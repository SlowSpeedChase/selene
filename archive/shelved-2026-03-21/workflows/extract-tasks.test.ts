/**
 * Test: Auto-assignment of tasks to projects based on concept matching
 *
 * RED phase: This test should fail until we implement findMatchingProject()
 */

import assert from 'assert';
import Database from 'better-sqlite3';
import { findMatchingProject } from './extract-tasks';

const TEST_DB = ':memory:';

async function runTests() {
  console.log('Setting up test database...');

  const db = new Database(TEST_DB);

  // Create minimal schema
  db.exec(`
    CREATE TABLE projects (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      primary_concept TEXT,
      things_project_id TEXT,
      status TEXT DEFAULT 'active',
      last_active_at DATETIME,
      test_run TEXT
    );

    CREATE TABLE processed_notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      raw_note_id INTEGER NOT NULL,
      concepts TEXT
    );
  `);

  // Test 1: Returns project_id when concept matches
  console.log('\nTest 1: Returns project_id when concept matches');
  {
    // Setup: Create a project with primary_concept "productivity"
    db.prepare(`
      INSERT INTO projects (name, primary_concept, things_project_id, status)
      VALUES ('Productivity System', 'productivity', 'things-proj-123', 'active')
    `).run();

    // Setup: Note with concepts including "productivity"
    const noteId = 42;
    db.prepare(`
      INSERT INTO processed_notes (raw_note_id, concepts)
      VALUES (?, ?)
    `).run(noteId, JSON.stringify(['productivity', 'planning', 'adhd']));

    // Act
    const result = findMatchingProject(db, noteId);

    // Assert
    assert.strictEqual(result, 'things-proj-123',
      `Expected 'things-proj-123', got '${result}'`);

    console.log('  ✓ PASS');
  }

  // Test 2: Returns null when no concept matches
  console.log('\nTest 2: Returns null when no concept matches');
  {
    const noteId = 99;
    db.prepare(`
      INSERT INTO processed_notes (raw_note_id, concepts)
      VALUES (?, ?)
    `).run(noteId, JSON.stringify(['cooking', 'recipes']));

    const result = findMatchingProject(db, noteId);

    assert.strictEqual(result, null,
      `Expected null, got '${result}'`);

    console.log('  ✓ PASS');
  }

  // Test 3: Returns most recently active project when multiple match
  console.log('\nTest 3: Returns most recently active project when multiple match');
  {
    // Add another project with same concept but older activity
    db.prepare(`
      INSERT INTO projects (name, primary_concept, things_project_id, status, last_active_at)
      VALUES ('Old Project', 'planning', 'things-old-456', 'active', '2025-01-01')
    `).run();

    db.prepare(`
      INSERT INTO projects (name, primary_concept, things_project_id, status, last_active_at)
      VALUES ('New Project', 'planning', 'things-new-789', 'active', '2026-01-10')
    `).run();

    const noteId = 100;
    db.prepare(`
      INSERT INTO processed_notes (raw_note_id, concepts)
      VALUES (?, ?)
    `).run(noteId, JSON.stringify(['planning', 'tasks']));

    const result = findMatchingProject(db, noteId);

    assert.strictEqual(result, 'things-new-789',
      `Expected 'things-new-789' (most recent), got '${result}'`);

    console.log('  ✓ PASS');
  }

  db.close();
  console.log('\n✓ All tests passed!');
}

runTests().catch(err => {
  console.error('\n✗ Test failed:', err.message);
  process.exit(1);
});
