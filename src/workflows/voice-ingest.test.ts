import assert from 'node:assert';
import { mkdtempSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { redirectSeleneSingleton } from '../lib/test-two-file-db';

// Redirect the db.ts singleton to throwaway files BEFORE importing the module-under-test.
// voice-ingest (via ./ingest) and ../lib/voice-transcriptions-db transitively import src/lib/db,
// which opens a real DB connection on import; the redirect makes that import harmless under jest.
const { restore } = redirectSeleneSingleton('selene-voice-ingest-test-');

import * as voiceIngestMod from './voice-ingest';
import { computeArchiveTarget } from './voice-ingest';
import * as voiceTranscriptionsDb from '../lib/voice-transcriptions-db';
import * as whisper from '../lib/whisper';
import * as voiceMemosReader from '../lib/voice-memos-reader';

describe('voice-ingest', () => {
  const work = mkdtempSync(join(tmpdir(), 'selene-voice-ingest-test-'));

  afterAll(() => {
    rmSync(work, { recursive: true, force: true });
    restore();
  });

  it('voice-ingest module exports main functions', () => {
    const mod = voiceIngestMod;
    assert.strictEqual(typeof mod.voiceIngest, 'function', 'voiceIngest should be a function');
    assert.strictEqual(typeof mod.voiceIngestOne, 'function', 'voiceIngestOne should be a function');
    assert.strictEqual(
      typeof mod.computeArchiveTarget,
      'function',
      'computeArchiveTarget should be a function'
    );
  });

  it('computeArchiveTarget builds YYYY/MM layout from recordedAt', () => {
    const memo = {
      uniqueId: 'ABCDEF12-3456-7890',
      pk: 1,
      title: 'Test memo',
      path: '/tmp/source/20260411 100500.m4a',
      recordedAt: new Date(Date.UTC(2026, 3, 11, 15, 5, 0)), // 2026-04-11
      durationSeconds: 30,
      customLabel: null,
      folderId: null,
    };
    const target = computeArchiveTarget(work, memo);
    assert.strictEqual(target.dir, join(work, '2026', '04'));
    assert.strictEqual(target.path, join(work, '2026', '04', '20260411 100500.m4a'));
  });

  it('voice-transcriptions-db exports lifecycle helpers', () => {
    const dbMod = voiceTranscriptionsDb;
    assert.strictEqual(typeof dbMod.isVoiceMemoProcessed, 'function');
    assert.strictEqual(typeof dbMod.upsertPendingVoiceMemo, 'function');
    assert.strictEqual(typeof dbMod.markVoiceMemoTranscribed, 'function');
    assert.strictEqual(typeof dbMod.markVoiceMemoArchived, 'function');
    assert.strictEqual(typeof dbMod.markVoiceMemoFailed, 'function');
    assert.strictEqual(dbMod.VOICE_STATUS.PENDING, 'pending');
    assert.strictEqual(dbMod.VOICE_STATUS.ARCHIVED, 'archived');
  });

  it('whisper module exports transcribeAudio/isWhisperAvailable', () => {
    const mod = whisper;
    assert.strictEqual(typeof mod.transcribeAudio, 'function');
    assert.strictEqual(typeof mod.isWhisperAvailable, 'function');
  });

  it('voice-memos-reader exports list/get/availability helpers', () => {
    const mod = voiceMemosReader;
    assert.strictEqual(typeof mod.listVoiceMemos, 'function');
    assert.strictEqual(typeof mod.getVoiceMemo, 'function');
    assert.strictEqual(typeof mod.isVoiceMemosAvailable, 'function');
    assert.strictEqual(typeof mod.voiceMemoFileExists, 'function');
  });
});
