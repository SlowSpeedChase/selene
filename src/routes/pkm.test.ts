import type { Database as DB } from 'better-sqlite3';
import { rmSync } from 'fs';
import Fastify, { FastifyInstance } from 'fastify';
import { pkmRoutes, isLanIp } from './pkm';
import { makeTwoFileTestDb } from '../lib/test-two-file-db';

// Fact-store split: review_state lives in facts.db and the routes read the `raw_notes` TEMP view,
// so the test DB is the real two-file layout. The note FACT goes into facts.captured_notes (+ a
// note_state row giving it status='processed'); markSurfaced (hit by GET /notes/:id) writes
// facts.review_state. Returns the dir so the caller can clean up the temp files.
function seedDb(): { db: DB; dir: string } {
  const { db, dir } = makeTwoFileTestDb();
  db.exec(`
    CREATE TABLE processed_notes (raw_note_id INTEGER, concepts TEXT, essence TEXT,
      primary_theme TEXT, category TEXT, cross_ref_categories TEXT);
  `);
  db.prepare(
    `INSERT INTO facts.captured_notes (id, title, content, content_hash, created_at)
     VALUES (1, 'A note', 'body', 'h1', '2026-05-01')`
  ).run();
  db.prepare(`INSERT INTO note_state (raw_note_id, status) VALUES (1, 'processed')`).run();
  db.prepare('INSERT INTO processed_notes VALUES (?,?,?,?,?,?)').run(1, '["focus"]', 'an essence', 't', 'Health & Body', '[]');
  return { db, dir };
}

async function buildApp(db: DB): Promise<FastifyInstance> {
  const app = Fastify();
  await app.register(pkmRoutes(db), { prefix: '/pkm' });
  await app.ready();
  return app;
}

describe('isLanIp', () => {
  it('allows private/loopback + Tailscale, denies public', () => {
    expect(isLanIp('127.0.0.1')).toBe(true);
    expect(isLanIp('192.168.1.50')).toBe(true);
    expect(isLanIp('10.0.0.4')).toBe(true);
    expect(isLanIp('172.16.5.5')).toBe(true);
    // Tailscale tailnet (CGNAT 100.64.0.0/10) — e.g. the Mac mini at 100.111.6.10.
    expect(isLanIp('100.111.6.10')).toBe(true);
    expect(isLanIp('100.64.0.1')).toBe(true);
    expect(isLanIp('100.127.255.255')).toBe(true);
    expect(isLanIp('8.8.8.8')).toBe(false);
    expect(isLanIp('172.32.0.1')).toBe(false);
    expect(isLanIp('100.128.0.1')).toBe(false); // just outside the /10
  });
});

describe('pkm routes', () => {
  let db: DB;
  let dir: string;
  let app: FastifyInstance;

  beforeEach(async () => { ({ db, dir } = seedDb()); app = await buildApp(db); });
  afterEach(async () => { await app.close(); db.close(); rmSync(dir, { recursive: true, force: true }); });

  it('GET /pkm/ returns HTML home', async () => {
    const res = await app.inject({ method: 'GET', url: '/pkm/', remoteAddress: '127.0.0.1' });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('text/html');
    expect(res.body).toContain('Selene');
  });

  it('GET /pkm/notes/:id renders the note AND records a resurfacing', async () => {
    const res = await app.inject({ method: 'GET', url: '/pkm/notes/1', remoteAddress: '127.0.0.1' });
    expect(res.statusCode).toBe(200);
    expect(res.body).toContain('A note');
    const row = db.prepare("SELECT surface_count AS c FROM review_state WHERE entity_type='note' AND entity_id='1'").get() as { c: number };
    expect(row.c).toBe(1);
  });

  it('GET /pkm/notes/:id returns 404 for a missing note', async () => {
    const res = await app.inject({ method: 'GET', url: '/pkm/notes/9999', remoteAddress: '127.0.0.1' });
    expect(res.statusCode).toBe(404);
  });

  it('blocks a non-LAN client with 403', async () => {
    const res = await app.inject({ method: 'GET', url: '/pkm/', remoteAddress: '8.8.8.8' });
    expect(res.statusCode).toBe(403);
  });
});
