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

/** Namespaced slug for a sub-cluster, e.g. "health-body/running". */
export function subSlug(category: string, sub: string): string {
  return `${slugForCategory(category)}/${slugForCategory(sub)}`;
}

/**
 * True if a topic_clusters slug is legitimate: either one of the 8 category slugs,
 * or a sub-slug `<categorySlug>/<sub>` whose prefix is a real category slug.
 * Used by synthesize-topics orphan cleanup. NOTE: slugForCategory maps any
 * non-alphanumeric run to '-', so a sub-name can never introduce a stray '/'.
 */
export function isValidClusterSlug(slug: string, categorySlugs: string[]): boolean {
  const set = new Set(categorySlugs);
  if (set.has(slug)) return true;
  const slash = slug.indexOf('/');
  if (slash === -1) return false;
  return set.has(slug.slice(0, slash));
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

export interface SubCategorizableNote extends CategorizableNote {
  subCategories: Record<string, string>;
}

/**
 * For each note, for each VALID category it belongs to, place it under the sub-cat
 * assigned for that category (if any). Returns category → (subName → noteIds[]).
 * A note's sub-cat for a category it isn't actually in is ignored (guards bad LLM maps).
 */
export function groupNotesBySubCategory(
  notes: SubCategorizableNote[],
): Map<string, Map<string, number[]>> {
  const groups = new Map<string, Map<string, Set<number>>>();
  for (const note of notes) {
    const cats = validCategoriesFor(note);
    for (const cat of cats) {
      const sub = note.subCategories[cat];
      if (!sub) continue;
      if (!groups.has(cat)) groups.set(cat, new Map());
      const subMap = groups.get(cat)!;
      if (!subMap.has(sub)) subMap.set(sub, new Set());
      subMap.get(sub)!.add(note.noteId);
    }
  }
  const out = new Map<string, Map<string, number[]>>();
  for (const [cat, subMap] of groups) {
    const m = new Map<string, number[]>();
    for (const [sub, set] of subMap) m.set(sub, [...set]);
    out.set(cat, m);
  }
  return out;
}

/** Build the closed-set sub-category prompt for one note over its assigned categories. */
export function buildSubCategoryPrompt(
  title: string,
  content: string,
  allowedByCategory: Record<string, string[]>,
): string {
  const lines = Object.entries(allowedByCategory)
    .map(([cat, subs]) => `- ${cat}: ${[...subs, 'none'].join(' | ')}`)
    .join('\n');
  return `For each category below, pick the ONE best-fitting sub-category from its list, or "none".
Choose ONLY from the given options — do not invent sub-categories.

Title: ${title}
Note: ${content}

Categories and their allowed sub-categories:
${lines}

Reply with JSON mapping each category to one chosen value, e.g. {"Health & Body":"Running"}:`;
}

/**
 * Parse the sub-category LLM response. Closed-set: a value is kept only if it
 * exactly matches an entry in that category's allowed list. "none"/invalid/unknown
 * categories are dropped. Returns a category→sub map (omits unassigned categories).
 */
export function parseSubCategories(
  response: string,
  allowedByCategory: Record<string, string[]>,
): Record<string, string> {
  const match = response.match(/\{[\s\S]*\}/);
  if (!match) return {};
  let parsed: unknown;
  try {
    parsed = JSON.parse(match[0]);
  } catch {
    return {};
  }
  if (parsed === null || typeof parsed !== 'object') return {};
  const out: Record<string, string> = {};
  for (const [cat, allowed] of Object.entries(allowedByCategory)) {
    const v = (parsed as Record<string, unknown>)[cat];
    if (typeof v === 'string' && allowed.includes(v)) out[cat] = v;
  }
  return out;
}
