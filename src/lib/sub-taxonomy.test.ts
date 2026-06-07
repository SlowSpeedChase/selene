import { CATEGORIES } from '../lib/prompts';
import { SUB_TAXONOMY, subCategoriesFor } from '../config/sub-taxonomy';
import { slugForCategory } from '../lib/category-clusters';

describe('sub-taxonomy seed config', () => {
  it('has an entry for every one of the 8 categories', () => {
    for (const cat of CATEGORIES) {
      expect(Array.isArray(SUB_TAXONOMY[cat])).toBe(true);
    }
    expect(Object.keys(SUB_TAXONOMY).sort()).toEqual([...CATEGORIES].sort());
  });

  it('subCategoriesFor returns the seed list for a known category', () => {
    expect(subCategoriesFor('Health & Body')).toEqual(SUB_TAXONOMY['Health & Body']);
  });

  it('subCategoriesFor returns [] for an unknown category', () => {
    expect(subCategoriesFor('Not A Category')).toEqual([]);
  });

  it('has no duplicate sub-categories within a category', () => {
    for (const cat of CATEGORIES) {
      const list = SUB_TAXONOMY[cat];
      expect(new Set(list).size).toBe(list.length);
    }
  });
});

describe('sub-taxonomy slug uniqueness (clobber guard)', () => {
  it('every sub-category within a category slugifies to a distinct slug', () => {
    for (const cat of CATEGORIES) {
      const slugs = SUB_TAXONOMY[cat].map((s) => slugForCategory(s));
      expect(new Set(slugs).size).toBe(slugs.length);
    }
  });
  it('no sub-category slugifies to an empty string', () => {
    for (const cat of CATEGORIES) {
      for (const sub of SUB_TAXONOMY[cat]) {
        expect(slugForCategory(sub).length).toBeGreaterThan(0);
      }
    }
  });
});
