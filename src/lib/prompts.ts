export const CATEGORIES = [
  'Personal Growth',
  'Relationships & Social',
  'Health & Body',
  'Projects & Tech',
  'Career & Work',
  'Creativity & Expression',
  'Politics & Society',
  'Daily Systems',
] as const;

export type Category = typeof CATEGORIES[number];

export const EXTRACT_PROMPT = `Analyze this note and extract key information.

Note Title: {title}
Note Content: {content}

Categories (pick the BEST fit for "category", optionally 1-2 others for "cross_ref_categories"):
- Personal Growth
- Relationships & Social
- Health & Body
- Projects & Tech
- Career & Work
- Creativity & Expression
- Politics & Society
- Daily Systems

Respond in JSON format:
{
  "concepts": ["concept1", "concept2", "concept3"],
  "category": "one of the 8 categories above",
  "cross_ref_categories": [],
  "primary_theme": "short freeform descriptor 2-4 words",
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

export const MOC_PROMPT = `You are a librarian organizing a personal knowledge library.
Topic: "{category}"

Here are the notes in this category:
{notes_list}

Cross-referenced notes from other categories:
{cross_ref_notes}

Organize these notes into a Map of Content with:
1. A 2-3 sentence intro in second person ("You've been exploring...")
2. Group notes into named sub-sections (## headers) by theme
3. Under each sub-section, list notes as "- [[{filename}]] — one-line description"
4. A "## See Also" section listing cross-referenced notes as "- [[{filename}]] — why it's relevant here"
5. At the bottom, link to related category MOCs as "Related: [[{other_category}]]"

Rules:
- Use [[filename]] EXACTLY as provided — never invent link names
- Every note must appear in exactly one sub-section
- Sub-section names should be 1-3 words (e.g., "Dating", "Family", "Social Skills")
- If a sub-section would have only 1 note, merge it with the most related sub-section
- Skip the "See Also" section if there are no cross-references
- Do NOT include frontmatter or a top-level heading (we add those ourselves)`;
