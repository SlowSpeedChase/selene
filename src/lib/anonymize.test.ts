import assert from 'assert';
import { anonymize, deanonymize, anonymizeWithNER } from './anonymize';

describe('anonymize', () => {
  it('anonymizes email addresses', () => {
    const result = anonymize('Contact me at chase@example.com please');
    assert.ok(!result.text.includes('chase@example.com'), 'Email should be replaced');
    assert.ok(result.text.includes('[EMAIL_'), 'Email replaced with token');
  });

  it('anonymizes phone numbers', () => {
    const result = anonymize('Call me at 555-867-5309');
    assert.ok(!result.text.includes('555-867-5309'), 'Phone should be replaced');
  });

  it('anonymizes URLs', () => {
    const result = anonymize('Visit https://my-private-site.com/secret-page for details');
    assert.ok(!result.text.includes('my-private-site.com'), 'URL should be replaced');
  });

  it('allows exact restoration via the token map', () => {
    const original = 'Email john@test.com or call 555-123-4567';
    const { text, tokenMap } = anonymize(original);
    const restored = deanonymize(text, tokenMap);
    assert.strictEqual(restored, original, 'Deanonymized text matches original');
  });

  it('passes safe text through unchanged', () => {
    const safe = 'The quick brown fox jumps over the lazy dog';
    const result = anonymize(safe);
    assert.strictEqual(result.text, safe, 'Safe text unchanged');
  });

  it('gives multiple instances distinct tokens', () => {
    const result = anonymize('From: alice@a.com To: bob@b.com');
    assert.ok(result.text.includes('[EMAIL_1]'), 'First email token');
    assert.ok(result.text.includes('[EMAIL_2]'), 'Second email token');
  });

  it('anonymizeWithNER replaces structured PII at minimum (NER layer is additive)', async () => {
    const input = 'Email test@example.com or visit https://example.com';
    const { text, tokenMap } = await anonymizeWithNER(input);
    assert.ok(!text.includes('test@example.com'), 'NER pass: email should be replaced');
    assert.ok(!text.includes('https://example.com'), 'NER pass: URL should be replaced');
    assert.ok(Object.keys(tokenMap).length >= 2, 'Token map has entries');
  });
});
