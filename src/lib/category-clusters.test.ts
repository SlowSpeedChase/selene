import {
  slugForCategory,
  parseCrossRefs,
  groupNotesByCategory,
  uncategorizedNoteIds,
  extractCategoryFields,
} from './category-clusters';

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
