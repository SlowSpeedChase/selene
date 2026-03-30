import { writeFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import { createWorkflowLogger, db, generate, isAvailable, config } from '../lib';
import { notifyBriefingReady } from '../lib/apns';

const log = createWorkflowLogger('daily-summary');

const SUMMARY_PROMPT = `Generate a brief summary of recent notes for someone with ADHD.

Most recent notes ({count} notes):
{notes}

Key themes detected:
{themes}

Write a 2-3 paragraph summary that:
1. Highlights the main threads of thought
2. Notes any patterns or connections
3. Suggests what might need attention tomorrow

Keep it encouraging and actionable.`;

const DIGEST_PROMPT = `Condense this daily summary into 3-5 short bullet points for a text message.
Be brief and actionable. No headers or formatting. No bullet characters - just short lines.

{summary}`;

export async function dailySummary(): Promise<{ success: boolean; path?: string; digestPath?: string }> {
  log.info('Starting daily summary generation');

  const obsidianPath = process.env.OBSIDIAN_VAULT_PATH || join(config.projectRoot, 'vault');

  // Get the last 10 notes (most recent first, then reversed to chronological)
  const notes = db
    .prepare(
      `SELECT rn.title, rn.content, pn.primary_theme, pn.secondary_themes, pn.concepts, pn.essence
       FROM raw_notes rn
       LEFT JOIN processed_notes pn ON rn.id = pn.raw_note_id
       WHERE rn.test_run IS NULL
       ORDER BY rn.created_at DESC
       LIMIT 10`
    )
    .all() as Array<{
    title: string;
    content: string;
    primary_theme: string | null;
    secondary_themes: string | null;
    concepts: string | null;
    essence: string | null;
  }>;

  // Reverse to chronological order for the prompt
  notes.reverse();

  log.info({ noteCount: notes.length }, 'Found recent notes for summary');

  if (notes.length === 0) {
    log.info('No notes found, skipping summary');
    return { success: true };
  }

  // Format notes for prompt
  const notesText = notes
    .map((n) => {
      // Prefer essence, then concepts, then truncated content
      if (n.essence) {
        return `- ${n.title}: ${n.essence}`;
      }
      if (n.concepts) {
        try {
          const conceptList = JSON.parse(n.concepts);
          if (conceptList.length > 0) {
            return `- ${n.title}: ${conceptList.slice(0, 3).join(', ')}`;
          }
        } catch {
          // Fall through
        }
      }
      return `- ${n.title}: ${n.content.slice(0, 100)}...`;
    })
    .join('\n');

  // Collect all themes
  const allThemes = notes
    .flatMap((n) => {
      const themes: string[] = [];
      if (n.primary_theme) themes.push(n.primary_theme);
      if (n.secondary_themes) {
        try {
          const secondary = JSON.parse(n.secondary_themes);
          themes.push(...secondary);
        } catch (e) {
          // Ignore parse errors
        }
      }
      return themes;
    })
    .filter((t, i, arr) => arr.indexOf(t) === i);

  const themesText = allThemes.length > 0 ? allThemes.join(', ') : 'No themes detected yet';

  // Generate summary
  let summary: string;

  if (await isAvailable()) {
    const prompt = SUMMARY_PROMPT.replace('{count}', String(notes.length))
      .replace('{notes}', notesText)
      .replace('{themes}', themesText);

    summary = await generate(prompt);
  } else {
    log.warn('Ollama not available, using fallback summary');
    summary = `## Daily Summary\n\nCaptured ${notes.length} notes today.\n\nThemes: ${themesText}\n\n(Ollama was offline - no AI summary generated)`;
  }

  // Write to Obsidian vault
  const dailyDir = join(obsidianPath, 'Selene', 'Daily');
  if (!existsSync(dailyDir)) {
    mkdirSync(dailyDir, { recursive: true });
  }

  const dateStr = new Date().toISOString().split('T')[0];
  const outputPath = join(dailyDir, `${dateStr}-summary.md`);

  const markdown = `---
date: ${dateStr}
notes: ${notes.length}
themes: [${allThemes.map((t) => `"${t}"`).join(', ')}]
---

# Daily Summary - ${dateStr}

${summary}

---

## Notes Captured

${notes.map((n) => `- [[${n.title}]]`).join('\n')}
`;

  writeFileSync(outputPath, markdown);
  log.info({ outputPath }, 'Daily summary written');

  // Generate condensed digest for Apple Notes
  let digest: string;
  if (await isAvailable()) {
    digest = await generate(DIGEST_PROMPT.replace('{summary}', summary));
  } else {
    digest = `${notes.length} notes captured. Themes: ${themesText}`;
  }

  // Write digest file
  const digestDir = config.digestsPath;
  if (!existsSync(digestDir)) {
    mkdirSync(digestDir, { recursive: true });
  }
  const digestPath = join(digestDir, `${dateStr}-digest.txt`);
  writeFileSync(digestPath, digest);
  log.info({ digestPath }, 'Condensed digest written');

  // Notify iOS devices
  await notifyBriefingReady();

  return { success: true, path: outputPath, digestPath };
}

// CLI entry point
if (require.main === module) {
  dailySummary()
    .then((result) => {
      console.log('Daily summary complete:', result);
      process.exit(0);
    })
    .catch((err) => {
      console.error('Daily summary failed:', err);
      process.exit(1);
    });
}
