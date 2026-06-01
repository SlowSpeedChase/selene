/**
 * db-guard.test.ts
 *
 * Documents (and pins) the safety contract behind the jest-skip of the ensureMigrated()
 * startup call in db.ts.
 *
 * Why this matters: under jest, config.env resolves to 'development' (the repo's
 * .env.development sets SELENE_ENV=development) and config.dbPath is the REAL dev DB
 * (~/selene-data-dev/selene.db), which still has a physical raw_notes table. An unguarded
 * ensureMigrated(config.dbPath, ...) at db.ts startup would therefore AUTO-MIGRATE the real
 * dev DB the moment any test imports db.ts — catastrophic.
 *
 * db.ts guards that startup call with `if (!process.env.JEST_WORKER_ID)`. jest sets
 * JEST_WORKER_ID per worker (and to '1' even when running in-band), so the guard is always
 * true under jest and the auto-migration never fires here. This test asserts that linchpin
 * directly: if JEST_WORKER_ID were ever undefined under jest, the skip would silently fail.
 *
 * Note: the dev DB is NOT re-checked here. The discriminating proof that the dev DB was spared
 * is the read-only sqlite3 query run after the FULL suite (raw_notes type=table, no
 * raw_notes_legacy_backup). A per-test assertion can't guarantee it runs after the whole suite,
 * so it would be strictly weaker than that post-suite check. We keep this test import-free and
 * minimal — it asserts WHY db.ts is allowed to skip the call, nothing more.
 */
describe('db.ts startup guard contract', () => {
  it('runs under jest, so JEST_WORKER_ID is defined (the value the db.ts skip keys off)', () => {
    expect(process.env.JEST_WORKER_ID).toBeDefined();
  });
});
