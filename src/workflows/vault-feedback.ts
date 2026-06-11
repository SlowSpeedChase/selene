// @map purpose: Scan vault "Your note" sections → ingest author intent into facts.note_feedback + re-pend notes for re-derivation
// @map reads: Obsidian vault, raw_notes, processed_notes
// @map writes: note_feedback (facts.db), note_state
import { join } from 'path';
import { createWorkflowLogger, db, config } from '../lib';
import { scanVaultFeedback } from '../lib/vault-feedback';

const log = createWorkflowLogger('vault-feedback');

export function vaultFeedback(): ReturnType<typeof scanVaultFeedback> {
  const notesDir = join(config.vaultPath, 'Notes');
  log.info({ notesDir }, 'Scanning vault for author feedback');
  const result = scanVaultFeedback(db, notesDir, new Date().toISOString());
  log.info(result, 'Vault feedback scan complete');
  if (result.unmatched > 0) {
    log.warn({ unmatched: result.unmatched }, 'Files with feedback but no resolvable selene_id (skipped, untouched)');
  }
  if (result.errors > 0) {
    // filename + exception message only — never note content.
    log.error({ errorSamples: result.errorSamples }, 'Per-file scan failures');
  }
  return result;
}

// CLI entry point
if (require.main === module) {
  const result = vaultFeedback();
  console.log(JSON.stringify(result, null, 2));
  process.exit(result.errors > 0 ? 1 : 0);
}
