import { existsSync, mkdirSync, readFileSync, writeFileSync, readdirSync, statSync, copyFileSync, unlinkSync } from 'fs';
import { join } from 'path';
import { execSync, execFileSync } from 'child_process';
import { createWorkflowLogger } from '../lib/logger';
import { config } from '../lib/config';
import { generate } from '../lib/ollama';
import type { ProcessedManifest, ProcessedFileEntry, VoiceMemoWorkflowResult } from '../types';

const log = createWorkflowLogger('transcribe-voice-memos');

const MANIFEST_FILENAME = '.processed.json';
const MIN_FILE_SIZE_BYTES = 1024; // 1KB - files smaller than this are likely not ready
const FILE_SETTLE_SECONDS = 5; // Skip files modified within the last N seconds
const WHISPER_TIMEOUT_MS = 10 * 60 * 1000; // 10 minutes

// ---------------------------------------------------------------------------
// macOS notification helper
// ---------------------------------------------------------------------------

function sendNotification(title: string, message: string): void {
  try {
    // Escape for AppleScript string (backslash and double-quote)
    const escapeAS = (s: string): string => s.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
    execSync(
      `osascript -e 'display notification "${escapeAS(message)}" with title "${escapeAS(title)}"'`
    );
  } catch {
    log.warn({ title, message }, 'Failed to send macOS notification');
  }
}

// ---------------------------------------------------------------------------
// Manifest management
// ---------------------------------------------------------------------------

function manifestPath(): string {
  return join(config.voiceMemosOutputDir, MANIFEST_FILENAME);
}

function loadManifest(): ProcessedManifest {
  const path = manifestPath();
  if (!existsSync(path)) {
    log.info('No existing manifest found, starting fresh');
    return { files: {} };
  }

  try {
    const raw = readFileSync(path, 'utf-8');
    const parsed = JSON.parse(raw) as ProcessedManifest;
    if (!parsed.files || typeof parsed.files !== 'object') {
      log.warn('Manifest missing "files" key, starting fresh');
      return { files: {} };
    }
    return parsed;
  } catch (err) {
    const error = err as Error;
    log.warn({ err: error }, 'Corrupt manifest file, starting fresh');
    return { files: {} };
  }
}

function saveManifest(manifest: ProcessedManifest): void {
  const dir = config.voiceMemosOutputDir;
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }
  writeFileSync(manifestPath(), JSON.stringify(manifest, null, 2));
}

// ---------------------------------------------------------------------------
// Preflight checks
// ---------------------------------------------------------------------------

function preflightChecks(): boolean {
  let ok = true;

  if (!existsSync(config.whisperBinary)) {
    const msg = `whisper.cpp binary not found at ${config.whisperBinary}`;
    log.error(msg);
    sendNotification('Selene Voice Memos', msg);
    ok = false;
  }

  if (!existsSync(config.whisperModel)) {
    const msg = `Whisper model not found at ${config.whisperModel}`;
    log.error(msg);
    sendNotification('Selene Voice Memos', msg);
    ok = false;
  }

  try {
    execSync('which ffmpeg', { stdio: 'pipe' });
  } catch {
    const msg = 'ffmpeg not found in PATH';
    log.error(msg);
    sendNotification('Selene Voice Memos', msg);
    ok = false;
  }

  return ok;
}

// ---------------------------------------------------------------------------
// File scanning
// ---------------------------------------------------------------------------

interface NewMemoFile {
  filename: string;
  fullPath: string;
}

function scanForNewFiles(manifest: ProcessedManifest): NewMemoFile[] {
  const recordingsDir = config.voiceMemosRecordingsDir;

  if (!existsSync(recordingsDir)) {
    log.warn({ recordingsDir }, 'Recordings directory does not exist');
    return [];
  }

  const now = Date.now();
  const entries = readdirSync(recordingsDir);
  const newFiles: NewMemoFile[] = [];

  for (const entry of entries) {
    // Only process .m4a files
    if (!entry.toLowerCase().endsWith('.m4a')) continue;

    // Skip already-processed files
    if (manifest.files[entry]) continue;

    const fullPath = join(recordingsDir, entry);

    try {
      const stat = statSync(fullPath);

      // Skip files that are too small (still being recorded)
      if (stat.size < MIN_FILE_SIZE_BYTES) {
        log.debug({ filename: entry, size: stat.size }, 'Skipping file: too small');
        continue;
      }

      // Skip files modified too recently (still being written)
      const ageSeconds = (now - stat.mtimeMs) / 1000;
      if (ageSeconds < FILE_SETTLE_SECONDS) {
        log.debug({ filename: entry, ageSeconds }, 'Skipping file: modified too recently');
        continue;
      }

      newFiles.push({ filename: entry, fullPath });
    } catch (err) {
      const error = err as Error;
      log.warn({ filename: entry, err: error }, 'Failed to stat file, skipping');
    }
  }

  return newFiles;
}

// ---------------------------------------------------------------------------
// Filename parsing
// ---------------------------------------------------------------------------

interface ParsedMemoName {
  date: string; // e.g. "2026-02-12"
  time: string; // e.g. "15:30:45"
  friendlyName: string; // e.g. "2026-02-12 15:30"
  filePrefix: string; // e.g. "2026-02-12-153045" (for output filenames)
}

function parseMemoFilename(filename: string): ParsedMemoName {
  // Voice Memos format: "20260212 153045.m4a" or "20260212 153045-HEXID.m4a"
  const match = filename.match(/^(\d{4})(\d{2})(\d{2})\s+(\d{2})(\d{2})(\d{2})(?:-[A-Fa-f0-9]+)?\.m4a$/);

  if (match) {
    const [, year, month, day, hour, minute, second] = match;
    return {
      date: `${year}-${month}-${day}`,
      time: `${hour}:${minute}:${second}`,
      friendlyName: `${year}-${month}-${day} ${hour}:${minute}`,
      filePrefix: `${year}-${month}-${day}-${hour}${minute}${second}`,
    };
  }

  // Fallback for unexpected naming: use current timestamp
  const now = new Date();
  const y = now.getFullYear();
  const mo = String(now.getMonth() + 1).padStart(2, '0');
  const d = String(now.getDate()).padStart(2, '0');
  const h = String(now.getHours()).padStart(2, '0');
  const mi = String(now.getMinutes()).padStart(2, '0');
  const s = String(now.getSeconds()).padStart(2, '0');
  const baseName = filename.replace(/\.m4a$/i, '');

  return {
    date: `${y}-${mo}-${d}`,
    time: `${h}:${mi}:${s}`,
    friendlyName: baseName,
    filePrefix: `${y}-${mo}-${d}-${h}${mi}${s}`,
  };
}

// ---------------------------------------------------------------------------
// Audio helpers
// ---------------------------------------------------------------------------

function convertToWav(inputPath: string, outputPath: string): void {
  execFileSync('ffmpeg', ['-i', inputPath, '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', outputPath, '-y'], {
    stdio: 'pipe',
  });
}

function transcribeWav(wavPath: string): string {
  const output = execFileSync(
    config.whisperBinary,
    ['-m', config.whisperModel, '-f', wavPath, '--no-timestamps', '-t', String(config.whisperThreads), '-l', 'en'],
    { stdio: 'pipe', timeout: WHISPER_TIMEOUT_MS }
  );
  return output.toString().trim();
}

function getAudioDuration(filePath: string): string {
  try {
    const output = execFileSync(
      'ffprobe',
      ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', filePath],
      { stdio: 'pipe' }
    );
    const totalSeconds = Math.round(parseFloat(output.toString().trim()));
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}m ${seconds}s`;
  } catch {
    return 'unknown';
  }
}

// ---------------------------------------------------------------------------
// LLM title generation
// ---------------------------------------------------------------------------

const TITLE_PROMPT_TEMPLATE = `Summarize this voice memo transcription as a short, descriptive title (5-8 words).
Return ONLY the title, no quotes or punctuation at the end.

Transcription:
`;

const MAX_TRANSCRIPTION_CHARS = 500;

async function generateMemoTitle(transcription: string, fallbackTitle: string): Promise<string> {
  if (!transcription.trim()) {
    log.info('Empty transcription, using fallback title');
    return fallbackTitle;
  }

  try {
    const truncated = transcription.slice(0, MAX_TRANSCRIPTION_CHARS);
    const prompt = TITLE_PROMPT_TEMPLATE + truncated;

    const result = await generate(prompt, {
      temperature: 0.3,
      maxTokens: 20,
      timeoutMs: 15000,
    });

    const title = result.trim().replace(/^["']+|[."']+$/g, '');

    if (!title || title.length < 3 || title.length > 100) {
      log.warn({ result, length: title?.length }, 'LLM returned invalid title, using fallback');
      return fallbackTitle;
    }

    log.info({ generatedTitle: title }, 'Generated LLM title for voice memo');
    return title;
  } catch (err) {
    const error = err as Error;
    log.warn({ err: error }, 'Failed to generate LLM title, using fallback');
    return fallbackTitle;
  }
}

// ---------------------------------------------------------------------------
// Send to Drafts app for review/editing
// ---------------------------------------------------------------------------

async function sendToDrafts(title: string, content: string): Promise<boolean> {
  try {
    const draftText = `${title}\n\n${content}`;
    const encoded = encodeURIComponent(draftText);
    const tag = encodeURIComponent('voice-memo');
    const url = `drafts://x-callback-url/create?text=${encoded}&tag=${tag}`;

    execFileSync('open', [url]);
    log.info({ title }, 'Sent to Drafts app for review');
    return true;
  } catch (err) {
    const error = err as Error;
    log.warn({ err: error }, 'Failed to send to Drafts app');
    return false;
  }
}

// ---------------------------------------------------------------------------
// Process a single voice memo
// ---------------------------------------------------------------------------

async function processMemo(
  memo: NewMemoFile,
  manifest: ProcessedManifest
): Promise<void> {
  const { filename, fullPath } = memo;
  log.info({ filename }, 'Processing voice memo');

  const parsed = parseMemoFilename(filename);
  const outputDir = config.voiceMemosOutputDir;
  const archiveDir = join(outputDir, 'archive');
  const transcriptsDir = join(outputDir, 'transcripts');

  // Ensure output directories exist
  mkdirSync(archiveDir, { recursive: true });
  mkdirSync(transcriptsDir, { recursive: true });

  // Temp WAV path
  const wavPath = join(outputDir, `_temp_${parsed.filePrefix}.wav`);

  try {
    // Step 1: Convert to WAV
    log.info({ filename }, 'Converting to WAV');
    convertToWav(fullPath, wavPath);

    // Step 2: Transcribe
    log.info({ filename }, 'Transcribing with whisper.cpp');
    const transcription = transcribeWav(wavPath);

    if (!transcription) {
      log.warn({ filename }, 'Empty transcription result');
    }

    // Step 3: Get audio duration
    const duration = getAudioDuration(fullPath);

    // Step 4: Archive original
    const archivePath = join(archiveDir, `${parsed.filePrefix}.m4a`);
    copyFileSync(fullPath, archivePath);
    log.info({ filename, archivePath }, 'Archived original');

    // Step 5: Write markdown transcript
    const markdownPath = join(transcriptsDir, `${parsed.filePrefix}.md`);
    const relativeArchivePath = `../archive/${parsed.filePrefix}.m4a`;
    const markdown = `# Voice Memo: ${parsed.friendlyName}

**Recorded:** ${parsed.date} ${parsed.time}
**Duration:** ${duration}
**Audio:** [Original recording](${relativeArchivePath})

---

${transcription}
`;
    writeFileSync(markdownPath, markdown);
    log.info({ markdownPath }, 'Transcript written');

    // Step 6: Generate title and send to Drafts for review
    const fallbackTitle = `Voice Memo ${parsed.friendlyName}`;
    const title = await generateMemoTitle(transcription, fallbackTitle);
    const ingested = await sendToDrafts(title, transcription);

    // Step 7: Update manifest
    const entry: ProcessedFileEntry = {
      transcribedAt: new Date().toISOString(),
      archivedTo: archivePath,
      markdownPath,
      ingestedToSelene: ingested,
      draftsTitle: title,
    };
    manifest.files[filename] = entry;
    saveManifest(manifest);

    // Step 8: Clean up temp WAV
    try {
      unlinkSync(wavPath);
    } catch {
      log.warn({ wavPath }, 'Failed to clean up temp WAV');
    }

    log.info({ filename, ingested, transcriptionLength: transcription.length }, 'Voice memo processed successfully');
  } catch (err) {
    const error = err as Error;

    // Clean up temp WAV on failure
    try {
      if (existsSync(wavPath)) unlinkSync(wavPath);
    } catch {
      // ignore cleanup errors
    }

    throw error;
  }
}

// ---------------------------------------------------------------------------
// Retry failed Drafts sends
// ---------------------------------------------------------------------------

async function retryFailedSends(manifest: ProcessedManifest): Promise<number> {
  let retried = 0;

  for (const [filename, entry] of Object.entries(manifest.files)) {
    if (entry.ingestedToSelene) continue;

    log.info({ filename }, 'Retrying failed Drafts send');

    try {
      if (!existsSync(entry.markdownPath)) {
        log.warn({ filename, markdownPath: entry.markdownPath }, 'Transcript file missing, cannot retry');
        continue;
      }

      const markdown = readFileSync(entry.markdownPath, 'utf-8');
      const parts = markdown.split('\n---\n');
      const transcription = parts.length > 1 ? parts.slice(1).join('\n---\n').trim() : markdown;

      const parsed = parseMemoFilename(filename);
      const fallbackTitle = `Voice Memo ${parsed.friendlyName}`;
      const title = await generateMemoTitle(transcription, fallbackTitle);

      const sent = await sendToDrafts(title, transcription);
      if (sent) {
        entry.ingestedToSelene = true;
        entry.draftsTitle = title;
        saveManifest(manifest);
        retried++;
        log.info({ filename }, 'Retry successful');
      }
    } catch (err) {
      const error = err as Error;
      log.warn({ filename, err: error }, 'Retry failed');
    }
  }

  return retried;
}

// ---------------------------------------------------------------------------
// Main workflow
// ---------------------------------------------------------------------------

export async function transcribeVoiceMemos(): Promise<VoiceMemoWorkflowResult> {
  log.info('Starting voice memo transcription workflow');

  const result: VoiceMemoWorkflowResult = {
    processed: 0,
    errors: 0,
    retried: 0,
    details: [],
  };

  // Preflight checks
  if (!preflightChecks()) {
    log.error('Preflight checks failed, aborting');
    return result;
  }

  // Load manifest
  const manifest = loadManifest();
  const processedCount = Object.keys(manifest.files).length;
  log.info({ processedCount }, 'Manifest loaded');

  // Scan for new files
  const newFiles = scanForNewFiles(manifest);
  log.info({ newFileCount: newFiles.length }, 'Scanned for new voice memos');

  // Process each new file
  for (const memo of newFiles) {
    try {
      await processMemo(memo, manifest);
      result.processed++;
      result.details.push({ filename: memo.filename, success: true });
    } catch (err) {
      const error = err as Error;
      log.error({ filename: memo.filename, err: error }, 'Failed to process voice memo');
      sendNotification('Selene Voice Memos', `Failed to transcribe ${memo.filename}: ${error.message}`);
      result.errors++;
      result.details.push({ filename: memo.filename, success: false, error: error.message });
    }
  }

  // Retry failed ingestions
  result.retried = await retryFailedSends(manifest);

  log.info(
    { processed: result.processed, errors: result.errors, retried: result.retried },
    'Voice memo transcription workflow complete'
  );

  return result;
}

// CLI entry point
if (require.main === module) {
  transcribeVoiceMemos()
    .then((result) => {
      console.log('Voice memo transcription complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Voice memo transcription failed:', err);
      process.exit(1);
    });
}
