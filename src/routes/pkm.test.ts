import Database from 'better-sqlite3';
import Fastify, { FastifyInstance } from 'fastify';
import { pkmRoutes, isLanIp } from './pkm';

type DB = InstanceType<typeof Database>;

function seedDb(): DB {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE raw_notes (id INTEGER PRIMARY KEY, title TEXT, content TEXT, created_at TEXT,
      status TEXT, test_run TEXT);
    CREATE TABLE processed_notes (raw_note_id INTEGER, concepts TEXT, essence TEXT,
      primary_theme TEXT, category TEXT, cross_ref_categories TEXT);
  `);
  db.prepare('INSERT INTO raw_notes VALUES (?,?,?,?,?,?)').run(1, 'A note', 'body', '2026-05-01', 'processed', null);
  db.prepare('INSERT INTO processed_notes VALUES (?,?,?,?,?,?)').run(1, '["focus"]', 'an essence', 't', 'Health & Body', '[]');
  return db;
}

async function buildApp(db: DB): Promise<FastifyInstance> {
  const app = Fastify();
  await app.register(pkmRoutes(db), { prefix: '/pkm' });
  await app.ready();
  return app;
}

describe('isLanIp', () => {
  it('allows private/loopback, denies public', () => {
    expect(isLanIp('127.0.0.1')).toBe(true);
    expect(isLanIp('192.168.1.50')).toBe(true);
    expect(isLanIp('10.0.0.4')).toBe(true);
    expect(isLanIp('172.16.5.5')).toBe(true);
    expect(isLanIp('8.8.8.8')).toBe(false);
    expect(isLanIp('172.32.0.1')).toBe(false);
  });
});

describe('pkm routes', () => {
  let db: DB;
  let app: FastifyInstance;

  beforeEach(async () => { db = seedDb(); app = await buildApp(db); });
  afterEach(async () => { await app.close(); db.close(); });

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
    const row = db.prepare("SELECT surface_count AS c FROM pkm_review_state WHERE entity_type='note' AND entity_id='1'").get() as { c: number };
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
