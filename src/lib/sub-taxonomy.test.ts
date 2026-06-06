import { CATEGORIES } from '../lib/prompts';
import { SUB_TAXONOMY, subCategoriesFor } from '../config/sub-taxonomy';

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
