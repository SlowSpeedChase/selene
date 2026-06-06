import {
  slugForCategory,
  parseCrossRefs,
  groupNotesByCategory,
  uncategorizedNoteIds,
  extractCategoryFields,
  normalizeToValidCategories,
  subSlug,
  isValidClusterSlug,
  parseSubCategories,
  buildSubCategoryPrompt,
  groupNotesBySubCategory,
  buildAllowedFor,
  aggregateSubCoverage,
} from './category-clusters';
import type { CoverageRow } from './category-clusters';
import { CATEGORIES } from './prompts';

describe('normalizeToValidCategories', () => {
  it('returns [] for null/empty', () => {
    expect(normalizeToValidCategories(null)).toEqual([]);
    expect(normalizeToValidCategories('')).toEqual([]);
  });
  it('passes a single valid category through', () => {
    expect(normalizeToValidCategories('Health & Body')).toEqual(['Health & Body']);
  });
  it('splits a comma-joined value into multiple valid categories', () => {
    expect(normalizeToValidCategories('Personal Growth, Relationships & Social'))
      .toEqual(['Personal Growth', 'Relationships & Social']);
    expect(normalizeToValidCategories('Personal Growth, Relationships & Social, Daily Systems'))
      .toEqual(['Personal Growth', 'Relationships & Social', 'Daily Systems']);
  });
  it('strips a parenthetical annotation', () => {
    expect(normalizeToValidCategories('Health & Body (for Body Pillow and Dog Enrichment Plan)'))
      .toEqual(['Health & Body']);
  });
  it('drops parts that are not exact valid categories', () => {
    expect(normalizeToValidCategories('Personal Growth, Made Up')).toEqual(['Personal Growth']);
    expect(normalizeToValidCategories('Totally Invalid')).toEqual([]);
  });
});

describe('slugForCategory', () => {
  it('lowercases and replaces non-alphanumerics with single hyphens', () => {
    expect(slugForCategory('Relationships & Social')).toBe('relationships-social');
    expect(slugForCategory('Health & Body')).toBe('health-body');
    expect(slugForCategory('Personal Growth')).toBe('personal-growth');
  });
});

describe('parseCrossRefs', () => {
  it('parses a JSON string array', () => {
    expect(parseCrossRefs('["Health & Body","Career & Work"]'))
      .toEqual(['Health & Body', 'Career & Work']);
  });
  it('returns [] for null, empty, or malformed input', () => {
    expect(parseCrossRefs(null)).toEqual([]);
    expect(parseCrossRefs('')).toEqual([]);
    expect(parseCrossRefs('not json')).toEqual([]);
    expect(parseCrossRefs('{"a":1}')).toEqual([]);
  });
  it('drops non-string entries', () => {
    expect(parseCrossRefs('["Health & Body",3,null]')).toEqual(['Health & Body']);
  });
});

describe('groupNotesByCategory', () => {
  it('places a note under its primary category and every valid cross-ref (multi-membership)', () => {
    const groups = groupNotesByCategory([
      { noteId: 1, category: 'Personal Growth', crossRefs: ['Health & Body', 'Career & Work'] },
    ]);
    expect(groups.get('Personal Growth')).toEqual([1]);
    expect(groups.get('Health & Body')).toEqual([1]);
    expect(groups.get('Career & Work')).toEqual([1]);
    expect(groups.get('Politics & Society')).toEqual([]);
  });
  it('dedups when a cross-ref repeats the primary category', () => {
    const groups = groupNotesByCategory([
      { noteId: 7, category: 'Daily Systems', crossRefs: ['Daily Systems'] },
    ]);
    expect(groups.get('Daily Systems')).toEqual([7]);
  });
  it('ignores categories outside the controlled list', () => {
    const groups = groupNotesByCategory([
      { noteId: 9, category: 'Made Up', crossRefs: ['Also Fake'] },
    ]);
    for (const ids of groups.values()) expect(ids).not.toContain(9);
  });
  it('treats a comma-joined primary category (real prod data) as multi-membership', () => {
    const groups = groupNotesByCategory([
      { noteId: 5, category: 'Health & Body, Projects & Tech, Career & Work', crossRefs: [] },
    ]);
    expect(groups.get('Health & Body')).toEqual([5]);
    expect(groups.get('Projects & Tech')).toEqual([5]);
    expect(groups.get('Career & Work')).toEqual([5]);
    expect(groups.get('Personal Growth')).toEqual([]);
  });
});

describe('uncategorizedNoteIds', () => {
  it('returns notes that match zero valid categories', () => {
    expect(uncategorizedNoteIds([
      { noteId: 1, category: 'Personal Growth', crossRefs: [] },
      { noteId: 2, category: null, crossRefs: [] },
      { noteId: 3, category: 'Bogus', crossRefs: ['Nope'] },
    ])).toEqual([2, 3]);
  });
});

describe('subSlug', () => {
  it('namespaces sub under category slug', () => {
    expect(subSlug('Health & Body', 'Running')).toBe('health-body/running');
  });
});

describe('isValidClusterSlug (orphan-cleanup guard)', () => {
  const cats = CATEGORIES.map(slugForCategory);
  it('keeps an exact category slug', () => {
    expect(isValidClusterSlug('health-body', cats)).toBe(true);
  });
  it('KEEPS a valid sub-slug (landmine: must not be deleted)', () => {
    expect(isValidClusterSlug('health-body/running', cats)).toBe(true);
  });
  it('DELETES a true orphan (old concept-hash slug)', () => {
    expect(isValidClusterSlug('running-a1b2c3', cats)).toBe(false);
  });
  it('DELETES a sub-slug whose parent is not a real category', () => {
    expect(isValidClusterSlug('bogus-parent/running', cats)).toBe(false);
  });
});

describe('extractCategoryFields', () => {
  it('extracts category + valid cross-refs from an LLM JSON blob with surrounding text', () => {
    const r = 'Sure!\n{"category":"Health & Body","cross_ref_categories":["Personal Growth","Bogus"]}\nDone';
    expect(extractCategoryFields(r)).toEqual({
      category: 'Health & Body',
      crossRefs: ['Personal Growth'],
    });
  });
  it('returns null category when missing/invalid and [] cross-refs on parse failure', () => {
    expect(extractCategoryFields('no json here')).toEqual({ category: null, crossRefs: [] });
    expect(extractCategoryFields('{"category":"Invalid"}')).toEqual({ category: null, crossRefs: [] });
  });
});

describe('parseSubCategories (closed-set)', () => {
  const allowed = { 'Health & Body': ['Running', 'Sleep'], 'Projects & Tech': ['Selene'] };

  it('keeps only values in that category seed list', () => {
    const r = parseSubCategories('{"Health & Body":"Running","Projects & Tech":"Nope"}', allowed);
    expect(r).toEqual({ 'Health & Body': 'Running' });
  });
  it('drops "none"', () => {
    expect(parseSubCategories('{"Health & Body":"none"}', allowed)).toEqual({});
  });
  it('ignores categories not in the allowed map', () => {
    expect(parseSubCategories('{"Career & Work":"Job"}', allowed)).toEqual({});
  });
  it('returns {} on malformed JSON', () => {
    expect(parseSubCategories('not json', allowed)).toEqual({});
  });
  it('finds JSON embedded in chatty output', () => {
    expect(parseSubCategories('Sure! {"Health & Body":"Sleep"} ok', allowed))
      .toEqual({ 'Health & Body': 'Sleep' });
  });
});

describe('buildSubCategoryPrompt', () => {
  it('lists each assigned category with its seed options', () => {
    const p = buildSubCategoryPrompt('T', 'C', { 'Health & Body': ['Running', 'Sleep'] });
    expect(p).toContain('Health & Body');
    expect(p).toContain('Running');
    expect(p).toContain('none');
  });
});

describe('groupNotesBySubCategory', () => {
  it('groups a note under a sub-cat for EACH parent it belongs to', () => {
    const notes = [{
      noteId: 1,
      category: 'Health & Body',
      crossRefs: ['Projects & Tech'],
      subCategories: { 'Health & Body': 'Running', 'Projects & Tech': 'Side Projects' },
    }];
    const g = groupNotesBySubCategory(notes);
    expect(g.get('Health & Body')?.get('Running')).toEqual([1]);
    expect(g.get('Projects & Tech')?.get('Side Projects')).toEqual([1]);
  });

  it('omits a category whose sub-cat is unassigned', () => {
    const notes = [{ noteId: 2, category: 'Health & Body', crossRefs: [], subCategories: {} }];
    const g = groupNotesBySubCategory(notes);
    expect(g.get('Health & Body')?.size ?? 0).toBe(0);
  });

  it('ignores a sub-cat for a category the note is NOT actually in', () => {
    const notes = [{ noteId: 3, category: 'Health & Body', crossRefs: [],
      subCategories: { 'Career & Work': 'Job' } }];
    const g = groupNotesBySubCategory(notes);
    expect(g.get('Career & Work')?.size ?? 0).toBe(0);
  });
});

describe('buildAllowedFor', () => {
  it('returns seed lists only for the categories the note landed in', () => {
    const allowed = buildAllowedFor('Health & Body', ['Projects & Tech']);
    expect(Object.keys(allowed).sort()).toEqual(['Health & Body', 'Projects & Tech']);
    expect(allowed['Health & Body'].length).toBeGreaterThan(0);
  });
  it('returns {} when there are no valid categories', () => {
    expect(buildAllowedFor(null, [])).toEqual({});
  });
});

describe('aggregateSubCoverage', () => {
  it('counts each note under its assigned sub, else under none, per category', () => {
    const rows: CoverageRow[] = [
      { categories: ['Health & Body'], subCategories: { 'Health & Body': 'Running' } },
      { categories: ['Health & Body'], subCategories: {} },                 // -> none
      { categories: ['Health & Body', 'Projects & Tech'],
        subCategories: { 'Health & Body': 'Running', 'Projects & Tech': 'Selene' } },
    ];
    const cov = aggregateSubCoverage(rows);
    expect(cov['Health & Body']).toEqual({ Running: 2, none: 1 });
    expect(cov['Projects & Tech']).toEqual({ Selene: 1 });
  });
  it('returns {} for no rows', () => {
    expect(aggregateSubCoverage([])).toEqual({});
  });
  it('counts a category-membership with an unassigned sub as none', () => {
    const cov = aggregateSubCoverage([{ categories: ['Daily Systems'], subCategories: {} }]);
    expect(cov['Daily Systems']).toEqual({ none: 1 });
  });
});
