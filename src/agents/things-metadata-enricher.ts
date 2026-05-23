import { BaseAgent, ProposedAction } from './base-agent';
import { getTasksFromProject, ThingsTask } from '../lib/things';
import { searchNotesKeyword } from '../lib/db';
import { generate } from '../lib/ollama';
import { logger } from '../lib/logger';

const log = logger.child({ module: 'things-metadata-enricher' });

export interface EnrichmentSuggestion {
  tags: string[];
  notes: string;
}

export function buildEnrichmentPrompt(taskName: string, relatedNotes: string): string {
  return `You are a personal knowledge management assistant.

Task: "${taskName}"

Related notes from the user's archive:
${relatedNotes || '(no related notes found)'}

Based on the task name and any related notes, suggest:
1. Tags (1-3 short, lowercase tags that categorize this task)
2. A one-sentence context note (what this task is about, why it matters)

Respond with ONLY valid JSON in this exact format:
{"tags": ["tag1", "tag2"], "notes": "One sentence context note here."}

Do not include any other text.`;
}

export function parseOllamaResponse(response: string): EnrichmentSuggestion | null {
  try {
    const jsonMatch = response.match(/\{[\s\S]*\}/);
    if (!jsonMatch) return null;
    const parsed = JSON.parse(jsonMatch[0]) as unknown;
    if (
      typeof parsed === 'object' && parsed !== null &&
      'tags' in parsed && Array.isArray((parsed as Record<string, unknown>).tags) &&
      'notes' in parsed && typeof (parsed as Record<string, unknown>).notes === 'string'
    ) {
      return parsed as EnrichmentSuggestion;
    }
    return null;
  } catch {
    return null;
  }
}

interface CollectedData {
  tasks: ThingsTask[];
  projectName: string;
}

export class ThingsMetadataEnricher extends BaseAgent {
  name = 'things-metadata-enricher';
  allowedActionTypes = ['things.update_notes', 'things.add_tag'];

  constructor(private projectName: string) {
    super();
  }

  async collect(): Promise<CollectedData> {
    log.info({ projectName: this.projectName }, 'Collecting tasks from Things');
    const tasks = getTasksFromProject(this.projectName);
    const needsEnrichment = tasks.filter(
      (t) => !t.notes?.trim() || t.tags.length === 0
    );
    log.info({ total: tasks.length, needsEnrichment: needsEnrichment.length }, 'Tasks collected');
    return { tasks: needsEnrichment, projectName: this.projectName };
  }

  async reason(data: unknown): Promise<ProposedAction[]> {
    const { tasks } = data as CollectedData;
    const actions: ProposedAction[] = [];

    for (const task of tasks) {
      log.info({ taskName: task.name }, 'Reasoning about task');

      // Find related notes from Selene archive
      const relatedNotes = searchNotesKeyword(task.name, 5);
      const relatedText = relatedNotes
        .map((n) => `- ${n.title}: ${n.content.slice(0, 200)}`)
        .join('\n');

      const prompt = buildEnrichmentPrompt(task.name, relatedText);

      try {
        const response = await generate(prompt, { temperature: 0.3 });
        const suggestion = parseOllamaResponse(response);

        if (!suggestion) {
          log.warn({ taskName: task.name }, 'Could not parse Ollama response, skipping');
          continue;
        }

        if (!task.notes?.trim() && suggestion.notes) {
          actions.push({
            action_type: 'things.update_notes',
            target_id: task.id,
            target_type: 'things_task',
            payload: { notes: suggestion.notes },
            rationale: `Task has no notes. Suggested: "${suggestion.notes}"`,
            confidence: 0.75,
          });
        }

        for (const tag of suggestion.tags) {
          if (!task.tags.includes(tag)) {
            actions.push({
              action_type: 'things.add_tag',
              target_id: task.id,
              target_type: 'things_task',
              payload: { tag },
              rationale: `Task has no "${tag}" tag. Suggested based on: "${task.name}"`,
              confidence: 0.7,
            });
          }
        }
      } catch (err) {
        log.error({ err, taskName: task.name }, 'Ollama reasoning failed for task');
      }
    }

    return actions;
  }

  buildReport(jobId: string, actions: ProposedAction[], data: unknown): { title: string; body: string } {
    const { tasks, projectName } = data as CollectedData;
    const noteActions = actions.filter((a) => a.action_type === 'things.update_notes');
    const tagActions = actions.filter((a) => a.action_type === 'things.add_tag');

    const actionLines = actions.map((a) => {
      const payload = a.payload as Record<string, string>;
      if (a.action_type === 'things.update_notes') {
        return `- **Add notes** to task \`${a.target_id}\`: "${payload.notes}" (${(a.confidence * 100).toFixed(0)}% confidence)\n  > ${a.rationale}`;
      }
      return `- **Add tag** \`${payload.tag}\` to task \`${a.target_id}\` (${(a.confidence * 100).toFixed(0)}% confidence)\n  > ${a.rationale}`;
    });

    return {
      title: `Things Metadata Enricher — ${projectName} — ${actions.length} proposed actions`,
      body: `## Things Metadata Enricher Report

**Project:** ${projectName}
**Job:** ${jobId}
**Analyzed:** ${tasks.length} tasks needing enrichment
**Proposed:** ${noteActions.length} notes updates, ${tagActions.length} tag additions

### Proposed Actions

${actionLines.join('\n\n')}

---
*Review and approve in the Selene dashboard at http://localhost:5678/dashboard*`,
    };
  }
}

// CLI entry point
if (require.main === module) {
  const projectName = process.argv[2];
  if (!projectName) {
    console.error('Usage: npx ts-node src/agents/things-metadata-enricher.ts "Project Name"');
    process.exit(1);
  }

  const agent = new ThingsMetadataEnricher(projectName);
  agent.run()
    .then(({ jobId, actionCount }) => {
      console.log(`Agent run complete. Job: ${jobId}, Actions: ${actionCount}`);
      process.exit(0);
    })
    .catch((err) => {
      console.error('Agent run failed:', err);
      process.exit(1);
    });
}
