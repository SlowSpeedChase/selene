export const EXTRACT_PROMPT = `Analyze this note and extract key information.

Note Title: {title}
Note Content: {content}

Respond in JSON format:
{
  "concepts": ["concept1", "concept2", "concept3"],
  "primary_theme": "main theme or category",
  "secondary_themes": ["related theme 1", "related theme 2"],
  "overall_sentiment": "positive|negative|neutral|mixed",
  "emotional_tone": "reflective|anxious|excited|frustrated|calm|curious|etc",
  "energy_level": "high|medium|low"
}

JSON response:`;

export const ESSENCE_PROMPT = `Distill this note into 1-2 sentences capturing what it means to the person who wrote it. Focus on the core insight, decision, or question — not a summary of the text.

Title: {title}
Content: {content}
{context}

Respond with ONLY the 1-2 sentence distillation, no quotes or explanation:`;

export function buildEssencePrompt(
  title: string,
  content: string,
  concepts: string | null,
  primaryTheme: string | null
): string {
  const contextParts: string[] = [];
  if (concepts) {
    try {
      const conceptList = JSON.parse(concepts);
      if (conceptList.length > 0) {
        contextParts.push(`Key concepts: ${conceptList.join(', ')}`);
      }
    } catch { /* ignore */ }
  }
  if (primaryTheme) {
    contextParts.push(`Theme: ${primaryTheme}`);
  }
  const contextStr = contextParts.length > 0
    ? contextParts.join('\n')
    : '';

  return ESSENCE_PROMPT
    .replace('{title}', title)
    .replace('{content}', content)
    .replace('{context}', contextStr);
}

export const TOPIC_INDEX_PROMPT = `You are writing a topic index page for a personal knowledge library. The topic is "{theme}".

Here are the notes in this topic:

{notes}

Write a topic index page with these sections:
1. A 2-3 sentence summary in second person ("You've been thinking about...") that captures the theme
2. A "## Recent" section listing notes from the last 2 weeks as "- [[{filename}]] — one-line description"
3. A "## Earlier" section listing older notes in the same format
4. A "## Connections" line suggesting 2-3 related topics that might link to this one

Rules:
- Do NOT include frontmatter or a top-level heading (we add those ourselves)
- Use the note titles and essences to write accurate descriptions
- If all notes are recent, skip the "Earlier" section
- If all notes are older, skip the "Recent" section
- Keep descriptions concise — one line each
- Use wiki-link format [[filename]] exactly as provided`;

export const DASHBOARD_PROMPT = `You are writing a dashboard page for a personal knowledge library. Here are the current stats and activity:

{stats}

Recent notes (last 7 days):
{recent_notes}

Topic activity:
{topic_activity}

Write a dashboard with these sections:
## What's New
A natural language summary of recent activity (2-3 sentences), followed by a linked list of recent notes as "- [[{filename}]] — description"

## Active Topics
A markdown table with columns: Topic, Recent Notes, Last Activity

## Emerging Patterns
What themes are recurring, growing, or new? 2-3 bullet points about patterns you notice.

## Quiet Topics
Topics without recent notes. A gentle reminder in 1-2 sentences about what hasn't been touched lately.

Rules:
- Do NOT include frontmatter or a top-level heading
- Use second person, conversational tone ("You've been focused on...")
- Use wiki-link format [[filename]] exactly as provided
- Keep it scannable — this is for someone with ADHD who needs a quick overview`;
