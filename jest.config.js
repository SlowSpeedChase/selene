/** @type {import('ts-jest').JestConfigWithTsJest} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  // Only run test files that use proper Jest describe/it format.
  // Existing tests use a custom runTests() + assert pattern and are excluded.
  testMatch: [
    '**/scripts/migrate-to-fact-store.test.ts',
    '**/src/lib/category-clusters.test.ts',
    '**/src/lib/config.test.ts',
    '**/src/lib/constellation.test.ts',
    '**/src/lib/constellation.db.test.ts',
    '**/src/lib/cosine.test.ts',
    '**/src/lib/db-capture.test.ts',
    '**/src/lib/db-config.test.ts',
    '**/src/lib/db-pending.test.ts',
    '**/src/lib/facts-db.test.ts',
    '**/src/lib/inspect.test.ts',
    '**/src/lib/note-state.test.ts',
    '**/src/lib/obsidian-render.test.ts',
    '**/src/lib/obsidian-render.db.test.ts',
    '**/src/lib/pkm-db.test.ts',
    '**/src/lib/pkm-queries.test.ts',
    '**/src/lib/pkm-render.test.ts',
    '**/src/lib/synthesis-db.test.ts',
    '**/src/lib/system-map.test.ts',
    '**/src/lib/synthesis-digest.test.ts',
    '**/src/lib/view-mode-readers.test.ts',
    '**/src/routes/notes.test.ts',
    '**/src/routes/pkm.test.ts',
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
};
