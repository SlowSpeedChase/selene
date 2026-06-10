import assert from 'assert';
import { redirectSeleneSingleton } from '../lib/test-two-file-db';

// things-metadata-enricher transitively imports ../lib/db (searchNotesKeyword), which opens a
// real DB connection on import and runs the dev/test _selene_metadata guard. Redirect the
// singleton to a throwaway DB BEFORE importing the module-under-test.
const { restore } = redirectSeleneSingleton('selene-things-metadata-enricher-test-');

import {
  ThingsMetadataEnricher,
  buildEnrichmentPrompt,
  parseOllamaResponse,
} from './things-metadata-enricher';

describe('things-metadata-enricher', () => {
  afterAll(() => restore());

  it('ThingsMetadataEnricher has correct name and allowed action types', () => {
    const agent = new ThingsMetadataEnricher('Test Project');
    assert.strictEqual(agent.name, 'things-metadata-enricher', 'Name is correct');
    assert.ok(agent.allowedActionTypes.includes('things.update_notes'), 'Allows update_notes');
    assert.ok(agent.allowedActionTypes.includes('things.add_tag'), 'Allows add_tag');
  });

  it('Enrichment prompt includes task name and related notes', () => {
    const prompt = buildEnrichmentPrompt('Doctor appointment', 'Recent notes about health checks and insurance');
    assert.ok(prompt.includes('Doctor appointment'), 'Prompt includes task name');
    assert.ok(prompt.includes('Recent notes about health checks'), 'Prompt includes related notes');
  });

  it('Ollama response parsing works', () => {
    const response = '{"tags": ["health", "admin"], "notes": "Annual checkup scheduling"}';
    const parsed = parseOllamaResponse(response);
    assert.deepStrictEqual(parsed?.tags, ['health', 'admin'], 'Tags parsed');
    assert.strictEqual(parsed?.notes, 'Annual checkup scheduling', 'Notes parsed');
  });

  it('Malformed Ollama response returns null gracefully', () => {
    const result = parseOllamaResponse('not json at all');
    assert.strictEqual(result, null, 'Returns null for malformed response');
  });
});
