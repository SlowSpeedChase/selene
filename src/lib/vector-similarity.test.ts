import {
  cosineSimilarity,
  similarityFromCosineDistance,
  computeConnections,
  EmbeddedNote,
} from './vector-similarity';

describe('cosineSimilarity', () => {
  it('returns 1 for identical-direction vectors', () => {
    expect(cosineSimilarity([1, 0, 0], [1, 0, 0])).toBeCloseTo(1, 6);
  });

  it('returns 0 for orthogonal vectors', () => {
    expect(cosineSimilarity([1, 0], [0, 1])).toBeCloseTo(0, 6);
  });

  it('returns -1 for opposite vectors', () => {
    expect(cosineSimilarity([1, 0], [-1, 0])).toBeCloseTo(-1, 6);
  });

  it('is magnitude-invariant (the bug nomic-embed exposed: norm ~20, not 1)', () => {
    // Same direction, very different magnitudes -> still perfectly similar.
    expect(cosineSimilarity([3, 0], [1, 0])).toBeCloseTo(1, 6);
    expect(cosineSimilarity([20, 0, 0], [0.5, 0, 0])).toBeCloseTo(1, 6);
  });

  it('returns 0 when either vector is all zeros (no direction)', () => {
    expect(cosineSimilarity([0, 0], [1, 1])).toBe(0);
    expect(cosineSimilarity([1, 1], [0, 0])).toBe(0);
  });
});

describe('similarityFromCosineDistance', () => {
  // LanceDB cosine-metric `_distance` is (1 - cos), range [0, 2].
  it('maps cosine distance 0 -> similarity 1', () => {
    expect(similarityFromCosineDistance(0)).toBeCloseTo(1, 6);
  });

  it('maps cosine distance 1 (orthogonal) -> similarity 0', () => {
    expect(similarityFromCosineDistance(1)).toBeCloseTo(0, 6);
  });

  it('maps cosine distance 2 (opposite) -> similarity -1', () => {
    expect(similarityFromCosineDistance(2)).toBeCloseTo(-1, 6);
  });

  it('keeps a genuinely-related pair positive and above 0.75 (regression vs the 1-d^2/2 bug)', () => {
    // Measured: "improv dinner" ~ "improv potluck" cosine ~0.78 -> cosine distance ~0.22.
    // The old `1 - distance^2/2` on squared-L2 produced large NEGATIVES here.
    const sim = similarityFromCosineDistance(0.22);
    expect(sim).toBeGreaterThan(0.75);
    expect(sim).toBeCloseTo(0.78, 2);
  });
});

describe('computeConnections', () => {
  const notes: EmbeddedNote[] = [
    { id: 1, createdAt: '2026-01-01T00:00:00Z', vector: [1, 0, 0] },
    { id: 2, createdAt: '2026-01-10T00:00:00Z', vector: [0.9, 0.1, 0] }, // ~ note 1
    { id: 3, createdAt: '2026-01-20T00:00:00Z', vector: [0, 0, 1] }, // orthogonal to both
  ];

  it('emits one connection for the single similar pair above threshold', () => {
    const conns = computeConnections(notes, 0.75);
    expect(conns).toHaveLength(1);
    expect(conns[0].similarity).toBeGreaterThan(0.75);
  });

  it('orients the connection newer -> older (source = later createdAt)', () => {
    const conns = computeConnections(notes, 0.75);
    expect(conns[0].sourceId).toBe(2); // 2026-01-10 is newer
    expect(conns[0].targetId).toBe(1); // 2026-01-01 is older
  });

  it('excludes pairs below the threshold', () => {
    expect(computeConnections(notes, 0.999)).toHaveLength(0);
  });

  it('emits each undirected pair only once (no double-counting)', () => {
    const dup: EmbeddedNote[] = [
      { id: 10, createdAt: '2026-02-01T00:00:00Z', vector: [1, 0] },
      { id: 11, createdAt: '2026-02-02T00:00:00Z', vector: [1, 0] },
    ];
    expect(computeConnections(dup, 0.75)).toHaveLength(1);
  });
});
