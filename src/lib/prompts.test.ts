import { EXTRACT_PROMPT, buildIntentBlock, buildEssencePrompt } from './prompts';

describe('buildIntentBlock', () => {
  it('empty -> empty string (EXTRACT_PROMPT {intent} replace is a no-op)', () => {
    expect(buildIntentBlock([])).toBe('');
  });

  it('renders each intent as a quoted bullet + the weighting instruction', () => {
    const block = buildIntentBlock(['a skill I enjoy', 'remember  for\nlater']);
    expect(block).toContain('- "a skill I enjoy"');
    expect(block).toContain('- "remember for later"'); // whitespace flattened
    expect(block).toContain('stated intent over the surface topic');
  });
});

describe('EXTRACT_PROMPT {intent} placeholder', () => {
  it('exists exactly once, after the content line', () => {
    expect(EXTRACT_PROMPT.split('{intent}')).toHaveLength(2);
    expect(EXTRACT_PROMPT.indexOf('{content}')).toBeLessThan(EXTRACT_PROMPT.indexOf('{intent}'));
  });
});

describe('buildEssencePrompt with intents', () => {
  it('includes author intent in the context block', () => {
    const p = buildEssencePrompt('t', 'c', null, null, ['a skill I enjoy']);
    expect(p).toContain('The author says this note means: "a skill I enjoy"');
  });
  it('backward compatible without intents', () => {
    expect(buildEssencePrompt('t', 'c', null, 'theme')).toContain('Theme: theme');
  });
});
