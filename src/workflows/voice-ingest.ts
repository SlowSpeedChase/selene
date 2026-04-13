import { existsSync, mkdirSync, renameSync, statSync } from 'fs';
import { basename, dirname, extname, join } from 'path';
import { createWorkflowLogger } from '../lib';
import { config } from '../lib/config';
import {
  listVoiceMemos,
  getVoiceMemo,
  voiceMemoFileExists,
  type VoiceMemo,
} from '../lib/voice-memos-reader';
import {
  isWhisperAvailable,
  transcribeAudio,
  WhisperTranscriberError,
  type TranscriptionResult,
} from '../lib/whisper';
import {
  isVoiceMemoProcessed,
  markVoiceMemoArchived,
  markVoiceMemoFailed,
  markVoiceMemoTranscribed,
  upsertPendingVoiceMemo,
} from '../lib/voice-transcriptions-db';
import { ingest } from './ingest';

const log = createWorkflowLogger('voice-ingest');

const DEFAULT_TAGS = ['#voice', '#selene'];

export interface VoiceIngestOptions {
  limit?: number;
  archiveRoot?: string;
  tags?: string[];
  language?: string;
}

export interface VoiceIngestResult {
  discovered: number;
  skipped: number;
  transcribed: number;
  archived: number;
  failed: number;
  errors: number;
  details: VoiceMemoResult[];
}

export interface VoiceMemoResult {
  uniqueId: string;
  title: string;
  success: boolean;
  noteId?: number;
  archivePath?: string;
  transcriptChars?: number;
  backend?: string;
  model?: string;
  error?: string;
}

export class VoiceIngestError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'VoiceIngestError';
  }
}

export async function voiceIngest(
  options: VoiceIngestOptions = {}
): Promise<VoiceIngestResult> {
  const archiveRoot = options.archiveRoot ?? config.voiceMemosOutputDir;
  const tags = options.tags ?? DEFAULT_TAGS;

  const stats: VoiceIngestResult = {
    discovered: 0,
    skipped: 0,
    transcribed: 0,
    archived: 0,
    failed: 0,
    errors: 0,
    details: [],
  };

  verifyArchiveRoot(archiveRoot);

  if (!isWhisperAvailable()) {
    throw new VoiceIngestError(
      `Whisper is not available. Checked WHISPER_BINARY=${config.whisperBinary} ` +
        `and WHISPER_MODEL=${config.whisperModel}.`
    );
  }

  const memos = listVoiceMemos({ limit: options.limit });
  stats.discovered = memos.length;
  log.info({ discovered: stats.discovered }, 'Discovered voice memos');

  for (const memo of memos) {
    if (isVoiceMemoProcessed(memo.uniqueId)) {
      stats.skipped++;
      continue;
    }

    const result = await processMemo(memo, {
      archiveRoot,
      tags,
      language: options.language,
    });
    stats.details.push(result);

    if (result.success) {
      stats.transcribed++;
      if (result.archivePath) stats.archived++;
    } else {
      stats.failed++;
      stats.errors++;
    }
  }

  log.info(
    {
      discovered: stats.discovered,
      skipped: stats.skipped,
      transcribed: stats.transcribed,
      archived: stats.archived,
      failed: stats.failed,
    },
    'Voice ingest run complete'
  );
  return stats;
}

export async function voiceIngestOne(
  uniqueId: string,
  options: VoiceIngestOptions = {}
): Promise<VoiceMemoResult> {
  const memo = getVoiceMemo(uniqueId);
  if (!memo) {
    throw new VoiceIngestError(`Voice memo not found: ${uniqueId}`);
  }
  const archiveRoot = options.archiveRoot ?? config.voiceMemosOutputDir;
  verifyArchiveRoot(archiveRoot);
  if (!isWhisperAvailable()) {
    throw new VoiceIngestError('Whisper is not available. Check WHISPER_BINARY / WHISPER_MODEL.');
  }
  return processMemo(memo, {
    archiveRoot,
    tags: options.tags ?? DEFAULT_TAGS,
    language: options.language,
  });
}

// ---- internals --------------------------------------------------------

interface ProcessContext {
  archiveRoot: string;
  tags: string[];
  language?: string;
}

async function processMemo(
  memo: VoiceMemo,
  ctx: ProcessContext
): Promise<VoiceMemoResult> {
  const result: VoiceMemoResult = {
    uniqueId: memo.uniqueId,
    title: memo.title,
    success: false,
  };

  if (!voiceMemoFileExists(memo)) {
    const error = `Audio file missing on disk: ${memo.path}`;
    log.warn({ uniqueId: memo.uniqueId, path: memo.path }, error);
    upsertPendingVoiceMemo({
      uniqueId: memo.uniqueId,
      title: memo.title,
      recordedAt: memo.recordedAt,
      durationSeconds: memo.durationSeconds,
    });
    markVoiceMemoFailed(memo.uniqueId, error);
    result.error = error;
    return result;
  }

  upsertPendingVoiceMemo({
    uniqueId: memo.uniqueId,
    title: memo.title,
    recordedAt: memo.recordedAt,
    durationSeconds: memo.durationSeconds,
  });

  // 1. Transcribe
  let transcription: TranscriptionResult;
  try {
    transcription = await transcribeAudio(memo.path, { language: ctx.language });
  } catch (err) {
    const error =
      err instanceof WhisperTranscriberError
        ? `Transcription failed: ${err.message}`
        : `Transcription failed: ${(err as Error).message}`;
    log.error({ uniqueId: memo.uniqueId, err: error }, 'Transcription failed');
    markVoiceMemoFailed(memo.uniqueId, error);
    result.error = error;
    return result;
  }

  result.transcriptChars = transcription.text.length;
  result.backend = transcription.backend;
  result.model = transcription.model;

  // 2. Ingest as a note (replaces the Drafts-based pipeline in the Python port)
  const noteContent = formatNoteContent(memo, transcription, ctx.tags);
  let noteId: number;
  try {
    const ingestResult = await ingest({
      title: memo.title,
      content: noteContent,
      created_at: memo.recordedAt.toISOString(),
      capture_type: 'voice',
    });
    if (ingestResult.duplicate && ingestResult.existingId) {
      noteId = ingestResult.existingId;
    } else if (ingestResult.id) {
      noteId = ingestResult.id;
    } else {
      throw new Error('ingest() returned neither id nor existingId');
    }
  } catch (err) {
    const error = `Ingest failed: ${(err as Error).message}`;
    log.error({ uniqueId: memo.uniqueId, err: error }, 'Ingest failed');
    markVoiceMemoFailed(memo.uniqueId, error);
    result.error = error;
    return result;
  }

  result.noteId = noteId;
  markVoiceMemoTranscribed({
    uniqueId: memo.uniqueId,
    noteId,
    backend: transcription.backend,
    model: transcription.model,
  });

  // 3. Archive audio file
  let archivePath: string;
  try {
    archivePath = archiveAudio(memo, ctx.archiveRoot);
  } catch (err) {
    const error = `Archive failed: ${(err as Error).message}`;
    log.error({ uniqueId: memo.uniqueId, err: error }, 'Archive failed');
    markVoiceMemoFailed(memo.uniqueId, error);
    result.error = error;
    return result;
  }

  markVoiceMemoArchived(memo.uniqueId, archivePath);
  result.archivePath = archivePath;
  result.success = true;
  return result;
}

function formatNoteContent(
  memo: VoiceMemo,
  transcription: TranscriptionResult,
  tags: string[]
): string {
  const recordedIso = memo.recordedAt.toISOString();
  const duration = `${Math.round(memo.durationSeconds)}s`;
  const lang = transcription.language ?? '?';
  const meta =
    `[Voice note · ${recordedIso} · ${duration} · lang=${lang} · ` +
    `${transcription.backend}/${basename(transcription.model)}]`;
  const transcript = transcription.text.trim() || '(no speech detected)';
  const tagLine = tags.length ? `\n\n${tags.join(' ')}` : '';
  return `${meta}\n\n${transcript}${tagLine}\n`;
}

function verifyArchiveRoot(archiveRoot: string): void {
  // If the archive root lives under /Volumes/<drive>/, require the drive
  // directory to already exist. Don't auto-create the mount itself; only
  // subfolders beneath it.
  const parts = archiveRoot.split('/').filter(Boolean);
  if (parts.length >= 2 && parts[0] === 'Volumes') {
    const volume = `/${parts[0]}/${parts[1]}`;
    if (!existsSync(volume)) {
      throw new VoiceIngestError(
        `Archive volume not mounted: ${volume}. Mount the drive and try again.`
      );
    }
  }
  try {
    mkdirSync(archiveRoot, { recursive: true });
  } catch (err) {
    throw new VoiceIngestError(
      `Cannot create archive root ${archiveRoot}: ${(err as Error).message}`
    );
  }
}

export function computeArchiveTarget(
  archiveRoot: string,
  memo: VoiceMemo
): { dir: string; path: string } {
  const year = String(memo.recordedAt.getUTCFullYear()).padStart(4, '0');
  const month = String(memo.recordedAt.getUTCMonth() + 1).padStart(2, '0');
  const dir = join(archiveRoot, year, month);
  const filename = basename(memo.path);
  return { dir, path: join(dir, filename) };
}

function archiveAudio(memo: VoiceMemo, archiveRoot: string): string {
  const { dir, path: initial } = computeArchiveTarget(archiveRoot, memo);
  try {
    mkdirSync(dir, { recursive: true });
  } catch (err) {
    throw new Error(`Cannot create archive subfolder ${dir}: ${(err as Error).message}`);
  }

  let target = initial;
  if (existsSync(target)) {
    // Don't overwrite — append a short unique-id suffix
    const ext = extname(memo.path);
    const stem = basename(memo.path, ext);
    target = join(dir, `${stem}__${memo.uniqueId.slice(0, 8)}${ext}`);
  }

  try {
    renameSync(memo.path, target);
  } catch (err) {
    const e = err as NodeJS.ErrnoException;
    if (e.code === 'EXDEV') {
      // Cross-device rename isn't supported; fall back to copy + delete.
      // Lazy-require fs to avoid importing copyFileSync at top level.
      const { copyFileSync, unlinkSync } = require('fs') as typeof import('fs');
      copyFileSync(memo.path, target);
      unlinkSync(memo.path);
    } else {
      throw new Error(`Failed to move ${memo.path} → ${target}: ${e.message}`);
    }
  }

  // Best-effort: move sidecar files (waveform, etc.) living next to the .m4a
  try {
    const { readdirSync } = require('fs') as typeof import('fs');
    const parentDir = dirname(memo.path);
    const ext = extname(memo.path);
    const stem = basename(memo.path, ext);
    for (const entry of readdirSync(parentDir)) {
      if (!entry.startsWith(stem)) continue;
      if (entry === basename(memo.path)) continue;
      const src = join(parentDir, entry);
      const dst = join(dir, entry);
      try {
        renameSync(src, dst);
      } catch (err) {
        log.warn({ sibling: entry, err: (err as Error).message }, 'Failed to move sidecar');
      }
    }
  } catch {
    // Parent dir may no longer be readable once the primary file has moved;
    // that's fine — sidecars are best-effort.
  }

  // Safety check: the file (or its renamed equivalent) should now exist.
  try {
    statSync(target);
  } catch {
    throw new Error(`Archive target not present after move: ${target}`);
  }

  log.info({ from: basename(memo.path), to: target }, 'Archived audio');
  return target;
}

// CLI entry point
if (require.main === module) {
  const limitArg = process.argv[2];
  const limit = limitArg ? parseInt(limitArg, 10) : undefined;
  voiceIngest(limit !== undefined && !Number.isNaN(limit) ? { limit } : {})
    .then((result) => {
      console.log('Voice ingest complete:', {
        discovered: result.discovered,
        skipped: result.skipped,
        transcribed: result.transcribed,
        archived: result.archived,
        failed: result.failed,
      });
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Voice ingest failed:', err);
      process.exit(1);
    });
}
