/** @type {import('ts-jest').JestConfigWithTsJest} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  // Run EVERY *.test.ts under one convention. This deliberately REPLACES the old
  // hand-maintained allowlist: with a glob, a newly-added test can never be silently
  // forgotten (the old allowlist had silently dropped real tests). The legacy custom
  // runTests()/vitest test files were migrated to jest describe/it in 2026-06.
  testMatch: ['**/*.test.ts'],
  // Never run tests outside the live source tree: node_modules, the archived shelved-*
  // trees (they import deleted modules), build output, and sibling git worktrees under
  // .claude/ (see the modulePathIgnorePatterns note below).
  testPathIgnorePatterns: [
    '/node_modules/',
    '<rootDir>/archive/',
    '<rootDir>/dist/',
    '<rootDir>/.claude/',
  ],
  transform: {
    '^.+\\.tsx?$': ['ts-jest', {
      tsconfig: {
        module: 'commonjs',
      },
    }],
  },
  moduleNameMapper: {
    '@lancedb/lancedb': '<rootDir>/src/__mocks__/lancedb.ts',
  },
  // Child git worktrees under .claude/worktrees/ carry their own copies of
  // package.json + src/__mocks__/lancedb.ts, which collide in jest's haste map and
  // corrupt module resolution for the REAL root tests (e.g. rebuild-core's
  // absent-column tolerance throws instead of being caught). The parent repo's jest
  // must never scan sibling worktrees. (Do NOT delete the worktrees — they're locked
  // on live feature branches.)
  modulePathIgnorePatterns: ['<rootDir>/.claude/'],
};
