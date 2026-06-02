import { verdict, thresholdsFromEnv, drainDecision, Snapshot, Thresholds } from './rebuild-core';

const DEFAULT_T: Thresholds = { coverageMin: 0.95, driftTolerance: 0.2 };

const snap = (over: Partial<Snapshot> = {}): Snapshot => ({
  captured: 100, processed: 100, essences: 100, embeddings: 100,
  clusters: 10, clusterLinks: 100, exported: 100, ...over,
});

describe('verdict', () => {
  it('passes when coverage meets the floor and no metric collapses', () => {
    const v = verdict(snap(), snap(), DEFAULT_T);
    expect(v.pass).toBe(true);
    expect(v.reasons).toEqual([]);
    expect(v.coverage).toBe(1);
  });

  it('fails when coverage is below the floor', () => {
    const pre = snap();
    const post = snap({ processed: 90 }); // 90/100 = 0.90 < 0.95
    const v = verdict(pre, post, DEFAULT_T);
    expect(v.pass).toBe(false);
    expect(v.coverage).toBeCloseTo(0.9);
    expect(v.reasons.some((r) => r.includes('coverage'))).toBe(true);
  });

  it('fails when a derived metric collapses past tolerance', () => {
    const pre = snap();
    // embeddings drops 100 -> 70 = -30% (< -20% tolerance). Keep coverage healthy.
    const post = snap({ embeddings: 70 });
    const v = verdict(pre, post, DEFAULT_T);
    expect(v.pass).toBe(false);
    expect(v.reasons.some((r) => r.includes('embeddings'))).toBe(true);
  });

  it('allows upward drift (a metric growing)', () => {
    const pre = snap();
    const post = snap({ embeddings: 200, clusters: 50 });
    const v = verdict(pre, post, DEFAULT_T);
    expect(v.pass).toBe(true);
    expect(v.reasons).toEqual([]);
  });

  it('skips drift on a metric whose baseline was zero', () => {
    const pre = snap({ embeddings: 0 });
    const post = snap({ embeddings: 0 }); // would be 0/0; must be skipped, not NaN-fail
    const v = verdict(pre, post, DEFAULT_T);
    expect(v.pass).toBe(true);
    expect(v.reasons).toEqual([]);
  });
});

describe('drainDecision', () => {
  const CAP = 1000;
  it('continues while work remains and a pass made progress', () => {
    // remaining 80, previous 100 (progress), iteration mid-range.
    expect(drainDecision(80, 100, 5, CAP)).toBe('continue');
  });

  it('stops (drained) when nothing remains', () => {
    expect(drainDecision(0, 50, 5, CAP)).toBe('drained');
  });

  it('stops (stalled) when a pass made no progress — a stuck note', () => {
    // remaining didn't move from the previous pass, but is non-zero.
    expect(drainDecision(7, 7, 5, CAP)).toBe('stalled');
  });

  it('stops (capped) at the iteration ceiling even with work remaining', () => {
    expect(drainDecision(7, 100, CAP, CAP)).toBe('capped');
  });

  it('drained takes precedence over capped (a clean finish on the last allowed pass)', () => {
    expect(drainDecision(0, 100, CAP, CAP)).toBe('drained');
  });

  it('first iteration with a fresh sentinel previous never false-stalls', () => {
    // previous = Infinity sentinel on iteration 0: must not read as no-progress.
    expect(drainDecision(500, Infinity, 0, CAP)).toBe('continue');
  });
});

describe('thresholdsFromEnv', () => {
  it('uses the agreed defaults when env is unset', () => {
    expect(thresholdsFromEnv({})).toEqual({ coverageMin: 0.95, driftTolerance: 0.2 });
  });

  it('honors COVERAGE_MIN override', () => {
    expect(thresholdsFromEnv({ COVERAGE_MIN: '0.8' })).toEqual({
      coverageMin: 0.8, driftTolerance: 0.2,
    });
  });

  it('honors DRIFT_TOLERANCE override', () => {
    expect(thresholdsFromEnv({ DRIFT_TOLERANCE: '0.5' })).toEqual({
      coverageMin: 0.95, driftTolerance: 0.5,
    });
  });

  it('falls back to the default when COVERAGE_MIN is non-numeric (no NaN fail-open)', () => {
    expect(thresholdsFromEnv({ COVERAGE_MIN: '0.9x' })).toEqual({
      coverageMin: 0.95, driftTolerance: 0.2,
    });
  });

  it('falls back to the default when COVERAGE_MIN is an empty string', () => {
    expect(thresholdsFromEnv({ COVERAGE_MIN: '' })).toEqual({
      coverageMin: 0.95, driftTolerance: 0.2,
    });
  });
});
