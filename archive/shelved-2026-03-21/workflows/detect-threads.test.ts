/**
 * Test: findBestThread logic for assigning notes to existing threads
 *
 * Tests the pure logic function that determines which thread (if any)
 * a note should be assigned to based on its vector similarity neighbors.
 */

import assert from 'assert';
import { findBestThread } from './detect-threads';

async function runTests() {
  console.log('Testing findBestThread logic...\n');

  // Test 1: Returns thread ID when multiple neighbors are in the same thread
  console.log('Test 1: Returns thread ID when multiple neighbors are in the same thread');
  {
    const neighbors = [
      { id: 10, distance: 0.5 },
      { id: 11, distance: 0.6 },
      { id: 12, distance: 0.8 },
      { id: 13, distance: 1.5 },
    ];
    // Map of note ID -> thread ID
    const threadMembership = new Map<number, number>([
      [10, 1],
      [11, 1],
      [13, 2],
    ]);

    const result = findBestThread(neighbors, threadMembership, {
      maxDistance: 1.0,
      minNeighbors: 2,
    });

    assert.notStrictEqual(result, null, 'Expected a ThreadMatch, got null');
    assert.strictEqual(result!.threadId, 1, `Expected threadId 1, got ${result!.threadId}`);
    assert.ok(typeof result!.relevanceScore === 'number', 'Expected relevanceScore to be a number');

    console.log('  ✓ PASS\n');
  }

  // Test 2: Returns null when no neighbors are in threads
  console.log('Test 2: Returns null when no neighbors are in threads');
  {
    const neighbors = [
      { id: 10, distance: 0.5 },
      { id: 11, distance: 0.6 },
    ];
    const threadMembership = new Map<number, number>();

    const result = findBestThread(neighbors, threadMembership, {
      maxDistance: 1.0,
      minNeighbors: 2,
    });

    assert.strictEqual(result, null, `Expected null, got ${JSON.stringify(result)}`);

    console.log('  ✓ PASS\n');
  }

  // Test 3: Returns null when only 1 neighbor is in a thread (below minNeighbors)
  console.log('Test 3: Returns null when only 1 neighbor is in a thread (below minNeighbors)');
  {
    const neighbors = [
      { id: 10, distance: 0.5 },
      { id: 11, distance: 0.6 },
    ];
    const threadMembership = new Map<number, number>([[10, 1]]);

    const result = findBestThread(neighbors, threadMembership, {
      maxDistance: 1.0,
      minNeighbors: 2,
    });

    assert.strictEqual(result, null, `Expected null, got ${JSON.stringify(result)}`);

    console.log('  ✓ PASS\n');
  }

  // Test 4: Returns null when neighbors are too far (above maxDistance)
  console.log('Test 4: Returns null when neighbors are too far (above maxDistance)');
  {
    const neighbors = [
      { id: 10, distance: 1.5 },
      { id: 11, distance: 1.8 },
    ];
    const threadMembership = new Map<number, number>([
      [10, 1],
      [11, 1],
    ]);

    const result = findBestThread(neighbors, threadMembership, {
      maxDistance: 1.0,
      minNeighbors: 2,
    });

    assert.strictEqual(result, null, `Expected null, got ${JSON.stringify(result)}`);

    console.log('  ✓ PASS\n');
  }

  // Test 5: Picks the thread with the most neighbors when multiple threads match
  console.log('Test 5: Picks the thread with the most neighbors when multiple threads match');
  {
    const neighbors = [
      { id: 10, distance: 0.3 },
      { id: 11, distance: 0.4 },
      { id: 12, distance: 0.5 },
      { id: 13, distance: 0.6 },
    ];
    const threadMembership = new Map<number, number>([
      [10, 1],
      [11, 2],
      [12, 2],
      [13, 2],
    ]);

    const result = findBestThread(neighbors, threadMembership, {
      maxDistance: 1.0,
      minNeighbors: 2,
    });

    assert.notStrictEqual(result, null, 'Expected a ThreadMatch, got null');
    assert.strictEqual(result!.threadId, 2, `Expected threadId 2 (most neighbors), got ${result!.threadId}`);

    console.log('  ✓ PASS\n');
  }

  console.log('✓ All tests passed!');
}

runTests().catch((err) => {
  console.error('\n✗ Test failed:', err.message);
  process.exit(1);
});
