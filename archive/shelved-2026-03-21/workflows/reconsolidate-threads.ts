import { createWorkflowLogger, db, generate, ContextBuilder } from '../lib';
import type { FidelityTier } from '../lib/context-builder';
import { normalizeThreadName } from '../lib/strings';
import type { WorkflowResult } from '../types';
import { writeFileSync, existsSync, mkdirSync, unlinkSync } from 'fs';
import { join } from 'path';

const log = createWorkflowLogger('reconsolidate-threads');

// Configuration
const MAX_NOTES_PER_SYNTHESIS = 30;

// Types
interface ThreadRecord {
  id: number;
  name: string;
  why: string | null;
  summary: string | null;
  status: string;
  updated_at: string;
}

interface NoteRecord {
  id: number;
  title: string;
  content: string;
  created_at: string;
  essence: string | null;
  primary_theme: string | null;
  concepts: string | null;
  fidelity_tier: FidelityTier;
}

interface ThreadSynthesis {
  name: string;
  summary: string;
  why: string;
  direction: 'exploring' | 'emerging' | 'clear';
  shifted: boolean;
}

interface MomentumData {
  thread_id: number;
  notes_7_days: number;
  notes_30_days: number;
}

interface ExportableThread {
  id: number;
  name: string;
  why: string | null;
  summary: string | null;
  status: string;
  note_count: number;
  momentum_score: number | null;
  last_activity_at: string | null;
  created_at: string;
}

interface LinkedNote {
  id: number;
  title: string;
  created_at: string;
  exported_to_obsidian: number;
}

/**
 * Find threads that have new notes since their last update
 */
function getThreadsNeedingUpdate(): ThreadRecord[] {
  // Find threads where the most recent note addition is newer than the thread's updated_at
  return db
    .prepare(
      `SELECT t.id, t.name, t.why, t.summary, t.status, t.updated_at
       FROM threads t
       WHERE t.status = 'active'
         AND EXISTS (
           SELECT 1 FROM thread_notes tn
           WHERE tn.thread_id = t.id
             AND tn.added_at > t.updated_at
         )
       ORDER BY t.updated_at ASC`
    )
    .all() as ThreadRecord[];
}

/**
 * Get notes for a thread, prioritizing recent ones
 */
function getThreadNotes(threadId: number, limit: number): NoteRecord[] {
  return db
    .prepare(
      `SELECT rn.id, rn.title, rn.content, rn.created_at,
              pn.essence, pn.primary_theme, pn.concepts,
              COALESCE(pn.fidelity_tier, 'full') as fidelity_tier
       FROM raw_notes rn
       JOIN thread_notes tn ON rn.id = tn.raw_note_id
       LEFT JOIN processed_notes pn ON rn.id = pn.raw_note_id
       WHERE tn.thread_id = ?
       ORDER BY rn.created_at DESC
       LIMIT ?`
    )
    .all(threadId, limit) as NoteRecord[];
}

/**
 * Build LLM prompt for thread resynthesis
 */
function buildResynthesisPrompt(thread: ThreadRecord, notes: NoteRecord[]): string {
  const builder = new ContextBuilder(3000);

  for (const note of notes) {
    builder.addNote({
      id: note.id,
      title: `${note.title} (${note.created_at})`,
      content: note.content,
      essence: note.essence,
      primary_theme: note.primary_theme,
      concepts: note.concepts,
      fidelity_tier: note.fidelity_tier,
    });
  }

  const noteTexts = builder.build();

  return `Thread: ${thread.name}
Previous summary: ${thread.summary || '(none)'}
Previous "why": ${thread.why || '(none)'}

Notes in this thread (newest first):
${noteTexts}

Questions:
1. Has the direction of this thread shifted?
2. What is the updated summary?
3. Has the underlying motivation become clearer or changed?

Respond ONLY with valid JSON:
{
  "name": "${thread.name}",
  "summary": "...",
  "why": "...",
  "direction": "exploring|emerging|clear",
  "shifted": true or false
}`;
}

/**
 * Parse LLM response into ThreadSynthesis
 */
function parseSynthesis(response: string, defaultName: string): ThreadSynthesis | null {
  try {
    // Extract JSON from response (handle markdown code blocks)
    const jsonMatch = response.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      log.warn({ response }, 'No JSON found in LLM response');
      return null;
    }

    const parsed = JSON.parse(jsonMatch[0]);

    // Validate and provide defaults
    return {
      name: normalizeThreadName(parsed.name || defaultName),
      summary: parsed.summary || '',
      why: parsed.why || '',
      direction: ['exploring', 'emerging', 'clear'].includes(parsed.direction)
        ? parsed.direction
        : 'exploring',
      shifted: typeof parsed.shifted === 'boolean' ? parsed.shifted : false,
    };
  } catch (err) {
    log.error({ err, response }, 'Failed to parse LLM response');
    return null;
  }
}

/**
 * Update a thread with new synthesis
 */
function updateThread(thread: ThreadRecord, synthesis: ThreadSynthesis): void {
  const now = new Date().toISOString();

  // Update thread record
  db.prepare(
    `UPDATE threads
     SET name = ?, summary = ?, why = ?, updated_at = ?
     WHERE id = ?`
  ).run(synthesis.name, synthesis.summary, synthesis.why, now, thread.id);

  // Record in history
  db.prepare(
    `INSERT INTO thread_history (thread_id, summary_before, summary_after, change_type, created_at)
     VALUES (?, ?, ?, 'summarized', ?)`
  ).run(thread.id, thread.summary, synthesis.summary, now);

  log.info(
    { threadId: thread.id, name: synthesis.name, shifted: synthesis.shifted },
    'Thread updated'
  );
}

/**
 * Calculate momentum scores for all active threads.
 * Formula: (notes_7_days * 2) + (notes_30_days * 1) + (tasks_completed_7_days * 3)
 */
function calculateMomentum(): number {
  const now = new Date();
  const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString();

  // Check if thread_activity table exists
  const activityTableExists = db
    .prepare("SELECT COUNT(*) as count FROM sqlite_master WHERE type='table' AND name='thread_activity'")
    .get() as { count: number };

  // Get note counts per thread for 7-day and 30-day windows
  const momentumData = db
    .prepare(
      `SELECT
         t.id as thread_id,
         SUM(CASE WHEN tn.added_at >= ? THEN 1 ELSE 0 END) as notes_7_days,
         SUM(CASE WHEN tn.added_at >= ? THEN 1 ELSE 0 END) as notes_30_days
       FROM threads t
       LEFT JOIN thread_notes tn ON t.id = tn.thread_id
       WHERE t.status = 'active'
       GROUP BY t.id`
    )
    .all(sevenDaysAgo, thirtyDaysAgo) as MomentumData[];

  // Get task completion counts if table exists
  let taskCompletions: Record<number, number> = {};
  if (activityTableExists.count > 0) {
    const activityData = db
      .prepare(
        `SELECT thread_id, COUNT(*) as completed_count
         FROM thread_activity
         WHERE activity_type = 'task_completed'
           AND occurred_at >= ?
         GROUP BY thread_id`
      )
      .all(sevenDaysAgo) as { thread_id: number; completed_count: number }[];

    for (const row of activityData) {
      taskCompletions[row.thread_id] = row.completed_count;
    }
  }

  // Update momentum scores
  const updateStmt = db.prepare(
    `UPDATE threads SET momentum_score = ? WHERE id = ?`
  );

  let updated = 0;
  for (const data of momentumData) {
    const tasksCompleted = taskCompletions[data.thread_id] || 0;
    // Task completions weighted highest (3x) — progress feels good
    const momentum =
      (data.notes_7_days * 2) + (data.notes_30_days * 1) + (tasksCompleted * 3);

    updateStmt.run(momentum, data.thread_id);
    updated++;
  }

  log.info({ threadsUpdated: updated }, 'Momentum scores calculated');
  return updated;
}

/**
 * Create URL-friendly slug from thread name
 */
function createSlug(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-')
    .slice(0, 50);
}

/**
 * Get status emoji for thread
 */
function getStatusEmoji(status: string): string {
  const emojis: Record<string, string> = {
    active: '🔥',
    paused: '⏸️',
    completed: '✅',
    abandoned: '💤',
    archived: '📦',
    merged: '🔗',
  };
  return emojis[status] || '📌';
}

/**
 * Format date as YYYY-MM-DD
 */
function formatDate(dateStr: string | null): string {
  if (!dateStr) return 'unknown';
  return dateStr.split('T')[0];
}

/**
 * Get all threads for Obsidian export
 */
function getAllThreadsForExport(): ExportableThread[] {
  return db
    .prepare(
      `SELECT id, name, why, summary, status, note_count,
              momentum_score, last_activity_at, created_at
       FROM threads
       ORDER BY momentum_score DESC NULLS LAST`
    )
    .all() as ExportableThread[];
}

/**
 * Get linked notes for a thread
 */
function getLinkedNotesForExport(threadId: number): LinkedNote[] {
  return db
    .prepare(
      `SELECT r.id, r.title, r.created_at, r.exported_to_obsidian
       FROM raw_notes r
       JOIN thread_notes tn ON r.id = tn.raw_note_id
       WHERE tn.thread_id = ?
       ORDER BY r.created_at DESC`
    )
    .all(threadId) as LinkedNote[];
}

/**
 * Generate Obsidian markdown for a thread
 */
function generateThreadMarkdown(thread: ExportableThread, notes: LinkedNote[]): string {
  const statusEmoji = getStatusEmoji(thread.status);
  const momentum = thread.momentum_score?.toFixed(1) || '0.0';
  const lastActivity = formatDate(thread.last_activity_at);
  const created = formatDate(thread.created_at);
  const today = new Date().toISOString().split('T')[0];

  // Build frontmatter
  const frontmatter = `---
title: "${thread.name.replace(/"/g, '\\"')}"
type: thread
status: ${thread.status}
momentum: ${thread.momentum_score || 0}
note_count: ${thread.note_count}
last_activity: ${lastActivity}
created: ${created}
tags:
  - selene/thread
  - status/${thread.status}
---`;

  // Build why section
  const whySection = thread.why
    ? `## Why This Thread Exists

${thread.why}`
    : '';

  // Build summary section
  const summarySection = thread.summary
    ? `## Current Summary

${thread.summary}`
    : `## Current Summary

*No summary generated yet.*`;

  // Build status line
  const statusLine = `## Status

${statusEmoji} **${thread.status.charAt(0).toUpperCase() + thread.status.slice(1)}** | Momentum: ${momentum} | ${thread.note_count} notes`;

  // Build linked notes section
  let notesSection = '## Linked Notes\n\n';
  if (notes.length === 0) {
    notesSection += '*No notes linked yet.*';
  } else {
    for (const note of notes) {
      const noteDate = formatDate(note.created_at);
      const dateDisplay = new Date(note.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });

      if (note.exported_to_obsidian) {
        // Create wiki-link to exported note
        const slug = note.title
          .toLowerCase()
          .replace(/[^a-z0-9\s-]/g, '')
          .replace(/\s+/g, '-')
          .slice(0, 50);
        notesSection += `- [[${noteDate}-${slug}]] - ${dateDisplay}\n`;
      } else {
        // Just show title without link
        notesSection += `- "${note.title}" *(not exported)* - ${dateDisplay}\n`;
      }
    }
  }

  // Combine all sections
  return `${frontmatter}

# ${thread.name}

${whySection}

${summarySection}

${statusLine}

---

${notesSection}

---

*Last updated: ${today} by Selene*
`;
}

/**
 * Export all threads to Obsidian vault
 */
function exportThreadsToObsidian(): number {
  const vaultPath = process.env.OBSIDIAN_VAULT_PATH;
  if (!vaultPath) {
    log.warn('OBSIDIAN_VAULT_PATH not set, skipping thread export');
    return 0;
  }

  const threadsDir = join(vaultPath, 'Selene', 'Threads');
  const archiveDir = join(threadsDir, 'Archive');

  // Ensure both directories exist
  if (!existsSync(threadsDir)) {
    mkdirSync(threadsDir, { recursive: true });
    log.info({ threadsDir }, 'Created Threads directory');
  }
  if (!existsSync(archiveDir)) {
    mkdirSync(archiveDir, { recursive: true });
    log.info({ archiveDir }, 'Created Threads/Archive directory');
  }

  const threads = getAllThreadsForExport();
  let exported = 0;

  for (const thread of threads) {
    try {
      const notes = getLinkedNotesForExport(thread.id);
      const markdown = generateThreadMarkdown(thread, notes);
      const slug = createSlug(thread.name);
      const fileName = `${slug}.md`;

      // Route archived/merged threads to Archive subfolder
      const isArchived = thread.status === 'archived' || thread.status === 'merged';
      const targetDir = isArchived ? archiveDir : threadsDir;
      const otherDir = isArchived ? threadsDir : archiveDir;
      const filePath = join(targetDir, fileName);

      writeFileSync(filePath, markdown, 'utf-8');
      exported++;

      // Clean up: remove from old location if thread moved between active and archived
      const oldPath = join(otherDir, fileName);
      if (existsSync(oldPath)) {
        unlinkSync(oldPath);
        log.info({ threadId: thread.id, oldPath, newPath: filePath }, 'Moved thread file to new location');
      }

      log.debug({ threadId: thread.id, filePath }, 'Exported thread to Obsidian');
    } catch (err) {
      const error = err as Error;
      log.error({ err: error, threadId: thread.id }, 'Failed to export thread');
    }
  }

  log.info({ exported, total: threads.length }, 'Thread export to Obsidian complete');
  return exported;
}

/**
 * Main workflow: reconsolidate thread summaries and calculate momentum
 */
export async function reconsolidateThreads(): Promise<WorkflowResult> {
  log.info('Starting thread reconsolidation');

  const result: WorkflowResult = {
    processed: 0,
    errors: 0,
    details: [],
  };

  // Phase 1: Find threads needing update
  const threadsNeedingUpdate = getThreadsNeedingUpdate();
  log.info({ count: threadsNeedingUpdate.length }, 'Threads needing resynthesis');

  // Phase 2: Resynthesize each thread
  for (const thread of threadsNeedingUpdate) {
    try {
      // Get notes for this thread (newest first, limited)
      const notes = getThreadNotes(thread.id, MAX_NOTES_PER_SYNTHESIS);

      if (notes.length === 0) {
        log.warn({ threadId: thread.id }, 'Thread has no notes');
        continue;
      }

      // Build prompt and call LLM
      const prompt = buildResynthesisPrompt(thread, notes);
      log.info(
        { threadId: thread.id, noteCount: notes.length, promptLength: prompt.length },
        'Calling LLM for resynthesis'
      );

      const llmResponse = await generate(prompt);

      // Parse response
      const synthesis = parseSynthesis(llmResponse, thread.name);
      if (!synthesis) {
        log.error({ threadId: thread.id }, 'Failed to synthesize thread update');
        result.errors++;
        result.details.push({ id: thread.id, success: false, error: 'LLM synthesis failed' });
        continue;
      }

      // Update thread
      updateThread(thread, synthesis);

      result.processed++;
      result.details.push({ id: thread.id, success: true });
    } catch (err) {
      const error = err as Error;
      log.error({ err: error, threadId: thread.id }, 'Error processing thread');
      result.errors++;
      result.details.push({ id: thread.id, success: false, error: error.message });
    }
  }

  // Phase 3: Calculate momentum for ALL active threads
  const momentumUpdated = calculateMomentum();

  // Phase 4: Export threads to Obsidian
  const threadsExported = exportThreadsToObsidian();

  log.info(
    {
      threadsResynthesized: result.processed,
      momentumUpdated,
      threadsExported,
      errors: result.errors,
    },
    'Thread reconsolidation complete'
  );

  return result;
}

// CLI entry point
if (require.main === module) {
  reconsolidateThreads()
    .then((result) => {
      console.log('Reconsolidate-threads complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Reconsolidate-threads failed:', err);
      process.exit(1);
    });
}
