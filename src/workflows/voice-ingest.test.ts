import assert from 'node:assert';
import { mkdtempSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';

async function runTests() {
  let passed = 0;
  const work = mkdtempSync(join(tmpdir(), 'selene-voice-ingest-test-'));

  try {
    // Test 1: module imports without throwing
    {
      const mod = await import('./voice-ingest');
      assert.strictEqual(typeof mod.voiceIngest, 'function', 'voiceIngest should be a function');
      assert.strictEqual(typeof mod.voiceIngestOne, 'function', 'voiceIngestOne should be a function');
      assert.strictEqual(
        typeof mod.computeArchiveTarget,
        'function',
        'computeArchiveTarget should be a function'
      );
      passed++;
      console.log('PASS 1: voice-ingest module exports main functions');
    }

    // Test 2: computeArchiveTarget places files under YYYY/MM
    {
      const { computeArchiveTarget } = await import('./voice-ingest');
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
      passed++;
      console.log('PASS 2: computeArchiveTarget builds YYYY/MM layout from recordedAt');
    }

    // Test 3: voice-transcriptions-db module creates the table on import
    {
      const dbMod = await import('../lib/voice-transcriptions-db');
      assert.strictEqual(typeof dbMod.isVoiceMemoProcessed, 'function');
      assert.strictEqual(typeof dbMod.upsertPendingVoiceMemo, 'function');
      assert.strictEqual(typeof dbMod.markVoiceMemoTranscribed, 'function');
      assert.strictEqual(typeof dbMod.markVoiceMemoArchived, 'function');
      assert.strictEqual(typeof dbMod.markVoiceMemoFailed, 'function');
      assert.strictEqual(dbMod.VOICE_STATUS.PENDING, 'pending');
      assert.strictEqual(dbMod.VOICE_STATUS.ARCHIVED, 'archived');
      passed++;
      console.log('PASS 3: voice-transcriptions-db exports lifecycle helpers');
    }

    // Test 4: whisper module exposes transcribe + availability helpers
    {
      const mod = await import('../lib/whisper');
      assert.strictEqual(typeof mod.transcribeAudio, 'function');
      assert.strictEqual(typeof mod.isWhisperAvailable, 'function');
      passed++;
      console.log('PASS 4: whisper module exports transcribeAudio/isWhisperAvailable');
    }

    // Test 5: voice-memos-reader exposes list/get helpers
    {
      const mod = await import('../lib/voice-memos-reader');
      assert.strictEqual(typeof mod.listVoiceMemos, 'function');
      assert.strictEqual(typeof mod.getVoiceMemo, 'function');
      assert.strictEqual(typeof mod.isVoiceMemosAvailable, 'function');
      assert.strictEqual(typeof mod.voiceMemoFileExists, 'function');
      passed++;
      console.log('PASS 5: voice-memos-reader exports list/get/availability helpers');
    }

    console.log(`\nAll ${passed}/5 voice-ingest tests passed.`);
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
