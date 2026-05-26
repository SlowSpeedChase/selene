import { describe, it, expect, afterAll } from 'vitest';
import Fastify from 'fastify';
import Database from 'better-sqlite3';
import { join } from 'path';
import { homedir } from 'os';
import { worksheetRoutes } from './worksheets';

const TEST_RUN = `test-worksheets-${Date.now()}`;
const DB_PATH = process.env.SELENE_DB_PATH || join(homedir(), 'selene-data/selene.db');

afterAll(() => {
  const db = new Database(DB_PATH);
  db.prepare('DELETE FROM raw_notes WHERE test_run = ?').run(TEST_RUN);
  db.close();
});

describe('worksheet routes', () => {
  it('GET /api/worksheets/today returns a free_capture worksheet', async () => {
    const app = Fastify();
    await app.register(worksheetRoutes);
    const res = await app.inject({ method: 'GET', url: '/api/worksheets/today' });
    expect(res.statusCode).toBe(200);
    expect(res.json().fields[0].kind).toBe('free_capture');
    await app.close();
  });

  it('POST answers creates a note for non-blank text and skips blanks', async () => {
    const app = Fastify();
    await app.register(worksheetRoutes);
    const res = await app.inject({
      method: 'POST',
      url: '/api/worksheets/ws_test/answers',
      payload: {
        worksheetId: 'ws_test',
        test_run: TEST_RUN,
        answers: [
          { fieldId: 'f1', chosenAction: 'new_note', text: `dentist ${TEST_RUN}` },
          { fieldId: 'f2', chosenAction: 'new_note', text: '   ' },
        ],
      },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.results[0].outcome).toBe('applied');
    expect(body.results[0].noteId).toBeTypeOf('number');
    expect(body.results[1].outcome).toBe('skipped');
    await app.close();
  });
});
