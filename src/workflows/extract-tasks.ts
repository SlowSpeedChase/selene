import { writeFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import Database from 'better-sqlite3';
import { createWorkflowLogger, db, generate, isAvailable, config } from '../lib';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('extract-tasks');

/**
 * Find a matching project for a note based on concept overlap.
 * Returns the Things project ID if a match is found, null otherwise.
 *
 * Matching rule: First active project where primary_concept appears in note's concepts.
 * If multiple matches, returns the most recently active project.
 */
export function findMatchingProject(database: Database.Database, noteId: number): string | null {
  // Get concepts for this note
  const noteRow = database
    .prepare('SELECT concepts FROM processed_notes WHERE raw_note_id = ?')
    .get(noteId) as { concepts: string } | undefined;

  if (!noteRow || !noteRow.concepts) {
    return null;
  }

  let concepts: string[];
  try {
    concepts = JSON.parse(noteRow.concepts);
  } catch {
    return null;
  }

  if (!Array.isArray(concepts) || concepts.length === 0) {
    return null;
  }

  // Find matching project - primary_concept must be in note's concepts
  // Order by last_active_at DESC to get most recently active
  const placeholders = concepts.map(() => '?').join(', ');
  const project = database
    .prepare(
      `SELECT things_project_id FROM projects
       WHERE status = 'active'
       AND primary_concept IN (${placeholders})
       ORDER BY last_active_at DESC NULLS LAST
       LIMIT 1`
    )
    .get(...concepts) as { things_project_id: string } | undefined;

  return project?.things_project_id ?? null;
}

const CLASSIFY_PROMPT = `Classify this note into one of three categories:
- actionable: Contains specific tasks that can be done
- needs_planning: Has ideas that need breakdown before acting
- archive_only: Reference material, no action needed

Note: {content}

Respond with just one word: actionable, needs_planning, or archive_only`;

const EXTRACT_TASKS_PROMPT = `Extract actionable tasks from this note.

Note: {content}

For each task, provide:
- title: Short task title
- notes: Any relevant context
- task_type: One of: action, decision, research, communication, learning, planning
- estimated_minutes: Estimate (5, 15, 30, 60, 120, or 240)
- overwhelm_factor: 1-10 scale (10 = most overwhelming/complex)

Respond in JSON array format:
[{"title": "Task", "notes": "Context", "task_type": "action", "estimated_minutes": 30, "overwhelm_factor": 3}]

JSON response:`;

function getCaptureTypeHint(captureType: string | null): string {
  switch (captureType) {
    case 'whiteboard':
      return '\n\nContext: This was captured from a whiteboard photo. Whiteboards typically contain planning, brainstorming, and high-level ideas rather than individual tasks. Bias toward needs_planning unless you see explicit checkbox-style tasks.\n\n';
    case 'daily_sheet_annotation':
      return '\n\nContext: This contains handwritten annotations from a daily planning sheet. Look for: completed tasks (checked items), new ideas (scratch zone notes), and thread-related observations.\n\n';
    default:
      return '';
  }
}

export async function extractTasks(limit = 10): Promise<WorkflowResult> {
  log.info({ limit }, 'Starting task extraction run');

  if (!(await isAvailable())) {
    log.error('Ollama is not available');
    return { processed: 0, errors: 0, details: [] };
  }

  // Get processed notes that haven't had tasks extracted yet
  const notes = db
    .prepare(
      `SELECT rn.id, rn.title, rn.content, rn.capture_type
       FROM raw_notes rn
       JOIN processed_notes pn ON rn.id = pn.raw_note_id
       WHERE rn.status = 'processed'
       AND (pn.things_integration_status IS NULL OR pn.things_integration_status = 'pending')
       LIMIT ?`
    )
    .all(limit) as Array<{ id: number; title: string; content: string; capture_type: string | null }>;

  log.info({ noteCount: notes.length }, 'Found notes needing classification');

  const result: WorkflowResult = { processed: 0, errors: 0, details: [] };

  // Ensure Things pending directory exists
  if (!existsSync(config.thingsPendingDir)) {
    mkdirSync(config.thingsPendingDir, { recursive: true });
  }

  for (const note of notes) {
    try {
      log.info({ noteId: note.id, title: note.title }, 'Classifying note');

      // Classify the note
      const captureHint = getCaptureTypeHint(note.capture_type);
      const classifyPrompt = CLASSIFY_PROMPT.replace('{content}', captureHint + note.content);
      const classification = (await generate(classifyPrompt)).trim().toLowerCase();

      const validClassifications = ['actionable', 'needs_planning', 'archive_only'];
      const finalClassification = validClassifications.includes(classification)
        ? classification
        : 'archive_only';

      log.info({ noteId: note.id, classification: finalClassification }, 'Note classified');

      // If actionable, extract tasks and write to Things bridge
      if (finalClassification === 'actionable') {
        const extractPrompt = EXTRACT_TASKS_PROMPT.replace('{content}', note.content);
        const tasksResponse = await generate(extractPrompt);

        let tasks = [];
        try {
          const jsonMatch = tasksResponse.match(/\[[\s\S]*\]/);
          if (jsonMatch) {
            tasks = JSON.parse(jsonMatch[0]);
          }
        } catch {
          log.warn({ noteId: note.id }, 'Failed to parse tasks JSON');
          tasks = [{ title: note.title, notes: note.content }];
        }

        // Check for matching project (auto-assignment)
        const projectId = findMatchingProject(db, note.id);
        if (projectId) {
          log.info({ noteId: note.id, projectId }, 'Found matching project for auto-assignment');
        }

        // Write tasks to Things bridge directory (or discussion thread if oversized)
        for (const task of tasks) {
          // Check for oversized task (7.2f.4)
          const isOversized =
            (task.overwhelm_factor && task.overwhelm_factor > 7) ||
            (task.estimated_minutes && task.estimated_minutes >= 240);

          if (isOversized) {
            // Route to discussion thread for planning breakdown
            db.prepare(
              `INSERT INTO discussion_threads_new
               (raw_note_id, thread_type, prompt, status, related_concepts)
               VALUES (?, 'planning', ?, 'pending', ?)`
            ).run(
              note.id,
              `This task needs breakdown: "${task.title}"\n\nOriginal context: ${task.notes || 'None'}\n\nEstimated: ${task.estimated_minutes || '?'} min, Overwhelm: ${task.overwhelm_factor || '?'}/10`,
              JSON.stringify([])
            );
            log.info(
              { noteId: note.id, title: task.title, overwhelm: task.overwhelm_factor, minutes: task.estimated_minutes },
              'Oversized task routed to discussion thread'
            );
            continue;
          }

          const taskFile = join(
            config.thingsPendingDir,
            `task-${note.id}-${Date.now()}.json`
          );

          // Build task data with optional fields
          const taskData: Record<string, unknown> = {
            title: task.title,
            notes: task.notes,
          };

          // Add project_id if we found a matching project
          if (projectId) {
            taskData.project_id = projectId;
          }

          // Add heading based on task_type (7.2f.3)
          const headingMap: Record<string, string> = {
            action: 'Actions',
            decision: 'Decisions',
            research: 'Research',
            communication: 'Communication',
            learning: 'Learning',
            planning: 'Planning',
          };
          if (task.task_type && headingMap[task.task_type]) {
            taskData.heading = headingMap[task.task_type];
          }

          writeFileSync(taskFile, JSON.stringify(taskData, null, 2));
          log.info(
            { noteId: note.id, taskFile, projectId, heading: taskData.heading },
            'Task written to Things bridge'
          );
        }

        // Mark as tasks_created
        db.prepare(
          'UPDATE processed_notes SET things_integration_status = ? WHERE raw_note_id = ?'
        ).run('tasks_created', note.id);
      } else {
        // Not actionable - mark as no_tasks
        db.prepare(
          'UPDATE processed_notes SET things_integration_status = ? WHERE raw_note_id = ?'
        ).run('no_tasks', note.id);
      }

      result.processed++;
      result.details.push({ id: note.id, success: true });
    } catch (err) {
      const error = err as Error;
      log.error({ noteId: note.id, err: error }, 'Failed to classify note');
      result.errors++;
      result.details.push({ id: note.id, success: false, error: error.message });
    }
  }

  log.info(result, 'Task extraction run complete');
  return result;
}

// CLI entry point
if (require.main === module) {
  extractTasks()
    .then((result) => {
      console.log('Extract-tasks complete:', result);
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Extract-tasks failed:', err);
      process.exit(1);
    });
}
