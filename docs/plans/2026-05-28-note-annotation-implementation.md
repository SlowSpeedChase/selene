# Note Annotation (iPad) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an "Annotate" tab to SeleneMarkup that lets the user browse notes by topic cluster, open a raw capture, and draw Apple Pencil annotations on an infinite canvas below the note text — sending the ink back to Selene as a new linked note.

**Architecture:** Two repos touched. In Selene (TypeScript), we add a `source_note_id` column to `raw_notes` and a new `src/routes/notes.ts` with 4 endpoints (clusters list, notes in cluster, note detail, post annotation). In SeleneMarkup (Swift/iPad), we add `NoteModels`, `AnnotationService`, three views (`ClusterListView`, `NoteListView`, `NoteCanvasView`), and a `NoteMetaSheet` peek panel, then wire them into a new tab in `ContentView`. Annotations flow back as first-class raw notes with `source_note_id` set, so the entire Selene pipeline picks them up automatically.

**Tech Stack:**
- TypeScript + Fastify + better-sqlite3 (Selene server)
- Swift + SwiftUI + PencilKit + Vision framework (SeleneMarkup iPad app)
- Jest (server tests), XCTest (Swift tests)
- Deploy: `cd ~/SeleneMarkup && ./redeploy.sh`

---

## Context: Two Repos

| Repo | Path | What we touch |
|------|------|---------------|
| Selene (server) | `~/selene/` | Schema, new route file, server.ts |
| SeleneMarkup (iPad app) | `~/SeleneMarkup/` | Models, Service, Views, ContentView |

Run `npx jest` in `~/selene/` for server tests. For Swift, build via `cd ~/SeleneMarkup && xcodegen generate && xcodebuild -scheme SeleneMarkup -destination 'generic/platform=iOS' build`.

---

## Context: SeleneMarkup App Structure

```
Sources/SeleneMarkup/
  App/SeleneMarkupApp.swift    — @main entry, renders ContentView
  Models/AppConfig.swift       — server URL + bearer token from UserDefaults
  Models/Worksheet.swift       — worksheet data models
  Services/WorksheetService.swift — HTTP client pattern to follow
  Services/HandwritingService.swift — VNRecognizeTextRequest (Vision OCR)
  Views/ContentView.swift      — currently just shows WorksheetView()
  Views/CanvasView.swift       — PKCanvasView wrapper with ToolPicker
  Views/WorksheetView.swift    — existing worksheet UI
```

`WorksheetService` is the pattern to follow for all new service code: it uses an `HTTPSession` protocol so tests inject a mock without network calls.

The existing `CanvasView` and `HandwritingService` are reused as-is — don't modify them.

---

## Context: Selene Server

Main server: `~/selene/src/server.ts`, runs on port 5678 (launchd: `com.selene.server`).

Route files live in `src/routes/` and are registered via `server.register(routeFn)`. Auth: import `requireAuth` from `../lib/auth` and pass as `preHandler`.

Test pattern: Jest + in-memory SQLite (see `src/lib/synthesis-db.test.ts` for the template). Tests must be listed in `jest.config.js` `testMatch` array to run.

---

## Task 1: Schema Migration — Add `source_note_id` to `raw_notes`

**Files:**
- Modify: `~/selene/src/lib/db.ts`
- Run: SQL migration against `data/selene.db`

**Step 1: Add the column to the live database**

```bash
sqlite3 ~/selene-data/selene.db "ALTER TABLE raw_notes ADD COLUMN source_note_id INTEGER REFERENCES raw_notes(id);"
```

Expected: no output, no error.

**Step 2: Verify column exists**

```bash
sqlite3 ~/selene-data/selene.db ".schema raw_notes" | grep source_note_id
```

Expected: line containing `source_note_id INTEGER`.

**Step 3: Update the `RawNote` interface in `db.ts`**

In `~/selene/src/lib/db.ts`, find the `RawNote` interface (around line 51) and add the new field:

```typescript
export interface RawNote {
  // ... existing fields ...
  source_note_id: number | null;  // add this line
}
```

**Step 4: Update `insertNote` to accept `sourceNoteId`**

In the same file, find `insertNote` (around line 95). Add `sourceNoteId?: number` to the parameter type and include it in the INSERT:

```typescript
export function insertNote(note: {
  title: string;
  content: string;
  contentHash: string;
  tags: string[];
  createdAt: string;
  testRun?: string;
  captureType?: string;
  sourceUuid?: string;
  sourceNoteId?: number;   // add this
}): number {
  const wordCount = note.content.split(/\s+/).filter(Boolean).length;
  const characterCount = note.content.length;

  const result = db
    .prepare(
      `INSERT INTO raw_notes
       (title, content, content_hash, tags, word_count, character_count, created_at, status, test_run, capture_type, source_uuid, source_note_id)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?)`
    )
    .run(
      note.title,
      note.content,
      note.contentHash,
      JSON.stringify(note.tags),
      wordCount,
      characterCount,
      note.createdAt,
      note.testRun || null,
      note.captureType || 'drafts',
      note.sourceUuid || null,
      note.sourceNoteId || null,
    );

  return result.lastInsertRowid as number;
}
```

**Step 5: Type-check**

```bash
cd ~/selene && npx tsc --noEmit
```

Expected: no errors.

**Step 6: Commit**

```bash
cd ~/selene
git add src/lib/db.ts
git commit -m "feat: add source_note_id to raw_notes for annotation linking"
```

---

## Task 2: Server — Notes Route (`src/routes/notes.ts`)

This file adds 4 endpoints:
- `GET /api/clusters` — list topic clusters (id, name, slug, note_count, synthesis_text)
- `GET /api/clusters/:id/notes` — raw notes linked to a cluster
- `GET /api/notes/:id` — single raw note with processed_note metadata
- `POST /api/notes/:id/annotations` — creates a new raw note linked to parent

**Files:**
- Create: `~/selene/src/routes/notes.ts`
- Create: `~/selene/src/routes/notes.test.ts`

**Step 1: Write the failing tests first**

Create `~/selene/src/routes/notes.test.ts`:

```typescript
import Database from 'better-sqlite3';
import { buildNotesDb } from './notes';

describe('notes route helpers', () => {
  let db: InstanceType<typeof Database>;

  beforeEach(() => {
    db = new Database(':memory:');
    db.exec(`
      CREATE TABLE raw_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        content_hash TEXT UNIQUE NOT NULL,
        source_type TEXT DEFAULT 'drafts',
        word_count INTEGER DEFAULT 0,
        character_count INTEGER DEFAULT 0,
        tags TEXT,
        created_at DATETIME NOT NULL,
        imported_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        status TEXT DEFAULT 'pending',
        capture_type TEXT DEFAULT 'drafts',
        source_note_id INTEGER
      );
      CREATE TABLE topic_clusters (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        slug TEXT NOT NULL,
        synthesis_text TEXT,
        note_count INTEGER NOT NULL DEFAULT 0,
        is_proto INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      );
      CREATE TABLE topic_note_links (
        topic_id TEXT NOT NULL,
        note_id INTEGER NOT NULL,
        added_at TEXT NOT NULL,
        PRIMARY KEY (topic_id, note_id)
      );
      CREATE TABLE processed_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        raw_note_id INTEGER NOT NULL,
        essence TEXT,
        concepts TEXT,
        primary_theme TEXT
      );
    `);
  });

  afterEach(() => db.close());

  it('getClusters returns non-proto clusters ordered by note_count', () => {
    db.prepare(`INSERT INTO topic_clusters VALUES (?,?,?,?,?,?,?)`).run(
      'c1', 'Focus', 'focus', 'synthesis about focus', 3, 0, '2026-01-01'
    );
    db.prepare(`INSERT INTO topic_clusters VALUES (?,?,?,?,?,?,?)`).run(
      'c2', 'Proto', 'proto', null, 1, 1, '2026-01-01'
    );
    const { getClusters } = buildNotesDb(db);
    const result = getClusters();
    expect(result).toHaveLength(1);
    expect(result[0].id).toBe('c1');
  });

  it('getNotesForCluster returns raw notes linked to a cluster', () => {
    db.prepare(`INSERT INTO raw_notes (title, content, content_hash, created_at) VALUES (?,?,?,?)`).run(
      'Note A', 'Body A', 'hash-a', '2026-01-01'
    );
    db.prepare(`INSERT INTO topic_note_links VALUES (?,?,?)`).run('c1', 1, '2026-01-01');
    const { getNotesForCluster } = buildNotesDb(db);
    const result = getNotesForCluster('c1');
    expect(result).toHaveLength(1);
    expect(result[0].title).toBe('Note A');
  });

  it('getNoteById returns note with processed metadata', () => {
    db.prepare(`INSERT INTO raw_notes (title, content, content_hash, created_at) VALUES (?,?,?,?)`).run(
      'My Note', 'Content here', 'hash-1', '2026-01-01'
    );
    db.prepare(`INSERT INTO processed_notes (raw_note_id, essence, concepts, primary_theme) VALUES (?,?,?,?)`).run(
      1, 'A short essence', '["idea","focus"]', 'Productivity'
    );
    const { getNoteById } = buildNotesDb(db);
    const result = getNoteById(1);
    expect(result).not.toBeNull();
    expect(result!.title).toBe('My Note');
    expect(result!.essence).toBe('A short essence');
    expect(result!.primary_theme).toBe('Productivity');
  });

  it('insertAnnotation creates a new raw note linked to parent', () => {
    db.prepare(`INSERT INTO raw_notes (title, content, content_hash, created_at) VALUES (?,?,?,?)`).run(
      'Parent', 'Parent content', 'hash-p', '2026-01-01'
    );
    const { insertAnnotation, getNoteById } = buildNotesDb(db);
    const newId = insertAnnotation({ parentNoteId: 1, text: 'My annotation ink' });
    const note = getNoteById(newId);
    expect(note).not.toBeNull();
    expect(note!.source_note_id).toBe(1);
    expect(note!.content).toBe('My annotation ink');
    expect(note!.capture_type).toBe('annotation');
  });
});
```

**Step 2: Run test — expect failure (function not found)**

```bash
cd ~/selene && npx jest src/routes/notes.test.ts --no-coverage
```

Expected: FAIL — `Cannot find module './notes'`

**Step 3: Create the route file**

Create `~/selene/src/routes/notes.ts`:

```typescript
import type { FastifyInstance } from 'fastify';
import type { Database as DatabaseType } from 'better-sqlite3';
import { db as prodDb } from '../lib/db';
import { requireAuth } from '../lib/auth';
import crypto from 'crypto';

// ---------------------------------------------------------------------------
// DB helpers — extracted so tests can inject an in-memory database
// ---------------------------------------------------------------------------

export function buildNotesDb(db: DatabaseType) {
  function getClusters() {
    return db
      .prepare(
        `SELECT id, name, slug, synthesis_text, note_count
         FROM topic_clusters
         WHERE is_proto = 0
         ORDER BY note_count DESC`
      )
      .all() as Array<{
        id: string;
        name: string;
        slug: string;
        synthesis_text: string | null;
        note_count: number;
      }>;
  }

  function getNotesForCluster(clusterId: string) {
    return db
      .prepare(
        `SELECT r.id, r.title, r.created_at, r.word_count, r.tags
         FROM raw_notes r
         JOIN topic_note_links l ON l.note_id = r.id
         WHERE l.topic_id = ?
         ORDER BY r.created_at DESC`
      )
      .all(clusterId) as Array<{
        id: number;
        title: string;
        created_at: string;
        word_count: number;
        tags: string | null;
      }>;
  }

  function getNoteById(noteId: number) {
    const row = db
      .prepare(
        `SELECT r.id, r.title, r.content, r.created_at, r.tags, r.capture_type, r.source_note_id,
                p.essence, p.concepts, p.primary_theme
         FROM raw_notes r
         LEFT JOIN processed_notes p ON p.raw_note_id = r.id
         WHERE r.id = ?`
      )
      .get(noteId) as {
        id: number;
        title: string;
        content: string;
        created_at: string;
        tags: string | null;
        capture_type: string;
        source_note_id: number | null;
        essence: string | null;
        concepts: string | null;
        primary_theme: string | null;
      } | undefined;
    return row ?? null;
  }

  function insertAnnotation({
    parentNoteId,
    text,
  }: {
    parentNoteId: number;
    text: string;
  }): number {
    const contentHash = crypto.createHash('sha256').update(text).digest('hex');
    const now = new Date().toISOString();
    const result = db
      .prepare(
        `INSERT INTO raw_notes
         (title, content, content_hash, word_count, character_count,
          created_at, status, capture_type, source_note_id)
         VALUES (?, ?, ?, ?, ?, ?, 'pending', 'annotation', ?)`
      )
      .run(
        `Annotation on note ${parentNoteId}`,
        text,
        contentHash,
        text.split(/\s+/).filter(Boolean).length,
        text.length,
        now,
        parentNoteId,
      );
    return result.lastInsertRowid as number;
  }

  return { getClusters, getNotesForCluster, getNoteById, insertAnnotation };
}

// ---------------------------------------------------------------------------
// Fastify plugin
// ---------------------------------------------------------------------------

export async function notesRoutes(fastify: FastifyInstance): Promise<void> {
  const q = buildNotesDb(prodDb);

  fastify.get('/api/clusters', { preHandler: requireAuth }, async () => {
    return { clusters: q.getClusters() };
  });

  fastify.get<{ Params: { id: string } }>(
    '/api/clusters/:id/notes',
    { preHandler: requireAuth },
    async (request, reply) => {
      const notes = q.getNotesForCluster(request.params.id);
      if (!notes.length) {
        const clusters = q.getClusters();
        const exists = clusters.some(c => c.id === request.params.id);
        if (!exists) {
          reply.status(404);
          return { error: 'Cluster not found' };
        }
      }
      return { notes };
    }
  );

  fastify.get<{ Params: { id: string } }>(
    '/api/notes/:id',
    { preHandler: requireAuth },
    async (request, reply) => {
      const noteId = parseInt(request.params.id, 10);
      if (isNaN(noteId)) {
        reply.status(400);
        return { error: 'Invalid note id' };
      }
      const note = q.getNoteById(noteId);
      if (!note) {
        reply.status(404);
        return { error: 'Note not found' };
      }
      return { note };
    }
  );

  fastify.post<{ Params: { id: string }; Body: { text: string } }>(
    '/api/notes/:id/annotations',
    { preHandler: requireAuth },
    async (request, reply) => {
      const parentId = parseInt(request.params.id, 10);
      if (isNaN(parentId)) {
        reply.status(400);
        return { error: 'Invalid note id' };
      }
      const { text } = request.body;
      if (!text || text.trim().length === 0) {
        reply.status(400);
        return { error: 'text is required' };
      }
      const parent = q.getNoteById(parentId);
      if (!parent) {
        reply.status(404);
        return { error: 'Parent note not found' };
      }
      const newId = q.insertAnnotation({ parentNoteId: parentId, text: text.trim() });
      reply.status(201);
      return { id: newId, status: 'created' };
    }
  );
}
```

**Step 4: Add test to jest.config.js testMatch**

In `~/selene/jest.config.js`, add the test file to `testMatch`:

```javascript
testMatch: [
  '**/src/lib/cosine.test.ts',
  '**/src/lib/synthesis-db.test.ts',
  '**/src/lib/synthesis-digest.test.ts',
  '**/src/routes/notes.test.ts',  // add this line
],
```

**Step 5: Run tests — expect pass**

```bash
cd ~/selene && npx jest src/routes/notes.test.ts --no-coverage
```

Expected: 4 tests passing.

**Step 6: Commit**

```bash
cd ~/selene
git add src/routes/notes.ts src/routes/notes.test.ts jest.config.js
git commit -m "feat: notes route — clusters, note list, note detail, annotation endpoint"
```

---

## Task 3: Register Notes Routes in Server

**Files:**
- Modify: `~/selene/src/server.ts`

**Step 1: Import and register**

In `~/selene/src/server.ts`, add the import alongside the other route imports:

```typescript
import { notesRoutes } from './routes/notes';
```

Then add the registration just after `server.register(dashboardRoutes)`:

```typescript
server.register(notesRoutes);
```

**Step 2: Type-check**

```bash
cd ~/selene && npx tsc --noEmit
```

Expected: no errors.

**Step 3: Smoke-test the endpoints**

Make sure the Selene server is running (`curl http://localhost:5678/health`). If not, start it: `npx ts-node src/server.ts`.

```bash
# List clusters (needs auth token from .env — set TOKEN=<your token>)
TOKEN=$(grep API_TOKEN ~/selene/.env | cut -d= -f2)
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:5678/api/clusters | jq '.clusters | length'
```

Expected: a number ≥ 0 (your cluster count).

```bash
# Get a specific note (use an id from your database)
FIRST_ID=$(sqlite3 ~/selene-data/selene.db "SELECT id FROM raw_notes LIMIT 1;")
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:5678/api/notes/$FIRST_ID | jq '.note.title'
```

Expected: a quoted title string.

**Step 4: Commit**

```bash
cd ~/selene
git add src/server.ts
git commit -m "feat: register notes routes on main server"
```

---

## Task 4: Swift Models — `NoteModels.swift`

**Files:**
- Create: `~/SeleneMarkup/Sources/SeleneMarkup/Models/NoteModels.swift`

**Step 1: Create the file**

```swift
import Foundation

struct NoteCluster: Decodable, Identifiable {
    let id: String
    let name: String
    let slug: String
    let synthesis_text: String?
    let note_count: Int
}

struct ClusterNote: Decodable, Identifiable {
    let id: Int
    let title: String
    let created_at: String
    let word_count: Int
    let tags: String?
}

struct NoteDetail: Decodable, Identifiable {
    let id: Int
    let title: String
    let content: String
    let created_at: String
    let tags: String?
    let capture_type: String
    let source_note_id: Int?
    // Processed metadata (may be nil if not yet processed)
    let essence: String?
    let concepts: String?
    let primary_theme: String?
}

struct ClustersResponse: Decodable {
    let clusters: [NoteCluster]
}

struct ClusterNotesResponse: Decodable {
    let notes: [ClusterNote]
}

struct NoteDetailResponse: Decodable {
    let note: NoteDetail
}

struct AnnotationResponse: Decodable {
    let id: Int
    let status: String
}
```

**Step 2: Build to verify it compiles**

```bash
cd ~/SeleneMarkup && xcodegen generate && xcodebuild -scheme SeleneMarkup -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|Build succeeded|BUILD FAILED"
```

Expected: `Build succeeded`

**Step 3: Commit**

```bash
cd ~/SeleneMarkup
git add Sources/SeleneMarkup/Models/NoteModels.swift
git commit -m "feat: NoteCluster, ClusterNote, NoteDetail Swift models"
```

---

## Task 5: Swift Service — `AnnotationService`

Follow the exact same pattern as `WorksheetService`: `HTTPSession` protocol, injectable in tests.

**Files:**
- Create: `~/SeleneMarkup/Sources/SeleneMarkup/Services/AnnotationService.swift`
- Create: `~/SeleneMarkup/Tests/SeleneMarkupTests/AnnotationServiceTests.swift`

**Step 1: Write the failing tests**

Create `~/SeleneMarkup/Tests/SeleneMarkupTests/AnnotationServiceTests.swift`:

```swift
import XCTest
@testable import SeleneMarkup

final class MockHTTPSession: HTTPSession {
    var stubbedData: Data = Data()
    var stubbedResponse: URLResponse = HTTPURLResponse(
        url: URL(string: "http://test")!, statusCode: 200, httpVersion: nil, headerFields: nil
    )!
    var lastRequest: URLRequest?
    var shouldThrow: Error? = nil

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let err = shouldThrow { throw err }
        return (stubbedData, stubbedResponse)
    }
}

final class AnnotationServiceTests: XCTestCase {
    var service: AnnotationService!
    var mockSession: MockHTTPSession!

    override func setUp() {
        super.setUp()
        mockSession = MockHTTPSession()
        let config = AppConfig(baseURL: URL(string: "http://selene.local:5678")!, bearerToken: "test-token")
        service = AnnotationService(config: config, session: mockSession)
    }

    func testFetchClustersDecodesResponse() async throws {
        let json = """
        {"clusters":[{"id":"c1","name":"Focus","slug":"focus","synthesis_text":null,"note_count":3}]}
        """
        mockSession.stubbedData = json.data(using: .utf8)!
        let clusters = try await service.fetchClusters()
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].name, "Focus")
    }

    func testFetchClustersUsesAuthHeader() async throws {
        let json = """{"clusters":[]}"""
        mockSession.stubbedData = json.data(using: .utf8)!
        _ = try await service.fetchClusters()
        XCTAssertEqual(mockSession.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
    }

    func testFetchNotesForClusterDecodesResponse() async throws {
        let json = """
        {"notes":[{"id":42,"title":"My Note","created_at":"2026-01-01","word_count":10,"tags":null}]}
        """
        mockSession.stubbedData = json.data(using: .utf8)!
        let notes = try await service.fetchNotes(clusterId: "c1")
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].id, 42)
    }

    func testFetchNoteDetailDecodesResponse() async throws {
        let json = """
        {"note":{"id":1,"title":"T","content":"C","created_at":"2026-01-01","tags":null,"capture_type":"drafts","source_note_id":null,"essence":"short","concepts":"[]","primary_theme":"Focus"}}
        """
        mockSession.stubbedData = json.data(using: .utf8)!
        let note = try await service.fetchNote(id: 1)
        XCTAssertEqual(note.essence, "short")
        XCTAssertEqual(note.primary_theme, "Focus")
    }

    func testSubmitAnnotationPostsJSON() async throws {
        let json = """{"id":99,"status":"created"}"""
        mockSession.stubbedData = json.data(using: .utf8)!
        mockSession.stubbedResponse = HTTPURLResponse(
            url: URL(string: "http://selene.local:5678")!, statusCode: 201,
            httpVersion: nil, headerFields: nil
        )!
        let result = try await service.submitAnnotation(noteId: 1, text: "hello ink")
        XCTAssertEqual(result.id, 99)
        XCTAssertEqual(mockSession.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(mockSession.lastRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
}
```

**Step 2: Run tests — expect build failure (service not found yet)**

```bash
cd ~/SeleneMarkup && xcodegen generate && xcodebuild test -scheme SeleneMarkup -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' 2>&1 | grep -E "error:|FAILED|passed|failed"
```

Expected: build error — `AnnotationService` not found.

**Step 3: Create `AnnotationService.swift`**

```swift
import Foundation

enum AnnotationError: LocalizedError {
    case httpError(statusCode: Int)
    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "Server returned HTTP \(code)"
        }
    }
}

final class AnnotationService {
    private let config: AppConfig
    private let session: any HTTPSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(config: AppConfig = .shared, session: any HTTPSession = URLSession.shared) {
        self.config = config
        self.session = session
    }

    func fetchClusters() async throws -> [NoteCluster] {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("api/clusters"))
        attachAuth(to: &request)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(ClustersResponse.self, from: data).clusters
    }

    func fetchNotes(clusterId: String) async throws -> [ClusterNote] {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("api/clusters/\(clusterId)/notes"))
        attachAuth(to: &request)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(ClusterNotesResponse.self, from: data).notes
    }

    func fetchNote(id: Int) async throws -> NoteDetail {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("api/notes/\(id)"))
        attachAuth(to: &request)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(NoteDetailResponse.self, from: data).note
    }

    func submitAnnotation(noteId: Int, text: String) async throws -> AnnotationResponse {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("api/notes/\(noteId)/annotations"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        attachAuth(to: &request)
        request.httpBody = try encoder.encode(["text": text])
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(AnnotationResponse.self, from: data)
    }

    private func attachAuth(to request: inout URLRequest) {
        guard !config.bearerToken.isEmpty else { return }
        request.setValue("Bearer \(config.bearerToken)", forHTTPHeaderField: "Authorization")
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode >= 400 else { return }
        throw AnnotationError.httpError(statusCode: http.statusCode)
    }
}
```

**Step 4: Run tests — expect pass**

```bash
cd ~/SeleneMarkup && xcodegen generate && xcodebuild test -scheme SeleneMarkup -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' 2>&1 | grep -E "error:|FAILED|passed|failed"
```

Expected: all tests pass (including existing `WorksheetServiceTests`).

**Step 5: Commit**

```bash
cd ~/SeleneMarkup
git add Sources/SeleneMarkup/Services/AnnotationService.swift \
        Tests/SeleneMarkupTests/AnnotationServiceTests.swift
git commit -m "feat: AnnotationService — fetch clusters, notes, post annotations"
```

---

## Task 6: Views — `ClusterListView` and `NoteListView`

**Files:**
- Create: `~/SeleneMarkup/Sources/SeleneMarkup/Views/ClusterListView.swift`
- Create: `~/SeleneMarkup/Sources/SeleneMarkup/Views/NoteListView.swift`

**Step 1: Create `ClusterListView.swift`**

```swift
import SwiftUI

struct ClusterListView: View {
    @StateObject private var vm = ClusterListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Loading clusters…")
                } else if let error = vm.error {
                    ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
                } else {
                    List(vm.clusters) { cluster in
                        NavigationLink(destination: NoteListView(cluster: cluster)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cluster.name).font(.headline)
                                HStack {
                                    Text("\(cluster.note_count) notes").font(.caption).foregroundStyle(.secondary)
                                    if let summary = cluster.synthesis_text {
                                        Text("·").foregroundStyle(.secondary)
                                        Text(summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .refreshable { await vm.load() }
                }
            }
            .navigationTitle("Your Notes")
            .task { await vm.load() }
        }
    }
}

@MainActor
final class ClusterListViewModel: ObservableObject {
    @Published var clusters: [NoteCluster] = []
    @Published var isLoading = false
    @Published var error: String? = nil

    private let service = AnnotationService()

    func load() async {
        isLoading = true
        error = nil
        do {
            clusters = try await service.fetchClusters()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
```

**Step 2: Create `NoteListView.swift`**

```swift
import SwiftUI

struct NoteListView: View {
    let cluster: NoteCluster
    @StateObject private var vm: NoteListViewModel

    init(cluster: NoteCluster) {
        self.cluster = cluster
        _vm = StateObject(wrappedValue: NoteListViewModel(clusterId: cluster.id))
    }

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("Loading notes…")
            } else if let error = vm.error {
                ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
            } else if vm.notes.isEmpty {
                ContentUnavailableView("No notes in this cluster", systemImage: "note.text")
            } else {
                List(vm.notes) { note in
                    NavigationLink(destination: NoteCanvasView(noteId: note.id, noteTitle: note.title)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title).font(.headline).lineLimit(2)
                            Text(note.created_at.prefix(10))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(cluster.name)
        .task { await vm.load() }
    }
}

@MainActor
final class NoteListViewModel: ObservableObject {
    @Published var notes: [ClusterNote] = []
    @Published var isLoading = false
    @Published var error: String? = nil

    private let clusterId: String
    private let service = AnnotationService()

    init(clusterId: String) { self.clusterId = clusterId }

    func load() async {
        isLoading = true
        error = nil
        do {
            notes = try await service.fetchNotes(clusterId: clusterId)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
```

**Step 3: Build**

```bash
cd ~/SeleneMarkup && xcodegen generate && xcodebuild -scheme SeleneMarkup -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|Build succeeded|BUILD FAILED"
```

Expected: `Build succeeded`

**Step 4: Commit**

```bash
cd ~/SeleneMarkup
git add Sources/SeleneMarkup/Views/ClusterListView.swift \
        Sources/SeleneMarkup/Views/NoteListView.swift
git commit -m "feat: ClusterListView and NoteListView navigation"
```

---

## Task 7: View — `NoteMetaSheet`

The "back of card" peek panel. Shows Selene's processed metadata for a note.

**Files:**
- Create: `~/SeleneMarkup/Sources/SeleneMarkup/Views/NoteMetaSheet.swift`

**Step 1: Create the file**

```swift
import SwiftUI

struct NoteMetaSheet: View {
    let note: NoteDetail

    var concepts: [String] {
        guard let raw = note.concepts,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return decoded
    }

    var body: some View {
        NavigationStack {
            List {
                if let essence = note.essence {
                    Section("Essence") {
                        Text(essence).font(.body)
                    }
                }

                if let theme = note.primary_theme {
                    Section("Primary Theme") {
                        Text(theme)
                    }
                }

                if !concepts.isEmpty {
                    Section("Concepts") {
                        FlowLayout(concepts)
                    }
                }

                Section("Captured") {
                    Text(String(note.created_at.prefix(10)))
                        .foregroundStyle(.secondary)
                    Text(note.capture_type)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About This Note")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// Simple horizontal-wrapping tag layout
struct FlowLayout: View {
    let tags: [String]
    init(_ tags: [String]) { self.tags = tags }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }
}
```

**Step 2: Build**

```bash
cd ~/SeleneMarkup && xcodegen generate && xcodebuild -scheme SeleneMarkup -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|Build succeeded|BUILD FAILED"
```

Expected: `Build succeeded`

**Step 3: Commit**

```bash
cd ~/SeleneMarkup
git add Sources/SeleneMarkup/Views/NoteMetaSheet.swift
git commit -m "feat: NoteMetaSheet — back-of-card essence, theme, concepts"
```

---

## Task 8: View — `NoteCanvasView` (the main annotation surface)

The core view: note text at top, infinite PencilKit canvas below, scrolls together, "Send to Selene" button, peek sheet.

**Files:**
- Create: `~/SeleneMarkup/Sources/SeleneMarkup/Views/NoteCanvasView.swift`

**Step 1: Create the file**

```swift
import SwiftUI
import PencilKit

struct NoteCanvasView: View {
    let noteId: Int
    let noteTitle: String

    @StateObject private var vm: NoteCanvasViewModel
    @State private var drawing = PKDrawing()
    @State private var showMeta = false
    @State private var showOCRConfirm = false
    @State private var recognizedText = ""
    @State private var isSending = false
    @State private var sendResult: String? = nil

    private let handwriting = HandwritingService()

    init(noteId: Int, noteTitle: String) {
        self.noteId = noteId
        self.noteTitle = noteTitle
        _vm = StateObject(wrappedValue: NoteCanvasViewModel(noteId: noteId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // — Note text (read-only) —
                if let note = vm.note {
                    Text(note.content)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                } else if vm.isLoading {
                    ProgressView()
                        .padding()
                } else if let error = vm.error {
                    Text(error).foregroundStyle(.red).padding()
                }

                // — Infinite PencilKit canvas —
                CanvasView(drawing: $drawing)
                    .frame(minHeight: 600)
                    .background(Color(.systemBackground))
            }
        }
        .scrollBounceBehavior(.always)
        .navigationTitle(noteTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Back-of-card peek
                Button {
                    showMeta = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .disabled(vm.note == nil)

                // Send annotation to Selene
                Button {
                    Task { await recognizeAndConfirm() }
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Label("Send to Selene", systemImage: "arrow.up.circle")
                    }
                }
                .disabled(drawing.strokes.isEmpty || isSending)
            }
        }
        .sheet(isPresented: $showMeta) {
            if let note = vm.note {
                NoteMetaSheet(note: note)
                    .presentationDetents([.medium, .large])
            }
        }
        // OCR review before sending
        .alert("Send to Selene?", isPresented: $showOCRConfirm) {
            Button("Send") { Task { await sendAnnotation() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(recognizedText.isEmpty ? "No text recognized." : recognizedText)
        }
        .overlay(alignment: .bottom) {
            if let result = sendResult {
                Text(result)
                    .padding(12)
                    .background(Material.bar)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { sendResult = nil }
                        }
                    }
            }
        }
        .task { await vm.load() }
    }

    private func recognizeAndConfirm() async {
        guard !drawing.strokes.isEmpty else { return }
        let image = drawing.image(from: drawing.bounds.insetBy(dx: -20, dy: -20), scale: UIScreen.main.scale)
        do {
            recognizedText = try await handwriting.recognize(image)
        } catch {
            recognizedText = ""
        }
        showOCRConfirm = true
    }

    private func sendAnnotation() async {
        guard !recognizedText.isEmpty else { return }
        isSending = true
        do {
            _ = try await vm.service.submitAnnotation(noteId: noteId, text: recognizedText)
            drawing = PKDrawing()   // clear canvas after successful send
            withAnimation { sendResult = "Sent to Selene ✓" }
        } catch {
            withAnimation { sendResult = "Failed: \(error.localizedDescription)" }
        }
        isSending = false
    }
}

@MainActor
final class NoteCanvasViewModel: ObservableObject {
    @Published var note: NoteDetail? = nil
    @Published var isLoading = false
    @Published var error: String? = nil

    let service = AnnotationService()
    private let noteId: Int

    init(noteId: Int) { self.noteId = noteId }

    func load() async {
        guard note == nil else { return }   // don't reload on sheet dismiss
        isLoading = true
        error = nil
        do {
            note = try await service.fetchNote(id: noteId)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
```

**Step 2: Build**

```bash
cd ~/SeleneMarkup && xcodegen generate && xcodebuild -scheme SeleneMarkup -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|Build succeeded|BUILD FAILED"
```

Expected: `Build succeeded`

**Step 3: Commit**

```bash
cd ~/SeleneMarkup
git add Sources/SeleneMarkup/Views/NoteCanvasView.swift
git commit -m "feat: NoteCanvasView — note text + infinite canvas + OCR send loop"
```

---

## Task 9: Wire Up the Tab in `ContentView`

**Files:**
- Modify: `~/SeleneMarkup/Sources/SeleneMarkup/Views/ContentView.swift`

**Step 1: Replace ContentView with a TabView**

The current `ContentView` just shows `WorksheetView()`. Replace it with a two-tab layout:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            WorksheetView()
                .tabItem {
                    Label("Worksheets", systemImage: "pencil.and.list.clipboard")
                }

            ClusterListView()
                .tabItem {
                    Label("Notes", systemImage: "note.text")
                }
        }
    }
}

#Preview {
    ContentView()
}
```

**Step 2: Build**

```bash
cd ~/SeleneMarkup && xcodegen generate && xcodebuild -scheme SeleneMarkup -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|Build succeeded|BUILD FAILED"
```

Expected: `Build succeeded`

**Step 3: Commit**

```bash
cd ~/SeleneMarkup
git add Sources/SeleneMarkup/Views/ContentView.swift
git commit -m "feat: add Notes tab (ClusterListView) to ContentView TabView"
```

---

## Task 10: Settings — Add Selene Main Server URL

SeleneMarkup currently defaults to port 5679 (worksheets dev server). The annotation endpoints live on the main Selene server at port 5678. `AppConfig.shared` reads from the `selene_base_url` key — the user needs to be able to set the main server URL.

**Files:**
- Modify: `~/SeleneMarkup/Sources/SeleneMarkup/Models/AppConfig.swift`

The current `AppConfig.shared` reads one URL. We need to distinguish between the worksheet server and the Selene main server. Simplest approach: add a second `mainBaseURL` property that reads a different UserDefaults key (`selene_main_url`), defaulting to port 5678.

```swift
import Foundation

struct AppConfig {
    let baseURL: URL           // worksheet server (port 5679)
    let mainBaseURL: URL       // selene main server (port 5678)
    let bearerToken: String

    init(baseURL: URL, mainBaseURL: URL? = nil, bearerToken: String = "") {
        self.baseURL = baseURL
        self.mainBaseURL = mainBaseURL ?? baseURL
        self.bearerToken = bearerToken
    }

    static let shared: AppConfig = {
        let urlString = UserDefaults.standard.string(forKey: "selene_base_url")
            ?? "http://192.168.1.239:5679"
        let mainUrlString = UserDefaults.standard.string(forKey: "selene_main_url")
            ?? urlString.replacingOccurrences(of: ":5679", with: ":5678")
        let token = UserDefaults.standard.string(forKey: "selene_bearer_token") ?? ""
        return AppConfig(
            baseURL: URL(string: urlString)!,
            mainBaseURL: URL(string: mainUrlString)!,
            bearerToken: token
        )
    }()
}
```

Then update `AnnotationService` to use `config.mainBaseURL` instead of `config.baseURL`:

In `AnnotationService.swift`, change all `config.baseURL` references to `config.mainBaseURL`.

**Build and commit:**

```bash
cd ~/SeleneMarkup && xcodegen generate && xcodebuild -scheme SeleneMarkup -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|Build succeeded|BUILD FAILED"
```

```bash
git add Sources/SeleneMarkup/Models/AppConfig.swift \
        Sources/SeleneMarkup/Services/AnnotationService.swift
git commit -m "feat: AppConfig mainBaseURL for main Selene server (port 5678)"
```

---

## Task 11: Deploy and End-to-End Test

**Step 1: Deploy to iPad**

Connect iPad via USB. Run:

```bash
cd ~/SeleneMarkup && ./redeploy.sh
```

Expected: `Done. Tap SeleneMarkup on your iPad to launch.`

**Step 2: End-to-end walkthrough**

On the iPad:

1. Open SeleneMarkup → tap **Notes** tab
2. Verify cluster list loads (should show your topic clusters)
3. Tap a cluster → verify notes list loads
4. Tap a note → verify raw note text appears at top of canvas
5. Draw with Apple Pencil below the note text
6. Tap the **ⓘ** button → verify NoteMetaSheet shows essence/theme/concepts
7. Tap **Send to Selene** → OCR review alert appears → tap **Send**
8. Verify toast: "Sent to Selene ✓"
9. Verify canvas clears

**Step 3: Verify annotation in database**

```bash
sqlite3 ~/selene-data/selene.db "SELECT id, title, capture_type, source_note_id FROM raw_notes WHERE capture_type = 'annotation' ORDER BY id DESC LIMIT 3;"
```

Expected: rows with `capture_type = annotation` and a non-null `source_note_id`.

**Step 4: Verify pipeline picks it up**

```bash
# Run process-llm manually to process the new annotation
npx ts-node ~/selene/src/workflows/process-llm.ts
sqlite3 ~/selene-data/selene.db "SELECT r.title, p.primary_theme FROM raw_notes r JOIN processed_notes p ON p.raw_note_id = r.id WHERE r.capture_type = 'annotation' LIMIT 3;"
```

Expected: your annotation has a `primary_theme` (processed by LLM).

---

## Rollback

If anything breaks:

- Remove the `source_note_id` column: not possible in SQLite without recreating the table, but since the column is nullable and unused by existing queries, it is safe to leave. All existing code still works — `insertNote` only passes `source_note_id` when explicitly provided.
- Remove the notes routes: delete `src/routes/notes.ts` and the `server.register(notesRoutes)` line in `server.ts`. No data loss.
- Revert `ContentView.swift` to the single-view version to remove the tab.
