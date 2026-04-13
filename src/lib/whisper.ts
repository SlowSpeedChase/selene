import { execFile } from 'child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { basename, join } from 'path';
import { promisify } from 'util';
import { config } from './config';
import { createWorkflowLogger } from './logger';

const log = createWorkflowLogger('whisper');
const execFileAsync = promisify(execFile);

export interface TranscriptionSegment {
  start: number; // seconds
  end: number;   // seconds
  text: string;
}

export interface TranscriptionResult {
  text: string;
  language: string | null;
  segments: TranscriptionSegment[];
  audioDurationSeconds: number;
  processingSeconds: number;
  backend: 'whisper.cpp';
  model: string;
  sourcePath: string;
}

export interface TranscribeOptions {
  language?: string;     // ISO code; omit or set to 'auto' for auto-detect
  binary?: string;       // override config.whisperBinary
  model?: string;        // override config.whisperModel
  threads?: number;      // override config.whisperThreads
  ffmpegBinary?: string; // default 'ffmpeg'
}

export class WhisperTranscriberError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'WhisperTranscriberError';
  }
}

export function isWhisperAvailable(opts: TranscribeOptions = {}): boolean {
  const binary = opts.binary ?? config.whisperBinary;
  const model = opts.model ?? config.whisperModel;
  return existsSync(binary) && existsSync(model);
}

export async function transcribeAudio(
  audioPath: string,
  opts: TranscribeOptions = {}
): Promise<TranscriptionResult> {
  if (!existsSync(audioPath)) {
    throw new WhisperTranscriberError(`Audio file not found: ${audioPath}`);
  }

  const binary = opts.binary ?? config.whisperBinary;
  const model = opts.model ?? config.whisperModel;
  const threads = opts.threads ?? config.whisperThreads;
  const ffmpeg = opts.ffmpegBinary ?? 'ffmpeg';
  const language = opts.language ?? 'auto';

  if (!existsSync(binary)) {
    throw new WhisperTranscriberError(
      `whisper.cpp binary not found at ${binary}. Install whisper.cpp or set WHISPER_BINARY.`
    );
  }
  if (!existsSync(model)) {
    throw new WhisperTranscriberError(
      `Whisper model not found at ${model}. Download a ggml model or set WHISPER_MODEL.`
    );
  }

  const work = mkdtempSync(join(tmpdir(), 'selene-whisper-'));
  const wavPath = join(work, 'audio.wav');
  const outPrefix = join(work, 'transcript');

  const startedAt = process.hrtime.bigint();
  try {
    // whisper.cpp wants 16kHz mono s16le WAV. Convert via ffmpeg regardless
    // of input format so we don't depend on whisper.cpp's optional codec
    // support.
    await runFfmpeg(ffmpeg, audioPath, wavPath);

    const args = [
      '-m', model,
      '-f', wavPath,
      '-t', String(threads),
      '-oj',              // emit JSON
      '-of', outPrefix,
      '-nt',              // no timestamps in printed output
    ];
    if (language && language !== 'auto') {
      args.push('-l', language);
    } else {
      args.push('-l', 'auto');
    }

    log.debug({ binary, model, threads, audioPath }, 'Invoking whisper.cpp');
    await execFileAsync(binary, args, { maxBuffer: 32 * 1024 * 1024 });

    const jsonPath = `${outPrefix}.json`;
    if (!existsSync(jsonPath)) {
      throw new WhisperTranscriberError(
        `whisper.cpp did not produce JSON output at ${jsonPath}`
      );
    }

    const raw = JSON.parse(readFileSync(jsonPath, 'utf8')) as WhisperCppJson;
    const segments = parseSegments(raw);
    const text = segments.map((s) => s.text).join(' ').replace(/\s+/g, ' ').trim();
    const duration = segments.length ? segments[segments.length - 1].end : 0;
    const elapsedMs = Number(process.hrtime.bigint() - startedAt) / 1e6;

    const result: TranscriptionResult = {
      text,
      language: raw?.result?.language ?? raw?.params?.language ?? null,
      segments,
      audioDurationSeconds: duration,
      processingSeconds: elapsedMs / 1000,
      backend: 'whisper.cpp',
      model,
      sourcePath: audioPath,
    };

    log.info(
      {
        file: basename(audioPath),
        chars: text.length,
        segments: segments.length,
        seconds: result.processingSeconds.toFixed(1),
      },
      'Transcribed audio'
    );
    return result;
  } catch (err) {
    if (err instanceof WhisperTranscriberError) throw err;
    throw new WhisperTranscriberError(
      `Transcription failed for ${basename(audioPath)}: ${(err as Error).message}`
    );
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

// ---- internals --------------------------------------------------------

interface WhisperCppSegment {
  timestamps?: { from?: string; to?: string };
  offsets?: { from?: number; to?: number };
  text?: string;
}

interface WhisperCppJson {
  result?: { language?: string };
  params?: { language?: string };
  transcription?: WhisperCppSegment[];
}

async function runFfmpeg(
  ffmpeg: string,
  input: string,
  output: string
): Promise<void> {
  const args = [
    '-hide_banner',
    '-loglevel', 'error',
    '-y',
    '-i', input,
    '-ar', '16000',
    '-ac', '1',
    '-c:a', 'pcm_s16le',
    output,
  ];
  try {
    await execFileAsync(ffmpeg, args, { maxBuffer: 16 * 1024 * 1024 });
  } catch (err) {
    const e = err as NodeJS.ErrnoException & { stderr?: string };
    if (e.code === 'ENOENT') {
      throw new WhisperTranscriberError(
        `ffmpeg not found on PATH. Install ffmpeg or set TranscribeOptions.ffmpegBinary.`
      );
    }
    throw new WhisperTranscriberError(
      `ffmpeg failed to convert ${basename(input)}: ${e.stderr?.trim() || e.message}`
    );
  }
}

function parseSegments(raw: WhisperCppJson): TranscriptionSegment[] {
  const out: TranscriptionSegment[] = [];
  for (const seg of raw.transcription ?? []) {
    const text = (seg.text ?? '').trim();
    if (!text) continue;
    const fromMs = seg.offsets?.from ?? parseTimestamp(seg.timestamps?.from);
    const toMs = seg.offsets?.to ?? parseTimestamp(seg.timestamps?.to);
    out.push({
      start: (fromMs ?? 0) / 1000,
      end: (toMs ?? 0) / 1000,
      text,
    });
  }
  return out;
}

function parseTimestamp(ts: string | undefined): number | null {
  // "HH:MM:SS,mmm"
  if (!ts) return null;
  const match = /^(\d+):(\d+):(\d+)[,.](\d+)$/.exec(ts);
  if (!match) return null;
  const [, h, m, s, ms] = match;
  return (
    parseInt(h, 10) * 3600_000 +
    parseInt(m, 10) * 60_000 +
    parseInt(s, 10) * 1000 +
    parseInt(ms, 10)
  );
}
