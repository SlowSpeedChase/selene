import { cosineSimilarity } from './cosine';

describe('cosineSimilarity', () => {
  it('identical vectors return 1.0', () => {
    const a = [1, 2, 3];
    expect(cosineSimilarity(a, a)).toBeCloseTo(1.0, 5);
  });

  it('orthogonal vectors return 0.0', () => {
    expect(cosineSimilarity([1, 0], [0, 1])).toBeCloseTo(0.0, 5);
  });

  it('opposite vectors return -1.0', () => {
    expect(cosineSimilarity([1, 0], [-1, 0])).toBeCloseTo(-1.0, 5);
  });

  it('768-dimension vectors of all 0.1 return ~1.0', () => {
    const a = new Array(768).fill(0.1);
    const b = new Array(768).fill(0.1);
    expect(cosineSimilarity(a, b)).toBeCloseTo(1.0, 3);
  });

  it('random 768-dim vectors return result between -1 and 1', () => {
    const a = Array.from({ length: 768 }, () => Math.random() * 2 - 1);
    const b = Array.from({ length: 768 }, () => Math.random() * 2 - 1);
    const result = cosineSimilarity(a, b);
    expect(result).toBeGreaterThanOrEqual(-1);
    expect(result).toBeLessThanOrEqual(1);
  });
});
