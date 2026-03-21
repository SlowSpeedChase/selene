/**
 * Verify Thread Quality Script
 *
 * Compares detected threads against expected clusters from test-notes.json.
 * Outputs quality metrics and identifies misclassifications.
 *
 * Usage: npx ts-node scripts/verify-thread-quality.ts [--verbose]
 */

import * as fs from 'fs';
import * as path from 'path';
import Database from 'better-sqlite3';

const DB_PATH = path.join(__dirname, '..', 'data', 'selene.db');
const TEST_NOTES_PATH = path.join(__dirname, 'test-notes.json');
const TEST_RUN_MARKER = 'seed-test';

interface TestNote {
  title: string;
  content: string;
  created_at: string;
  expected_cluster: string;
  tags?: string[];
  edge_case?: string;
}

interface TestNotesFile {
  clusters: Record<string, {
    expected_thread_name: string | null;
    description: string;
  }>;
  notes: TestNote[];
}

interface DbThread {
  id: number;
  name: string;
  why: string;
  note_count: number;
}

interface DbThreadNote {
  thread_id: number;
  thread_name: string;
  note_id: number;
  note_title: string;
}

interface DbNote {
  id: number;
  title: string;
  content: string;
}

function loadTestNotes(): TestNotesFile {
  return JSON.parse(fs.readFileSync(TEST_NOTES_PATH, 'utf-8'));
}

function getDetectedThreads(db: Database.Database): DbThread[] {
  return db.prepare(`
    SELECT id, name, why, note_count
    FROM threads
    ORDER BY note_count DESC
  `).all() as DbThread[];
}

function getThreadNotes(db: Database.Database): DbThreadNote[] {
  return db.prepare(`
    SELECT
      tn.thread_id,
      t.name as thread_name,
      rn.id as note_id,
      rn.title as note_title
    FROM thread_notes tn
    JOIN threads t ON tn.thread_id = t.id
    JOIN raw_notes rn ON tn.raw_note_id = rn.id
    WHERE rn.test_run = ?
    ORDER BY t.id, rn.id
  `).all(TEST_RUN_MARKER) as DbThreadNote[];
}

function getUnthreadedNotes(db: Database.Database): DbNote[] {
  return db.prepare(`
    SELECT rn.id, rn.title, rn.content
    FROM raw_notes rn
    LEFT JOIN thread_notes tn ON rn.id = tn.raw_note_id
    WHERE rn.test_run = ? AND tn.thread_id IS NULL
    ORDER BY rn.id
  `).all(TEST_RUN_MARKER) as DbNote[];
}

function buildExpectedMap(testNotes: TestNotesFile): Map<string, string> {
  // Map note title -> expected cluster
  const map = new Map<string, string>();
  for (const note of testNotes.notes) {
    map.set(note.title, note.expected_cluster);
  }
  return map;
}

function matchThreadToCluster(
  threadName: string,
  clusterNotes: string[],
  testNotes: TestNotesFile
): { cluster: string; confidence: number } | null {
  // Count which expected cluster dominates this thread
  const clusterCounts: Record<string, number> = {};
  const expectedMap = buildExpectedMap(testNotes);

  for (const noteTitle of clusterNotes) {
    const expected = expectedMap.get(noteTitle);
    if (expected) {
      clusterCounts[expected] = (clusterCounts[expected] || 0) + 1;
    }
  }

  // Find dominant cluster
  let maxCluster = '';
  let maxCount = 0;
  for (const [cluster, count] of Object.entries(clusterCounts)) {
    if (count > maxCount) {
      maxCount = count;
      maxCluster = cluster;
    }
  }

  if (!maxCluster) return null;

  return {
    cluster: maxCluster,
    confidence: maxCount / clusterNotes.length,
  };
}

function analyzeResults(
  threads: DbThread[],
  threadNotes: DbThreadNote[],
  unthreaded: DbNote[],
  testNotes: TestNotesFile,
  verbose: boolean
): void {
  const expectedMap = buildExpectedMap(testNotes);

  // Group notes by thread
  const notesByThread = new Map<number, string[]>();
  for (const tn of threadNotes) {
    if (!notesByThread.has(tn.thread_id)) {
      notesByThread.set(tn.thread_id, []);
    }
    notesByThread.get(tn.thread_id)!.push(tn.note_title);
  }

  console.log('\n=== Thread Analysis ===\n');

  // Analyze each detected thread
  let totalCorrect = 0;
  let totalNotes = 0;
  const matchedClusters = new Set<string>();

  for (const thread of threads) {
    const notes = notesByThread.get(thread.id) || [];
    const match = matchThreadToCluster(thread.name, notes, testNotes);

    console.log(`Thread: "${thread.name}" (${notes.length} notes)`);
    console.log(`  Why: ${thread.why}`);

    if (match) {
      matchedClusters.add(match.cluster);
      const expectedName = testNotes.clusters[match.cluster]?.expected_thread_name;
      console.log(`  Best match: ${match.cluster} (${(match.confidence * 100).toFixed(0)}% confidence)`);
      console.log(`  Expected name: "${expectedName}"`);

      // Count correct assignments
      let correct = 0;
      let incorrect = 0;
      for (const noteTitle of notes) {
        const expected = expectedMap.get(noteTitle);
        if (expected === match.cluster) {
          correct++;
        } else {
          incorrect++;
          if (verbose) {
            console.log(`    ✗ "${noteTitle}" expected in ${expected}`);
          }
        }
      }
      totalCorrect += correct;
      totalNotes += notes.length;
      console.log(`  Correct: ${correct}/${notes.length}`);
    } else {
      console.log(`  No clear cluster match`);
      totalNotes += notes.length;
    }
    console.log();
  }

  // Analyze unthreaded notes
  console.log('=== Unthreaded Notes ===\n');

  let orphanCorrect = 0;
  let orphanIncorrect = 0;
  const missedClusters: Record<string, string[]> = {};

  for (const note of unthreaded) {
    const expected = expectedMap.get(note.title);
    if (expected === 'orphan' || expected === 'multi-topic' || expected === 'borderline') {
      orphanCorrect++;
      if (verbose) {
        console.log(`  ✓ "${note.title}" correctly unthreaded (${expected})`);
      }
    } else if (expected) {
      orphanIncorrect++;
      if (!missedClusters[expected]) {
        missedClusters[expected] = [];
      }
      missedClusters[expected].push(note.title);
      console.log(`  ✗ "${note.title}" should be in ${expected}`);
    }
  }

  console.log(`\nUnthreaded: ${unthreaded.length} notes`);
  console.log(`  Correctly unthreaded (orphans/edge): ${orphanCorrect}`);
  console.log(`  Incorrectly unthreaded (should cluster): ${orphanIncorrect}`);

  // Calculate expected clusters that weren't detected
  const allExpectedClusters = Object.keys(testNotes.clusters).filter(
    c => c !== 'orphan'
  );
  const missedClustersList = allExpectedClusters.filter(
    c => !matchedClusters.has(c)
  );

  if (missedClustersList.length > 0) {
    console.log('\n=== Missed Clusters ===\n');
    for (const cluster of missedClustersList) {
      const info = testNotes.clusters[cluster];
      console.log(`  "${info.expected_thread_name}" (${cluster}) - not detected`);
    }
  }

  // Summary metrics
  console.log('\n=== Quality Metrics ===\n');

  const threadedAccuracy = totalNotes > 0 ? (totalCorrect / totalNotes * 100).toFixed(1) : '0';
  const orphanAccuracy = (orphanCorrect + orphanIncorrect) > 0
    ? (orphanCorrect / (orphanCorrect + orphanIncorrect) * 100).toFixed(1)
    : '100';
  const clusterRecall = ((allExpectedClusters.length - missedClustersList.length) / allExpectedClusters.length * 100).toFixed(1);

  console.log(`Threads detected: ${threads.length}`);
  console.log(`Expected clusters: ${allExpectedClusters.length}`);
  console.log(`Cluster recall: ${clusterRecall}% (${allExpectedClusters.length - missedClustersList.length}/${allExpectedClusters.length})`);
  console.log(`Threaded note accuracy: ${threadedAccuracy}% (${totalCorrect}/${totalNotes})`);
  console.log(`Orphan handling: ${orphanAccuracy}% correct`);

  // Overall assessment
  console.log('\n=== Assessment ===\n');

  const clusterRecallNum = parseFloat(clusterRecall);
  const threadedAccuracyNum = parseFloat(threadedAccuracy);
  const orphanAccuracyNum = parseFloat(orphanAccuracy);

  if (clusterRecallNum >= 80 && threadedAccuracyNum >= 80 && orphanAccuracyNum >= 80) {
    console.log('✓ PASS - Thread detection quality is good');
  } else if (clusterRecallNum >= 60 && threadedAccuracyNum >= 60) {
    console.log('~ MARGINAL - Consider tuning parameters');
    console.log('\nSuggestions:');
    if (clusterRecallNum < 80) {
      console.log('  - Lower similarity threshold to catch more clusters');
    }
    if (threadedAccuracyNum < 80) {
      console.log('  - Raise similarity threshold for tighter clusters');
    }
  } else {
    console.log('✗ FAIL - Thread detection needs significant tuning');
  }
}

function main(): void {
  const verbose = process.argv.includes('--verbose') || process.argv.includes('-v');

  console.log('=== Verify Thread Quality ===\n');

  if (!fs.existsSync(DB_PATH)) {
    console.error(`Database not found: ${DB_PATH}`);
    process.exit(1);
  }

  const db = new Database(DB_PATH, { readonly: true });

  try {
    const testNotes = loadTestNotes();
    const threads = getDetectedThreads(db);
    const threadNotes = getThreadNotes(db);
    const unthreaded = getUnthreadedNotes(db);

    console.log(`Test notes file: ${testNotes.notes.length} notes`);
    console.log(`Detected threads: ${threads.length}`);
    console.log(`Notes in threads: ${threadNotes.length}`);
    console.log(`Unthreaded notes: ${unthreaded.length}`);

    if (threads.length === 0) {
      console.log('\nNo threads detected yet. Run:');
      console.log('  npx ts-node src/workflows/detect-threads.ts');
      return;
    }

    analyzeResults(threads, threadNotes, unthreaded, testNotes, verbose);

  } finally {
    db.close();
  }
}

main();
