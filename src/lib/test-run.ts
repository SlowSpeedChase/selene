import { config } from './config';

/**
 * Production-safety SQL fragment that excludes ephemeral `test_run` notes from
 * real output (digests, exports, clusters, worksheets).
 *
 * In **development** the entire database is test-seeded — every fixture carries
 * `test_run = 'dev-seed'` — so applying the guard would erase the whole dataset
 * and leave the dev/test app empty. Return an empty fragment there.
 *
 * In **production** (and tests) the fragment is identical to the long-standing
 * hardcoded guard, so behavior is byte-for-byte unchanged.
 *
 * @param alias  the `raw_notes` table alias used in the query (e.g. `'rn'`,
 *               `'src'`). Pass `''` (the default) when the column is unqualified.
 * @returns      `"AND <alias>.test_run IS NULL"` outside development, else `''`.
 */
export function testRunFilter(alias = ''): string {
  if (config.env === 'development') return '';
  const prefix = alias ? `${alias}.` : '';
  return `AND ${prefix}test_run IS NULL`;
}
