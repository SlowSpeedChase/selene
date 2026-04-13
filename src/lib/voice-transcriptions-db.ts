import { db } from './db';

export const VOICE_STATUS = {
  PENDING: 'pending',
  TRANSCRIBED: 'transcribed',
  ARCHIVED: 'archived',
  FAILED: 'failed',
} as const;

export type VoiceStatus = (typeof VOICE_STATUS)[keyof typeof VOICE_STATUS];

export interface VoiceTranscriptionRecord {
  uniqueId: string;
  title: string;
  recordedAt: string;          // ISO-8601 UTC
  durationSeconds: number;
  status: VoiceStatus;
  transcribedAt: string | null;
  noteId: number | null;       // raw_notes.id once ingested
  archivePath: string | null;
  backend: string | null;
  model: string | null;
  errorMessage: string | null;
  attempts: number;
  createdAt: string;
  updatedAt: string;
}

// Ensure the tracking table exists on module load. Matches the inline-schema
// pattern used for other ephemeral tables in db.ts.
db.exec(`
  CREATE TABLE IF NOT EXISTS voice_transcriptions (
    unique_id        TEXT PRIMARY KEY,
    title            TEXT NOT NULL,
    recorded_at      TEXT NOT NULL,
    duration_seconds REAL NOT NULL,
    transcribed_at   TEXT,
    note_id          INTEGER,
    archive_path     TEXT,
    backend          TEXT,
    model            TEXT,
    status           TEXT NOT NULL,
    error_message    TEXT,
    attempts         INTEGER NOT NULL DEFAULT 0,
    created_at       TEXT NOT NULL,
    updated_at       TEXT NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_voice_status ON voice_transcriptions(status);
  CREATE INDEX IF NOT EXISTS idx_voice_recorded_at ON voice_transcriptions(recorded_at);
`);

// ---- queries ----------------------------------------------------------

export function isVoiceMemoProcessed(uniqueId: string): boolean {
  const row = db
    .prepare('SELECT status FROM voice_transcriptions WHERE unique_id = ?')
    .get(uniqueId) as { status: string } | undefined;
  return !!row && row.status === VOICE_STATUS.ARCHIVED;
}

export function getVoiceTranscription(
  uniqueId: string
): VoiceTranscriptionRecord | null {
  const row = db
    .prepare(
      'SELECT unique_id, title, recorded_at, duration_seconds, transcribed_at, ' +
        'note_id, archive_path, backend, model, status, error_message, ' +
        'attempts, created_at, updated_at ' +
        'FROM voice_transcriptions WHERE unique_id = ?'
    )
    .get(uniqueId) as VoiceRow | undefined;
  return row ? rowToRecord(row) : null;
}

export function upsertPendingVoiceMemo(input: {
  uniqueId: string;
  title: string;
  recordedAt: Date;
  durationSeconds: number;
}): void {
  const now = new Date().toISOString();
  db.prepare(
    `INSERT INTO voice_transcriptions
       (unique_id, title, recorded_at, duration_seconds, status,
        attempts, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, 0, ?, ?)
     ON CONFLICT(unique_id) DO UPDATE SET
       title = excluded.title,
       recorded_at = excluded.recorded_at,
       duration_seconds = excluded.duration_seconds,
       updated_at = excluded.updated_at`
  ).run(
    input.uniqueId,
    input.title,
    input.recordedAt.toISOString(),
    input.durationSeconds,
    VOICE_STATUS.PENDING,
    now,
    now
  );
}

export function markVoiceMemoTranscribed(input: {
  uniqueId: string;
  noteId: number;
  backend: string;
  model: string;
}): void {
  const now = new Date().toISOString();
  db.prepare(
    `UPDATE voice_transcriptions
       SET status = ?, transcribed_at = ?, note_id = ?, backend = ?, model = ?,
           error_message = NULL, updated_at = ?
     WHERE unique_id = ?`
  ).run(
    VOICE_STATUS.TRANSCRIBED,
    now,
    input.noteId,
    input.backend,
    input.model,
    now,
    input.uniqueId
  );
}

export function markVoiceMemoArchived(uniqueId: string, archivePath: string): void {
  const now = new Date().toISOString();
  db.prepare(
    `UPDATE voice_transcriptions
       SET status = ?, archive_path = ?, updated_at = ?
     WHERE unique_id = ?`
  ).run(VOICE_STATUS.ARCHIVED, archivePath, now, uniqueId);
}

export function markVoiceMemoFailed(uniqueId: string, error: string): void {
  const now = new Date().toISOString();
  db.prepare(
    `UPDATE voice_transcriptions
       SET status = ?, error_message = ?, attempts = attempts + 1, updated_at = ?
     WHERE unique_id = ?`
  ).run(VOICE_STATUS.FAILED, error.slice(0, 2000), now, uniqueId);
}

export function listVoiceTranscriptionsByStatus(
  status: VoiceStatus
): VoiceTranscriptionRecord[] {
  const rows = db
    .prepare(
      'SELECT unique_id, title, recorded_at, duration_seconds, transcribed_at, ' +
        'note_id, archive_path, backend, model, status, error_message, ' +
        'attempts, created_at, updated_at ' +
        'FROM voice_transcriptions WHERE status = ? ORDER BY recorded_at DESC'
    )
    .all(status) as VoiceRow[];
  return rows.map(rowToRecord);
}

export function voiceTranscriptionStats(): Record<string, number> {
  const rows = db
    .prepare('SELECT status, COUNT(*) AS count FROM voice_transcriptions GROUP BY status')
    .all() as { status: string; count: number }[];
  const stats: Record<string, number> = {};
  for (const r of rows) stats[r.status] = r.count;
  return stats;
}

// ---- internals --------------------------------------------------------

interface VoiceRow {
  unique_id: string;
  title: string;
  recorded_at: string;
  duration_seconds: number;
  transcribed_at: string | null;
  note_id: number | null;
  archive_path: string | null;
  backend: string | null;
  model: string | null;
  status: string;
  error_message: string | null;
  attempts: number;
  created_at: string;
  updated_at: string;
}

function rowToRecord(row: VoiceRow): VoiceTranscriptionRecord {
  return {
    uniqueId: row.unique_id,
    title: row.title,
    recordedAt: row.recorded_at,
    durationSeconds: Number(row.duration_seconds),
    status: row.status as VoiceStatus,
    transcribedAt: row.transcribed_at,
    noteId: row.note_id,
    archivePath: row.archive_path,
    backend: row.backend,
    model: row.model,
    errorMessage: row.error_message,
    attempts: Number(row.attempts || 0),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}
