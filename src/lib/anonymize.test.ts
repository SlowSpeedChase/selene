import assert from 'assert';

async function runTests() {
  const { anonymize, deanonymize } = await import('./anonymize');

  // Test 1: Email replaced
  {
    const result = anonymize('Contact me at chase@example.com please');
    assert.ok(!result.text.includes('chase@example.com'), 'Email should be replaced');
    assert.ok(result.text.includes('[EMAIL_'), 'Email replaced with token');
    console.log('  ✓ Email addresses are anonymized');
  }

  // Test 2: Phone number replaced
  {
    const result = anonymize('Call me at 555-867-5309');
    assert.ok(!result.text.includes('555-867-5309'), 'Phone should be replaced');
    console.log('  ✓ Phone numbers are anonymized');
  }

  // Test 3: URL replaced
  {
    const result = anonymize('Visit https://my-private-site.com/secret-page for details');
    assert.ok(!result.text.includes('my-private-site.com'), 'URL should be replaced');
    console.log('  ✓ URLs are anonymized');
  }

  // Test 4: Token map allows deanonymization
  {
    const original = 'Email john@test.com or call 555-123-4567';
    const { text, tokenMap } = anonymize(original);
    const restored = deanonymize(text, tokenMap);
    assert.strictEqual(restored, original, 'Deanonymized text matches original');
    console.log('  ✓ Token map allows exact restoration');
  }

  // Test 5: Safe text passes through unchanged
  {
    const safe = 'The quick brown fox jumps over the lazy dog';
    const result = anonymize(safe);
    assert.strictEqual(result.text, safe, 'Safe text unchanged');
    console.log('  ✓ Safe text passes through unchanged');
  }

  // Test 6: Multiple emails get distinct tokens
  {
    const result = anonymize('From: alice@a.com To: bob@b.com');
    assert.ok(result.text.includes('[EMAIL_1]'), 'First email token');
    assert.ok(result.text.includes('[EMAIL_2]'), 'Second email token');
    console.log('  ✓ Multiple instances get distinct tokens');
  }

  // Test 7: anonymizeWithNER replaces structured PII at minimum (NER optional)
  {
    const { anonymizeWithNER } = await import('./anonymize');
    const input = 'Email test@example.com or visit https://example.com';
    const { text, tokenMap } = await anonymizeWithNER(input);
    assert.ok(!text.includes('test@example.com'), 'NER pass: email should be replaced');
    assert.ok(!text.includes('https://example.com'), 'NER pass: URL should be replaced');
    assert.ok(Object.keys(tokenMap).length >= 2, 'Token map has entries');
    console.log('  ✓ anonymizeWithNER replaces structured PII (NER layer is additive)');
  }

  console.log('\nAll anonymize tests passed!');
}

runTests().catch((err) => {
  console.error('Tests failed:', err);
  process.exit(1);
});
