import { config } from './config';

describe('factsDbPath', () => {
  it('ends in facts.db', () => {
    expect(config.factsDbPath).toMatch(/facts\.db$/);
  });
  it('lives in the same directory as dbPath', () => {
    const dir = (p: string) => p.replace(/\/[^/]+$/, '');
    expect(dir(config.factsDbPath)).toBe(dir(config.dbPath));
  });
});
