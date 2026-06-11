import { redirectSeleneSingleton } from '../lib/test-two-file-db';

// send-digest imports `db` from ../lib, and db.ts opens a real connection on import.
// Redirect the singleton to throwaway temp files BEFORE importing the module-under-test.
const { restore } = redirectSeleneSingleton('selene-send-digest-test-');

import assert from 'assert';
import { buildTrmnlPayload } from './send-digest';

describe('send-digest', () => {
  afterAll(() => restore());

  it('buildTrmnlPayload splits digest into bullets', () => {
    const digest = 'Focus on thread detection refinements\nReview voice input feedback\nCheck task extraction accuracy';
    const result = buildTrmnlPayload(digest);

    assert.strictEqual(result.merge_variables.title, 'Selene Daily');
    assert.ok(result.merge_variables.date.length > 0, 'date should be non-empty');
    assert.deepStrictEqual(result.merge_variables.bullets, [
      'Focus on thread detection refinements',
      'Review voice input feedback',
      'Check task extraction accuracy',
    ]);
  });

  it('buildTrmnlPayload filters empty lines', () => {
    const digest = 'Line one\n\n\nLine two\n';
    const result = buildTrmnlPayload(digest);

    assert.deepStrictEqual(result.merge_variables.bullets, [
      'Line one',
      'Line two',
    ]);
  });

  it('buildTrmnlPayload handles single-line digest', () => {
    const digest = 'Just one bullet today';
    const result = buildTrmnlPayload(digest);

    assert.deepStrictEqual(result.merge_variables.bullets, [
      'Just one bullet today',
    ]);
  });
});
