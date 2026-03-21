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
