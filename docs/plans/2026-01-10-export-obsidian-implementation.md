# Export Obsidian TypeScript Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a TypeScript workflow that exports processed notes to Obsidian with full ADHD-optimized formatting, scheduled hourly via launchd with HTTP trigger support.

**Architecture:** Single workflow file (`export-obsidian.ts`) handles all logic - query DB, generate markdown, write to 4 locations, update export status. Server endpoint calls the same function for manual triggers.

**Tech Stack:** TypeScript, better-sqlite3, Fastify, launchd

**Design Doc:** `docs/plans/2026-01-10-export-obsidian-typescript-design.md`

---

## Task 1: Create ExportableNote Interface

**Files:**
- Modify: `src/types/index.ts`

**Step 1: Add the interface**

Add to `src/types/index.ts`:

```typescript
// Obsidian export types
export interface ExportableNote {
  id: number;
  title: string;
  content: string;
  created_at: string;
  tags: string | null;
  word_count: number;
  concepts: string | null;
  primary_theme: string;
  secondary_themes: string | null;
  overall_sentiment: string;
  sentiment_score: number | null;
  emotional_tone: string;
  energy_level: string;
  sentiment_data: string | null;
}

export interface ExportResult {
  success: boolean;
  exported_count: number;
  errors: number;
  message: string;
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/types/index.ts
git commit -m "feat(export): add ExportableNote and ExportResult types"
```

---

## Task 2: Create Markdown Generator Helpers

**Files:**
- Create: `src/workflows/export-obsidian.ts`

**Step 1: Create file with imports and helper functions**

```typescript
import { writeFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import { createWorkflowLogger, db, config } from '../lib';
import type { ExportableNote, ExportResult } from '../types';

const log = createWorkflowLogger('export-obsidian');

// Emoji mappings
const ENERGY_EMOJI: Record<string, string> = {
  high: '⚡',
  medium: '🔋',
  low: '🪫',
};

const EMOTION_EMOJI: Record<string, string> = {
  excited: '🚀',
  calm: '😌',
  anxious: '😰',
  frustrated: '😤',
  content: '😊',
  overwhelmed: '🤯',
  motivated: '💪',
  focused: '🎯',
  reflective: '🤔',
  curious: '🧐',
};

const SENTIMENT_EMOJI: Record<string, string> = {
  positive: '✅',
  negative: '⚠️',
  neutral: '⚪',
  mixed: '🔀',
};

// Helper: Safely parse JSON fields
function parseJson<T>(field: string | null, defaultValue: T): T {
  if (!field) return defaultValue;
  try {
    return JSON.parse(field) as T;
  } catch {
    return defaultValue;
  }
}

// Helper: Create URL-friendly slug
function createSlug(title: string): string {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-')
    .slice(0, 50);
}

// Helper: Extract action items from content
function extractActionItems(content: string): string[] {
  const items: string[] = [];

  // Pattern 1: Checkbox format
  const checkboxes = content.match(/^[-*]\s*\[[ x]\]\s*(.+)$/gim) || [];
  checkboxes.forEach((match) => {
    const item = match.replace(/^[-*]\s*\[[ x]\]\s*/i, '').trim();
    if (item) items.push(item);
  });

  // Pattern 2: TODO/TASK/ACTION format
  const todos = content.match(/^[-*]\s*(?:TODO|TASK|ACTION)[:)]\s*(.+)$/gim) || [];
  todos.forEach((match) => {
    const item = match.replace(/^[-*]\s*(?:TODO|TASK|ACTION)[:)]\s*/i, '').trim();
    if (item) items.push(item);
  });

  // Pattern 3: "need to", "should", etc.
  const intentions = content.match(/\b(?:need to|should|must|have to|remember to)\s+([^.!?]+)/gi) || [];
  intentions.forEach((match) => {
    const item = match.replace(/^(?:need to|should|must|have to|remember to)\s+/i, '').trim();
    if (item) items.push(item);
  });

  // Deduplicate and filter
  const unique = [...new Set(items)].filter((item) => item.length > 5 && item.length < 200);
  return unique.slice(0, 10);
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/workflows/export-obsidian.ts
git commit -m "feat(export): add helper functions for markdown generation"
```

---

## Task 3: Create Markdown Generator Function

**Files:**
- Modify: `src/workflows/export-obsidian.ts`

**Step 1: Add generateAdhdMarkdown function**

Append to `src/workflows/export-obsidian.ts`:

```typescript
interface MarkdownData {
  markdown: string;
  dateStr: string;
  year: string;
  month: string;
  concepts: string[];
  theme: string;
  energy: string;
  title: string;
  slug: string;
}

function generateAdhdMarkdown(note: ExportableNote): MarkdownData {
  // Parse JSON fields
  const concepts = parseJson<string[]>(note.concepts, []);
  const secondaryThemes = parseJson<string[]>(note.secondary_themes, []);
  const tags = parseJson<string[]>(note.tags, []);
  const sentimentData = parseJson<{
    adhd_markers?: { overwhelm?: boolean; hyperfocus?: boolean; executive_dysfunction?: boolean };
    key_emotions?: string[];
    stress_indicators?: boolean;
    analysis_confidence?: number;
  }>(note.sentiment_data, {});

  // Extract ADHD markers
  const adhdMarkers = sentimentData.adhd_markers || {};
  const keyEmotions = sentimentData.key_emotions || [];
  const stressIndicators = sentimentData.stress_indicators || false;
  const analysisConfidence = sentimentData.analysis_confidence || 0.5;

  // Parse date
  const createdAt = new Date(note.created_at);
  const dateStr = createdAt.toISOString().split('T')[0];
  const timeStr = createdAt.toTimeString().slice(0, 5);
  const year = createdAt.getFullYear().toString();
  const month = (createdAt.getMonth() + 1).toString().padStart(2, '0');
  const dayOfWeek = createdAt.toLocaleDateString('en-US', { weekday: 'long' });

  // Get emojis
  const energyEmoji = ENERGY_EMOJI[note.energy_level] || '🔋';
  const emotionEmoji = EMOTION_EMOJI[note.emotional_tone] || '💭';
  const sentimentEmoji = SENTIMENT_EMOJI[note.overall_sentiment] || '⚪';

  // ADHD marker badges
  const adhdBadges: string[] = [];
  if (adhdMarkers.overwhelm) adhdBadges.push('🧠 OVERWHELM');
  if (adhdMarkers.hyperfocus) adhdBadges.push('🎯 HYPERFOCUS');
  if (adhdMarkers.executive_dysfunction) adhdBadges.push('⚠️ EXEC-DYS');
  if (stressIndicators) adhdBadges.push('😰 STRESS');
  const adhdBadgeStr = adhdBadges.length > 0 ? adhdBadges.join(' | ') : '✨ BASELINE';

  // Extract action items
  const actionItems = extractActionItems(note.content);

  // Generate TL;DR
  const sentences = note.content.split(/[.!?]\s+/);
  const firstSentences = sentences.slice(0, 2).join('. ');
  const tldr = firstSentences.length > 200 ? firstSentences.slice(0, 200) + '...' : firstSentences;

  // Reading time
  const readingTime = Math.max(1, Math.round(note.word_count / 200));

  // Build all tags
  const allTags = [
    note.primary_theme,
    ...secondaryThemes,
    ...tags,
    `energy-${note.energy_level}`,
    `mood-${note.emotional_tone}`,
    `sentiment-${note.overall_sentiment}`,
  ];
  if (adhdMarkers.overwhelm) allTags.push('adhd/overwhelm');
  if (adhdMarkers.hyperfocus) allTags.push('adhd/hyperfocus');
  if (stressIndicators) allTags.push('state/stressed');
  const uniqueTags = [...new Set(allTags.filter(Boolean))];

  // Escape title for YAML
  const titleEscaped = note.title.replace(/"/g, '\\"');
  const sentimentScore = note.sentiment_score || 0.5;

  // Build frontmatter
  const conceptsYaml = concepts.map((c) => `  - ${c}`).join('\n');
  const tagsYaml = uniqueTags.map((t) => `  - ${t}`).join('\n');

  const frontmatter = `---
title: "${titleEscaped}"
date: ${dateStr}
time: "${timeStr}"
day: ${dayOfWeek}
theme: ${note.primary_theme || 'uncategorized'}
energy: ${note.energy_level}
mood: ${note.emotional_tone || 'neutral'}
sentiment: ${note.overall_sentiment}
sentiment_score: ${sentimentScore}
concepts:
${conceptsYaml || '  - uncategorized'}
tags:
${tagsYaml}
adhd_markers:
  overwhelm: ${adhdMarkers.overwhelm || false}
  hyperfocus: ${adhdMarkers.hyperfocus || false}
  executive_dysfunction: ${adhdMarkers.executive_dysfunction || false}
stress: ${stressIndicators}
action_items: ${actionItems.length}
reading_time: ${readingTime}
word_count: ${note.word_count}
source: Selene
automated: true
---`;

  // Context concepts
  const contextConcepts = concepts.slice(0, 2).join(', ') || 'general notes';

  // Build status header
  const statusHeader = `# ${emotionEmoji} ${note.title}

## 🎯 Status at a Glance

| Indicator | Status | Details |
|-----------|--------|----------|
| Energy | ${energyEmoji} ${note.energy_level.toUpperCase()} | Brain capacity indicator |
| Mood | ${emotionEmoji} ${note.emotional_tone || 'neutral'} | Emotional state |
| Sentiment | ${sentimentEmoji} ${note.overall_sentiment} | Overall tone (${Math.round(sentimentScore * 100)}%) |
| ADHD | ${adhdBadgeStr} | Markers detected |
| Actions | 🎯 ${actionItems.length} items | Tasks extracted |

---`;

  // Build metadata section
  const conceptLinks = concepts.map((c) => `[[Concepts/${c}]]`).join(' • ') || 'none';
  const themeLinks = [note.primary_theme, ...secondaryThemes]
    .filter(Boolean)
    .map((t) => `[[Themes/${t}]]`)
    .join(' • ');

  const contextBox = `> **⚡ Quick Context**
> ${tldr}
>
> **Why this matters:** Related to ${contextConcepts}
> **Reading time:** ${readingTime} min
> **Brain state:** ${note.energy_level} energy, ${note.emotional_tone || 'neutral'}`;

  const metadataSection = `
**🏷️ Theme**: ${themeLinks || 'uncategorized'}
**💡 Concepts**: ${conceptLinks}
**📅 Created**: ${dateStr} (${dayOfWeek}) at ${timeStr}
**⏱️ Reading Time**: ${readingTime} min

---

${contextBox}

---`;

  // Build action items section
  let actionItemsSection = '';
  if (actionItems.length > 0) {
    const actionItemsList = actionItems.map((item) => `- [ ] ${item}`).join('\n');
    actionItemsSection = `
## ✅ Action Items Detected

${actionItemsList}

> **Tip:** Copy these to your daily todo list or use Obsidian Tasks plugin

---`;
  }

  // Content section
  const contentSection = `
## 📝 Full Content

${note.content}

---`;

  // Energy interpretation
  const energyInterpretation: Record<string, string> = {
    high: '⚡ Great time for complex tasks',
    low: '🪫 Consider rest or easy tasks',
    medium: '🔋 Moderate capacity available',
  };

  // Emotional insights
  const emotionalInsights: string[] = [];
  if (adhdMarkers.overwhelm) emotionalInsights.push('⚠️ Signs of overwhelm detected - consider breaking tasks down');
  if (adhdMarkers.hyperfocus) emotionalInsights.push('🎯 Hyperfocus detected - valuable insights likely!');
  if (stressIndicators) emotionalInsights.push('😰 Stress indicators present - be gentle with yourself');
  const emotionalInsightsStr = emotionalInsights.length > 0 ? '\n  - ' + emotionalInsights.join('\n  - ') : '';

  // Key emotions section
  let keyEmotionsSection = '';
  if (keyEmotions.length > 0) {
    keyEmotionsSection = `
### Key Emotions
${keyEmotions.map((e) => `- ${e}`).join('\n')}`;
  }

  const insightsSection = `
## 🧠 ADHD Insights

### Brain State Analysis

- **Energy Level**: ${note.energy_level} ${energyEmoji}
  - ${energyInterpretation[note.energy_level] || ''}

- **Emotional Tone**: ${note.emotional_tone || 'neutral'} ${emotionEmoji}${emotionalInsightsStr}

- **Sentiment**: ${note.overall_sentiment} (${Math.round(sentimentScore * 100)}%)
${keyEmotionsSection}

### Context Clues

- **When was this?** ${dayOfWeek}, ${dateStr} at ${timeStr}
- **What was I thinking about?** ${concepts.slice(0, 3).join(', ') || 'various topics'}
- **Theme**: ${note.primary_theme || 'uncategorized'}
- **How did I feel?** ${note.emotional_tone || 'neutral'}, ${note.overall_sentiment}

> **Memory Trigger**: Look for related notes tagged with these concepts to restore full context

---`;

  // Metadata footer
  const metadataFooter = `
## 📊 Processing Metadata

- **Processed**: ${new Date().toISOString().split('T')[0]}
- **Source**: Selene Knowledge Management System
- **Concept Count**: ${concepts.length}
- **Word Count**: ${note.word_count}
- **Sentiment Confidence**: ${Math.round(analysisConfidence * 100)}%

## 🔗 Related Notes

*Obsidian will automatically show backlinks here based on shared concepts and tags*

---

*🤖 This note was automatically processed and optimized for ADHD by Selene*
`;

  // Combine all sections
  const markdown = `${frontmatter}

${statusHeader}

${metadataSection}
${actionItemsSection}
${contentSection}
${insightsSection}
${metadataFooter}`;

  return {
    markdown,
    dateStr,
    year,
    month,
    concepts,
    theme: note.primary_theme || 'uncategorized',
    energy: note.energy_level,
    title: note.title,
    slug: createSlug(note.title),
  };
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/workflows/export-obsidian.ts
git commit -m "feat(export): add ADHD markdown generator function"
```

---

## Task 4: Create File Writer Function

**Files:**
- Modify: `src/workflows/export-obsidian.ts`

**Step 1: Add writeNoteToVault function**

Append to `src/workflows/export-obsidian.ts`:

```typescript
function writeNoteToVault(note: ExportableNote, markdownData: MarkdownData, vaultPath: string): string {
  const filename = `${markdownData.dateStr}-${markdownData.slug}.md`;

  // Define all 4 paths
  const paths = {
    timeline: join(vaultPath, 'Selene', 'Timeline', markdownData.year, markdownData.month, filename),
    concept: join(
      vaultPath,
      'Selene',
      'By-Concept',
      markdownData.concepts[0] || 'uncategorized',
      filename
    ),
    theme: join(vaultPath, 'Selene', 'By-Theme', markdownData.theme, filename),
    energy: join(vaultPath, 'Selene', 'By-Energy', markdownData.energy, filename),
  };

  // Create directories and write files
  for (const [pathType, filePath] of Object.entries(paths)) {
    const dir = filePath.substring(0, filePath.lastIndexOf('/'));
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
    writeFileSync(filePath, markdownData.markdown, 'utf-8');
    log.debug({ pathType, filePath }, 'Wrote note to vault');
  }

  // Create concept hub pages
  const conceptsDir = join(vaultPath, 'Selene', 'Concepts');
  if (!existsSync(conceptsDir)) {
    mkdirSync(conceptsDir, { recursive: true });
  }

  for (const concept of markdownData.concepts) {
    const conceptFile = join(conceptsDir, `${concept}.md`);
    if (!existsSync(conceptFile)) {
      const conceptContent = `# ${concept}

**Type**: Concept Index
**Created**: ${new Date().toISOString().split('T')[0]}
**Auto-generated**: Yes

## 🎯 What is this?

This is a hub page for all notes related to **${concept}**. Obsidian will automatically show backlinks below.

## 📚 Related Notes

*Backlinks will appear here automatically*

## 🧠 ADHD Tips

- Use this page to see all notes about ${concept} in one place
- Great for refreshing your memory before diving into a specific note
- Check the backlinks section to find related context

---

*Auto-generated by Selene - edit freely!*
`;
      writeFileSync(conceptFile, conceptContent, 'utf-8');
      log.info({ concept, conceptFile }, 'Created concept hub page');
    }
  }

  return filename;
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/workflows/export-obsidian.ts
git commit -m "feat(export): add vault file writer with 4-location output"
```

---

## Task 5: Create Main Export Function

**Files:**
- Modify: `src/workflows/export-obsidian.ts`

**Step 1: Add database query and main export function**

Append to `src/workflows/export-obsidian.ts`:

```typescript
// Query for notes ready to export
function getNotesForExport(noteId?: number, limit = 50): ExportableNote[] {
  if (noteId) {
    // Export specific note
    return db
      .prepare(
        `SELECT
          rn.id, rn.title, rn.content, rn.created_at, rn.tags, rn.word_count,
          pn.concepts, pn.primary_theme, pn.secondary_themes,
          pn.overall_sentiment, pn.sentiment_score, pn.emotional_tone,
          pn.energy_level, pn.sentiment_data
        FROM raw_notes rn
        JOIN processed_notes pn ON rn.id = pn.raw_note_id
        WHERE rn.id = ?
          AND rn.status = 'processed'`
      )
      .all(noteId) as ExportableNote[];
  }

  // Export all pending notes
  return db
    .prepare(
      `SELECT
        rn.id, rn.title, rn.content, rn.created_at, rn.tags, rn.word_count,
        pn.concepts, pn.primary_theme, pn.secondary_themes,
        pn.overall_sentiment, pn.sentiment_score, pn.emotional_tone,
        pn.energy_level, pn.sentiment_data
      FROM raw_notes rn
      JOIN processed_notes pn ON rn.id = pn.raw_note_id
      WHERE rn.exported_to_obsidian = 0
        AND rn.status = 'processed'
      ORDER BY rn.created_at DESC
      LIMIT ?`
    )
    .all(limit) as ExportableNote[];
}

// Mark note as exported
function markAsExported(noteId: number): void {
  db.prepare(
    `UPDATE raw_notes
     SET exported_to_obsidian = 1, exported_at = ?
     WHERE id = ?`
  ).run(new Date().toISOString(), noteId);
}

// Main export function
export async function exportObsidian(noteId?: number): Promise<ExportResult> {
  log.info({ noteId }, 'Starting Obsidian export');

  const vaultPath = process.env.OBSIDIAN_VAULT_PATH || join(config.projectRoot, 'vault');
  log.info({ vaultPath }, 'Using vault path');

  const notes = getNotesForExport(noteId);
  log.info({ noteCount: notes.length }, 'Found notes for export');

  if (notes.length === 0) {
    const message = noteId
      ? `Note ${noteId} not found or not ready for export`
      : 'No notes ready for export';
    return { success: true, exported_count: 0, errors: 0, message };
  }

  let exportedCount = 0;
  let errorCount = 0;

  for (const note of notes) {
    try {
      log.info({ noteId: note.id, title: note.title }, 'Exporting note');

      // Generate markdown
      const markdownData = generateAdhdMarkdown(note);

      // Write to vault
      const filename = writeNoteToVault(note, markdownData, vaultPath);

      // Mark as exported
      markAsExported(note.id);

      log.info({ noteId: note.id, filename }, 'Note exported successfully');
      exportedCount++;
    } catch (err) {
      const error = err as Error;
      log.error({ noteId: note.id, err: error }, 'Failed to export note');
      errorCount++;
    }
  }

  const message = noteId
    ? `Exported note ${noteId}`
    : `Exported ${exportedCount} notes to Obsidian`;

  log.info({ exportedCount, errorCount }, 'Export complete');

  return {
    success: errorCount === 0,
    exported_count: exportedCount,
    errors: errorCount,
    message,
  };
}

// CLI entry point
if (require.main === module) {
  const noteId = process.argv[2] ? parseInt(process.argv[2], 10) : undefined;

  exportObsidian(noteId)
    .then((result) => {
      console.log(JSON.stringify(result, null, 2));
      process.exit(result.errors > 0 ? 1 : 0);
    })
    .catch((err) => {
      console.error('Export failed:', err);
      process.exit(1);
    });
}
```

**Step 2: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 3: Commit**

```bash
git add src/workflows/export-obsidian.ts
git commit -m "feat(export): add main export function with CLI entry point"
```

---

## Task 6: Add HTTP Endpoint to Server

**Files:**
- Modify: `src/server.ts`

**Step 1: Import the export function**

Add import at top of `src/server.ts`:

```typescript
import { exportObsidian } from './workflows/export-obsidian';
```

**Step 2: Add the endpoint**

Add before `// Start server` comment:

```typescript
// Manual export trigger endpoint
server.post<{ Body: { noteId?: number } }>('/webhook/api/export-obsidian', async (request, reply) => {
  const { noteId } = request.body || {};

  logger.info({ noteId }, 'Export-obsidian webhook received');

  try {
    const result = await exportObsidian(noteId);
    return result;
  } catch (err) {
    const error = err as Error;
    logger.error({ err: error }, 'Export-obsidian failed');
    reply.status(500);
    return { success: false, exported_count: 0, errors: 1, message: error.message };
  }
});
```

**Step 3: Verify TypeScript compiles**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 4: Commit**

```bash
git add src/server.ts
git commit -m "feat(export): add /webhook/api/export-obsidian endpoint"
```

---

## Task 7: Create launchd Plist

**Files:**
- Create: `launchd/com.selene.export-obsidian.plist`

**Step 1: Create the plist file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.export-obsidian</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/npx</string>
        <string>ts-node</string>
        <string>src/workflows/export-obsidian.ts</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/chaseeasterling/selene</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Minute</key>
        <integer>0</integer>
    </dict>

    <key>StandardOutPath</key>
    <string>/Users/chaseeasterling/selene/logs/export-obsidian.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/chaseeasterling/selene/logs/export-obsidian.error.log</string>
</dict>
</plist>
```

**Step 2: Commit**

```bash
git add launchd/com.selene.export-obsidian.plist
git commit -m "feat(export): add hourly launchd job for Obsidian export"
```

---

## Task 8: Manual Test

**Step 1: Run the workflow manually**

Run: `npx ts-node src/workflows/export-obsidian.ts`
Expected: JSON output with `success: true`

**Step 2: Check vault for exported files**

Run: `ls -la vault/Selene/Timeline/2026/01/ 2>/dev/null || echo "No files yet (expected if no processed notes)"`

**Step 3: Test HTTP endpoint**

Start server in one terminal: `npx ts-node src/server.ts`

In another terminal:
```bash
curl -X POST http://localhost:5678/webhook/api/export-obsidian \
  -H "Content-Type: application/json" \
  -d '{}'
```

Expected: JSON response with export result

---

## Task 9: Install launchd Agent

**Step 1: Copy plist to LaunchAgents**

Run: `cp launchd/com.selene.export-obsidian.plist ~/Library/LaunchAgents/`

**Step 2: Load the agent**

Run: `launchctl load ~/Library/LaunchAgents/com.selene.export-obsidian.plist`

**Step 3: Verify loaded**

Run: `launchctl list | grep selene.export`
Expected: Shows `com.selene.export-obsidian`

**Step 4: Test manual trigger**

Run: `launchctl start com.selene.export-obsidian`

Check logs: `tail -20 logs/export-obsidian.log`

---

## Task 10: Final Commit and Merge Prep

**Step 1: Run full TypeScript check**

Run: `npx tsc --noEmit`
Expected: No errors

**Step 2: Test server starts cleanly**

Run: `timeout 5 npx ts-node src/server.ts || true`
Expected: Server starts without errors

**Step 3: Create summary commit if any uncommitted changes**

```bash
git status
# If clean, skip
# If changes, commit with:
git add -A
git commit -m "chore(export): cleanup and final adjustments"
```

**Step 4: Verify branch is ready**

Run: `git log --oneline main..HEAD`
Expected: Shows all commits for this feature

---

## Summary

| Task | Description | Est. Time |
|------|-------------|-----------|
| 1 | Add types | 2 min |
| 2 | Helper functions | 3 min |
| 3 | Markdown generator | 5 min |
| 4 | File writer | 3 min |
| 5 | Main export function | 4 min |
| 6 | HTTP endpoint | 3 min |
| 7 | launchd plist | 2 min |
| 8 | Manual test | 3 min |
| 9 | Install launchd | 2 min |
| 10 | Final verification | 2 min |
