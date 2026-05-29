import { CATEGORIES } from './prompts';

const VALID = new Set<string>(CATEGORIES);

export interface CategorizableNote {
  noteId: number;
  category: string | null;
  crossRefs: string[];
}

export function slugForCategory(category: string): string {
  return category.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

export function parseCrossRefs(json: string | null): string[] {
  if (!json) return [];
  try {
    const parsed: unknown = JSON.parse(json);
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((x): x is string => typeof x === 'string');
  } catch {
    return [];
  }
}

/**
 * Normalize a possibly-messy category value into the valid controlled categories it names.
 *
 * `process-llm.ts` stores `category` UNVALIDATED, so real data contains comma-joined lists
 * ("Personal Growth, Relationships & Social") and parentheticals ("Health & Body (for ...)").
 * No valid category contains a comma, so we split on commas, strip parentheticals, trim, and
 * keep only exact matches. A comma-joined value therefore yields genuine multi-membership.
 */
export function normalizeToValidCategories(value: string | null): string[] {
  if (!value) return [];
  return value
    .split(',')
    .map((part) => part.replace(/\(.*?\)/g, '').trim())
    .filter((part) => VALID.has(part));
}

function validCategoriesFor(note: CategorizableNote): Set<string> {
  const cats = new Set<string>();
  for (const c of normalizeToValidCategories(note.category)) cats.add(c);
  for (const cr of note.crossRefs) for (const c of normalizeToValidCategories(cr)) cats.add(c);
  return cats;
}

/** Map every controlled category -> the distinct note IDs that belong to it
 *  (via primary `category` OR any valid `cross_ref`). All 8 keys always present. */
export function groupNotesByCategory(notes: CategorizableNote[]): Map<string, number[]> {
  const groups = new Map<string, Set<number>>();
  for (const cat of CATEGORIES) groups.set(cat, new Set<number>());
  for (const note of notes) {
    for (const cat of validCategoriesFor(note)) groups.get(cat)!.add(note.noteId);
  }
  const out = new Map<string, number[]>();
  for (const [cat, set] of groups) out.set(cat, [...set]);
  return out;
}

/** Notes that matched zero valid categories — used for "no silent drop" logging. */
export function uncategorizedNoteIds(notes: CategorizableNote[]): number[] {
  return notes.filter((n) => validCategoriesFor(n).size === 0).map((n) => n.noteId);
}

/** Parse an Ollama EXTRACT_PROMPT response into validated category fields. */
export function extractCategoryFields(response: string): {
  category: string | null;
  crossRefs: string[];
} {
  const match = response.match(/\{[\s\S]*\}/);
  if (!match) return { category: null, crossRefs: [] };
  try {
    const parsed = JSON.parse(match[0]) as {
      category?: unknown;
      cross_ref_categories?: unknown;
    };
    const category =
      typeof parsed.category === 'string' && VALID.has(parsed.category)
        ? parsed.category
        : null;
    const crossRefs = Array.isArray(parsed.cross_ref_categories)
      ? parsed.cross_ref_categories.filter(
          (x): x is string => typeof x === 'string' && VALID.has(x)
        )
      : [];
    return { category, crossRefs };
  } catch {
    return { category: null, crossRefs: [] };
  }
}
