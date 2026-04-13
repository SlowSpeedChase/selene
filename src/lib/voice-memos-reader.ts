import Database from 'better-sqlite3';
import { copyFileSync, existsSync, mkdtempSync, rmSync, statSync } from 'fs';
import { tmpdir } from 'os';
import { isAbsolute, join, resolve } from 'path';
import { config } from './config';
import { createWorkflowLogger } from './logger';

const log = createWorkflowLogger('voice-memos-reader');

// Apple Cocoa reference date: 2001-01-01 00:00:00 UTC
const COCOA_EPOCH_MS = Date.UTC(2001, 0, 1, 0, 0, 0);

export interface VoiceMemo {
  uniqueId: string;       // ZUNIQUEID — stable identifier across syncs
  pk: number;             // ZCLOUDRECORDING.Z_PK
  title: string;
  path: string;           // absolute path to .m4a on disk
  recordedAt: Date;       // UTC
  durationSeconds: number;
  customLabel: string | null;
  folderId: number | null;
}

export interface ListVoiceMemosOptions {
  since?: Date;
  limit?: number;
}

export class VoiceMemosReaderError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'VoiceMemosReaderError';
  }
}

interface ReaderPaths {
  dbPath: string;
  recordingsDir: string;
}

function resolvePaths(overrides?: Partial<ReaderPaths>): ReaderPaths {
  const recordingsDir = overrides?.recordingsDir ?? config.voiceMemosRecordingsDir;
  const dbPath = overrides?.dbPath ?? join(recordingsDir, 'CloudRecordings.db');
  return { dbPath, recordingsDir };
}

export function isVoiceMemosAvailable(overrides?: Partial<ReaderPaths>): boolean {
  const { dbPath, recordingsDir } = resolvePaths(overrides);
  return existsSync(dbPath) && existsSync(recordingsDir);
}

export function listVoiceMemos(
  options: ListVoiceMemosOptions = {},
  overrides?: Partial<ReaderPaths>
): VoiceMemo[] {
  const paths = resolvePaths(overrides);
  if (!isVoiceMemosAvailable(paths)) {
    throw new VoiceMemosReaderError(
      `Voice Memos database not found at ${paths.dbPath}`
    );
  }

  return withSnapshot(paths.dbPath, (db) => {
    let sql =
      'SELECT Z_PK, ZUNIQUEID, ZCUSTOMLABEL, ZENCRYPTEDTITLE, ' +
      'ZPATH, ZDATE, ZDURATION, ZFOLDER ' +
      'FROM ZCLOUDRECORDING ' +
      'WHERE ZUNIQUEID IS NOT NULL AND ZPATH IS NOT NULL ' +
      'ORDER BY ZDATE DESC';
    if (options.limit !== undefined) {
      sql += ` LIMIT ${Math.max(0, Math.floor(options.limit))}`;
    }

    const rows = db.prepare(sql).all() as RawMemoRow[];
    const memos: VoiceMemo[] = [];
    for (const row of rows) {
      const memo = rowToMemo(row, paths.recordingsDir);
      if (!memo) continue;
      if (options.since && memo.recordedAt < options.since) continue;
      memos.push(memo);
    }

    log.debug(
      { count: memos.length, since: options.since, limit: options.limit },
      'Listed voice memos'
    );
    return memos;
  });
}

export function getVoiceMemo(
  uniqueId: string,
  overrides?: Partial<ReaderPaths>
): VoiceMemo | null {
  const paths = resolvePaths(overrides);
  if (!isVoiceMemosAvailable(paths)) {
    throw new VoiceMemosReaderError(
      `Voice Memos database not found at ${paths.dbPath}`
    );
  }

  return withSnapshot(paths.dbPath, (db) => {
    const row = db
      .prepare(
        'SELECT Z_PK, ZUNIQUEID, ZCUSTOMLABEL, ZENCRYPTEDTITLE, ' +
          'ZPATH, ZDATE, ZDURATION, ZFOLDER ' +
          'FROM ZCLOUDRECORDING WHERE ZUNIQUEID = ? LIMIT 1'
      )
      .get(uniqueId) as RawMemoRow | undefined;
    return row ? rowToMemo(row, paths.recordingsDir) : null;
  });
}

export function voiceMemoFileExists(memo: VoiceMemo): boolean {
  try {
    return statSync(memo.path).isFile();
  } catch {
    return false;
  }
}

// ---- internals --------------------------------------------------------

interface RawMemoRow {
  Z_PK: number;
  ZUNIQUEID: string | null;
  ZCUSTOMLABEL: string | null;
  ZENCRYPTEDTITLE: string | null;
  ZPATH: string | null;
  ZDATE: number | null;
  ZDURATION: number | null;
  ZFOLDER: number | null;
}

function withSnapshot<T>(
  dbPath: string,
  fn: (db: Database.Database) => T
): T {
  // Copy the live DB (+ WAL/SHM sidecars) to a temp file so we get a
  // consistent point-in-time view and never interfere with Voice Memos'
  // own writes.
  const tmp = mkdtempSync(join(tmpdir(), 'selene-voicememos-'));
  const snapshot = join(tmp, 'CloudRecordings.db');
  try {
    copyFileSync(dbPath, snapshot);
    for (const sidecar of ['-wal', '-shm']) {
      const src = dbPath + sidecar;
      if (existsSync(src)) {
        copyFileSync(src, snapshot + sidecar);
      }
    }

    const db = new Database(snapshot, { readonly: true });
    try {
      return fn(db);
    } finally {
      db.close();
    }
  } catch (err) {
    throw new VoiceMemosReaderError(
      `Failed to snapshot Voice Memos database: ${(err as Error).message}`
    );
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

function rowToMemo(row: RawMemoRow, recordingsDir: string): VoiceMemo | null {
  const uniqueId = row.ZUNIQUEID;
  const zPath = row.ZPATH;
  if (!uniqueId || !zPath) return null;

  const recordedAt = cocoaToDate(row.ZDATE);
  const path = resolveMemoPath(zPath, recordingsDir);
  const title = deriveTitle(row.ZENCRYPTEDTITLE, row.ZCUSTOMLABEL, recordedAt);

  return {
    uniqueId: String(uniqueId),
    pk: Number(row.Z_PK),
    title,
    path,
    recordedAt,
    durationSeconds: Number(row.ZDURATION ?? 0),
    customLabel: row.ZCUSTOMLABEL ? String(row.ZCUSTOMLABEL) : null,
    folderId: row.ZFOLDER !== null && row.ZFOLDER !== undefined ? Number(row.ZFOLDER) : null,
  };
}

function cocoaToDate(zDate: number | null): Date {
  if (zDate === null || zDate === undefined) {
    return new Date(COCOA_EPOCH_MS);
  }
  return new Date(COCOA_EPOCH_MS + Number(zDate) * 1000);
}

function resolveMemoPath(zPath: string, recordingsDir: string): string {
  if (isAbsolute(zPath)) return zPath;
  return resolve(recordingsDir, zPath);
}

function deriveTitle(
  encryptedTitle: string | null,
  customLabel: string | null,
  recordedAt: Date
): string {
  // Apple stores the user-visible title in ZENCRYPTEDTITLE (plain text in
  // current schema versions). Location auto-titles land here. ZCUSTOMLABEL
  // is often an ISO timestamp and is used as a fallback only.
  if (encryptedTitle && encryptedTitle.trim()) return encryptedTitle.trim();
  if (customLabel && customLabel.trim()) return customLabel.trim();
  const y = recordedAt.getUTCFullYear();
  const m = String(recordedAt.getUTCMonth() + 1).padStart(2, '0');
  const d = String(recordedAt.getUTCDate()).padStart(2, '0');
  const hh = String(recordedAt.getUTCHours()).padStart(2, '0');
  const mm = String(recordedAt.getUTCMinutes()).padStart(2, '0');
  return `Voice Memo ${y}-${m}-${d} ${hh}:${mm}`;
}
