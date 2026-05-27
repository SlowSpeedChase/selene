# Selene Mobile Companion App — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an iPhone/iPad companion app that lets you browse Selene's Obsidian vault, annotate notes with Apple Pencil (PencilKit), and feed annotations back to the librarian — plus a home screen WidgetKit widget showing today's summary.

**Architecture:** The Selene Mac server grows 4 new REST endpoints (served from `src/routes/vault.ts`) that the iOS app calls over Tailscale. The app is a new `SeleneMobile/` directory at the repo root using Xcode + SwiftUI (iOS/iPadOS 17+). A bundled WidgetKit extension reads `/api/summary/latest`. Phase 0 ships the server + basic app; Phase 1 adds PencilKit; Phase 2 adds the Capture tab.

**Tech Stack:** TypeScript/Fastify (server additions), Swift/SwiftUI/PencilKit/Vision/WidgetKit (iOS app), XcodeGen (project generation), better-sqlite3 (annotations table), URLSession (networking)

---

## Context You Need

- **Vault location:** `~/selene-data/vault/` (symlinked — resolve via `config.vaultPath` in `src/lib/config.ts`)
- **Daily summaries:** markdown files at `<vault>/Selene/Daily/YYYY-MM-DD-summary.md`
- **Vault notes:** markdown files in `<vault>/Selene/Notes/`
- **Auth middleware:** `requireAuth` in `src/lib/auth.ts` — add as `preHandler` on every new protected route
- **Route pattern:** see `src/routes/agents.ts` for how a Fastify plugin is structured
- **Register routes:** add `server.register(vaultRoutes)` in `src/server.ts` alongside the existing agent/dashboard registers
- **Archived iOS app for reference:** `archive/shelved-2026-03-21/SeleneChat/SeleneMobile/` — do NOT copy code, just read for patterns
- **Existing icon assets:** `archive/shelved-2026-03-21/SeleneChat/SeleneChat.icon/` — copy to new app

---

## Phase 0: Server endpoints + App skeleton + Widget

### Task 1: Add `note_annotations` SQLite table

**Files:**
- Create: `src/lib/vault-db.ts`

**Step 1: Create the module with migration**

```typescript
import { db } from './db';

export interface NoteAnnotationRow {
  id: number;
  note_path: string;
  annotation_text: string;
  created_at: string;
  processed: number;
}

export function runVaultMigrations(): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS note_annotations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      note_path TEXT NOT NULL,
      annotation_text TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      processed INTEGER NOT NULL DEFAULT 0
    )
  `);
}

export function insertAnnotation(notePath: string, text: string): NoteAnnotationRow {
  const stmt = db.prepare(
    `INSERT INTO note_annotations (note_path, annotation_text) VALUES (?, ?)`
  );
  const result = stmt.run(notePath, text);
  return db.prepare('SELECT * FROM note_annotations WHERE id = ?')
    .get(result.lastInsertRowid) as NoteAnnotationRow;
}

export function getUnprocessedAnnotations(): NoteAnnotationRow[] {
  return db.prepare(
    `SELECT * FROM note_annotations WHERE processed = 0 ORDER BY created_at`
  ).all() as NoteAnnotationRow[];
}

export function markAnnotationProcessed(id: number): void {
  db.prepare('UPDATE note_annotations SET processed = 1 WHERE id = ?').run(id);
}
```

**Step 2: Call migration from server startup — modify `src/server.ts`**

Add near the top, after the existing imports:

```typescript
import { runVaultMigrations } from './lib/vault-db';
```

And call it before `server.register(agentRoutes)`:

```typescript
runVaultMigrations();
```

**Step 3: Verify the table is created**

```bash
npx ts-node -e "
import { runVaultMigrations } from './src/lib/vault-db';
runVaultMigrations();
import { db } from './src/lib/db';
console.log(db.prepare(\"SELECT name FROM sqlite_master WHERE type='table' AND name='note_annotations'\").get());
"
```

Expected output: `{ name: 'note_annotations' }`

**Step 4: Commit**

```bash
git add src/lib/vault-db.ts src/server.ts
git commit -m "feat: add note_annotations table + vault-db module"
```

---

### Task 2: Create `src/routes/vault.ts`

**Files:**
- Create: `src/routes/vault.ts`

This file exposes the 4 new API endpoints. The vault path comes from `config.vaultPath`.

**Step 1: Write the route module**

```typescript
import type { FastifyInstance } from 'fastify';
import { readdirSync, readFileSync, existsSync } from 'fs';
import { join, basename, relative } from 'path';
import { config } from '../lib/config';
import { requireAuth } from '../lib/auth';
import { insertAnnotation } from '../lib/vault-db';

const NOTES_DIR = join(config.vaultPath, 'Selene', 'Notes');
const DAILY_DIR = join(config.vaultPath, 'Selene', 'Daily');

function safeReadDir(dir: string): string[] {
  try {
    return readdirSync(dir).filter(f => f.endsWith('.md'));
  } catch {
    return [];
  }
}

export async function vaultRoutes(fastify: FastifyInstance): Promise<void> {

  // GET /api/summary/latest — most recent daily summary file
  fastify.get('/api/summary/latest', { preHandler: requireAuth }, async (_req, reply) => {
    const files = safeReadDir(DAILY_DIR).sort().reverse();
    if (files.length === 0) {
      reply.status(404);
      return { error: 'No summaries found' };
    }
    const filename = files[0];
    const content = readFileSync(join(DAILY_DIR, filename), 'utf-8');
    const date = filename.replace('-summary.md', '');
    // Extract first non-empty non-header line as headline
    const headline = content.split('\n')
      .map(l => l.trim())
      .find(l => l.length > 0 && !l.startsWith('#')) ?? '';
    return { date, content, headline };
  });

  // GET /api/vault/notes — list all notes
  fastify.get('/api/vault/notes', { preHandler: requireAuth }, async () => {
    const files = safeReadDir(NOTES_DIR);
    const notes = files.map(filename => {
      const title = filename.replace(/\.md$/, '').replace(/-/g, ' ');
      return {
        path: filename,
        title,
        filename,
      };
    });
    return { notes };
  });

  // GET /api/vault/notes/:filename — single note content
  fastify.get<{ Params: { filename: string } }>(
    '/api/vault/notes/:filename',
    { preHandler: requireAuth },
    async (request, reply) => {
      const { filename } = request.params;
      // Security: prevent path traversal
      if (filename.includes('/') || filename.includes('..') || !filename.endsWith('.md')) {
        reply.status(400);
        return { error: 'Invalid filename' };
      }
      const filePath = join(NOTES_DIR, filename);
      if (!existsSync(filePath)) {
        reply.status(404);
        return { error: 'Note not found' };
      }
      const content = readFileSync(filePath, 'utf-8');
      const title = filename.replace(/\.md$/, '').replace(/-/g, ' ');
      return { filename, title, content };
    }
  );

  // POST /api/vault/notes/:filename/annotations — submit annotation text
  fastify.post<{ Params: { filename: string }; Body: { text: string } }>(
    '/api/vault/notes/:filename/annotations',
    { preHandler: requireAuth },
    async (request, reply) => {
      const { filename } = request.params;
      const { text } = request.body;
      if (!text || text.trim().length === 0) {
        reply.status(400);
        return { error: 'Annotation text is required' };
      }
      if (filename.includes('/') || filename.includes('..') || !filename.endsWith('.md')) {
        reply.status(400);
        return { error: 'Invalid filename' };
      }
      const row = insertAnnotation(filename, text.trim());
      return { ok: true, id: row.id };
    }
  );
}
```

**Step 2: Register in `src/server.ts`**

Add import:
```typescript
import { vaultRoutes } from './routes/vault';
```

Add after `server.register(dashboardRoutes)`:
```typescript
server.register(vaultRoutes);
```

**Step 3: Restart server and smoke-test the endpoints**

```bash
# Restart the server
launchctl kickstart -k gui/$(id -u)/com.selene.server

# Wait 2 seconds, then test
curl -s http://localhost:5678/api/summary/latest \
  -H "Authorization: Bearer $(grep API_TOKEN .env | cut -d= -f2)" | head -c 200

curl -s http://localhost:5678/api/vault/notes \
  -H "Authorization: Bearer $(grep API_TOKEN .env | cut -d= -f2)" | python3 -m json.tool | head -20
```

Expected: JSON response with `date`, `content`, `headline` for summary; `notes` array for notes list.

**Step 4: Commit**

```bash
git add src/routes/vault.ts src/server.ts
git commit -m "feat: add vault API routes (summary, notes list, note detail, annotations)"
```

---

### Task 3: Test `POST /annotations` end-to-end

**Step 1: Post a test annotation**

```bash
# Get any note filename from the list first
FILENAME=$(curl -s http://localhost:5678/api/vault/notes \
  -H "Authorization: Bearer $(grep API_TOKEN .env | cut -d= -f2)" \
  | python3 -c "import sys,json; notes=json.load(sys.stdin)['notes']; print(notes[0]['filename'] if notes else 'none')")

echo "Using note: $FILENAME"

curl -s -X POST "http://localhost:5678/api/vault/notes/$FILENAME/annotations" \
  -H "Authorization: Bearer $(grep API_TOKEN .env | cut -d= -f2)" \
  -H "Content-Type: application/json" \
  -d '{"text": "Test annotation from plan"}'
```

Expected: `{"ok":true,"id":1}`

**Step 2: Verify in database**

```bash
sqlite3 data/selene.db "SELECT * FROM note_annotations;"
```

Expected: one row with the test annotation.

**Step 3: Clean up**

```bash
sqlite3 data/selene.db "DELETE FROM note_annotations WHERE annotation_text = 'Test annotation from plan';"
```

---

### Task 4: Create the SeleneMobile Xcode project

**Prerequisite:** Xcode 16 must be installed. You'll use XcodeGen.

**Step 1: Install XcodeGen if needed**

```bash
which xcodegen || brew install xcodegen
```

**Step 2: Create directory structure**

```bash
mkdir -p SeleneMobile/Sources/SeleneMobile/App
mkdir -p SeleneMobile/Sources/SeleneMobile/Views
mkdir -p SeleneMobile/Sources/SeleneMobile/Services
mkdir -p SeleneMobile/Sources/SeleneMobile/Models
mkdir -p SeleneMobile/Sources/SeleneMobile/Resources/Assets.xcassets/AppIcon.appiconset
mkdir -p SeleneMobile/Sources/SeleneWidget
mkdir -p SeleneMobile/Tests/SeleneMobileTests
```

**Step 3: Copy the original icon assets**

```bash
# Copy iOS 1024x1024 icon
cp archive/shelved-2026-03-21/SeleneChat/SeleneChat.icon/SeleneChat-iOS-Default-1024x1024@1x.png \
   SeleneMobile/Sources/SeleneMobile/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
```

Create the Contents.json for the app icon:

```bash
cat > SeleneMobile/Sources/SeleneMobile/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json << 'EOF'
{
  "images": [
    {
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024",
      "filename": "icon-1024.png"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
EOF
```

Also create Contents.json for the xcassets root:

```bash
cat > SeleneMobile/Sources/SeleneMobile/Resources/Assets.xcassets/Contents.json << 'EOF'
{
  "info": {
    "author": "xcode",
    "version": 1
  }
}
EOF
```

**Step 4: Create `SeleneMobile/project.yml`**

```yaml
name: SeleneMobile
options:
  bundleIdPrefix: com.selene
  deploymentTarget:
    iOS: "17.0"
  xcodeVersion: "16.0"

targets:
  SeleneMobile:
    type: application
    platform: iOS
    sources:
      - path: Sources/SeleneMobile
    resources:
      - path: Sources/SeleneMobile/Resources
    info:
      path: Sources/SeleneMobile/App/Info.plist
      properties:
        CFBundleDisplayName: Selene
        NSMicrophoneUsageDescription: "Selene uses the microphone for voice note capture."
        NSSpeechRecognitionUsageDescription: "Selene uses speech recognition to convert voice to text."
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
          NSAllowsArbitraryLoads: true
        UILaunchScreen: {}
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.chaseeasterling.selene-mobile
        PRODUCT_NAME: SeleneMobile
        SWIFT_VERSION: "5.9"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    dependencies:
      - target: SeleneWidget

  SeleneWidget:
    type: app-extension
    platform: iOS
    sources:
      - path: Sources/SeleneWidget
    info:
      path: Sources/SeleneWidget/Info.plist
      properties:
        CFBundleDisplayName: SeleneWidget
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.chaseeasterling.selene-mobile.widget
        PRODUCT_NAME: SeleneWidget
        SWIFT_VERSION: "5.9"

  SeleneMobileTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests/SeleneMobileTests
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.chaseeasterling.selene-mobile-tests
    dependencies:
      - target: SeleneMobile
```

**Step 5: Generate the Xcode project**

```bash
cd SeleneMobile && xcodegen generate
```

Expected: `SeleneMobile.xcodeproj` created with no errors.

**Step 6: Commit**

```bash
cd ..
git add SeleneMobile/
git commit -m "feat: scaffold SeleneMobile Xcode project with icon + WidgetKit target"
```

---

### Task 5: Build the API client and data models

**Files:**
- Create: `SeleneMobile/Sources/SeleneMobile/Services/APIClient.swift`
- Create: `SeleneMobile/Sources/SeleneMobile/Models/VaultNote.swift`
- Create: `SeleneMobile/Sources/SeleneMobile/Models/DailySummary.swift`

**Step 1: Create `VaultNote.swift`**

```swift
import Foundation

struct VaultNote: Identifiable, Codable, Hashable {
    var id: String { filename }
    let filename: String
    let title: String
    let content: String?

    enum CodingKeys: String, CodingKey {
        case filename, title, content
    }
}

struct VaultNotesResponse: Codable {
    let notes: [VaultNote]
}
```

**Step 2: Create `DailySummary.swift`**

```swift
import Foundation

struct DailySummary: Codable {
    let date: String
    let content: String
    let headline: String
}
```

**Step 3: Create `APIClient.swift`**

```swift
import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case httpError(Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Server URL not configured. Set it in Settings."
        case .httpError(let code): return "Server returned HTTP \(code)"
        case .decodingError(let e): return "Parsing error: \(e.localizedDescription)"
        }
    }
}

@MainActor
class APIClient: ObservableObject {
    static let shared = APIClient()

    private var baseURL: String { UserDefaults.standard.string(forKey: "serverURL") ?? "" }
    private var token: String { UserDefaults.standard.string(forKey: "authToken") ?? "" }

    private func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        guard !baseURL.isEmpty else { throw APIError.notConfigured }
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.notConfigured }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw APIError.httpError(status) }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func latestSummary() async throws -> DailySummary {
        try await request("/api/summary/latest")
    }

    func listNotes() async throws -> [VaultNote] {
        let response: VaultNotesResponse = try await request("/api/vault/notes")
        return response.notes
    }

    func noteDetail(filename: String) async throws -> VaultNote {
        try await request("/api/vault/notes/\(filename)")
    }

    func submitAnnotation(filename: String, text: String) async throws {
        let body = try JSONEncoder().encode(["text": text])
        struct OkResponse: Codable { let ok: Bool }
        let _: OkResponse = try await request(
            "/api/vault/notes/\(filename)/annotations",
            method: "POST",
            body: body
        )
    }

    func testConnection() async throws -> Bool {
        struct HealthResponse: Codable { let status: String }
        let response: HealthResponse = try await request("/health")
        return response.status == "ok"
    }
}
```

**Step 4: Build in Xcode to verify no compilation errors**

Open `SeleneMobile/SeleneMobile.xcodeproj` in Xcode. Select the `SeleneMobile` target, choose an iPhone 17 simulator, hit **⌘B** (Build).

Expected: Build succeeds with 0 errors.

**Step 5: Commit**

```bash
git add SeleneMobile/Sources/SeleneMobile/Services/ SeleneMobile/Sources/SeleneMobile/Models/
git commit -m "feat: add APIClient + VaultNote + DailySummary models"
```

---

### Task 6: Build the Settings view + app entry point

**Files:**
- Create: `SeleneMobile/Sources/SeleneMobile/App/SeleneMobileApp.swift`
- Create: `SeleneMobile/Sources/SeleneMobile/App/Info.plist` (placeholder — XcodeGen generates it)
- Create: `SeleneMobile/Sources/SeleneMobile/Views/SettingsView.swift`
- Create: `SeleneMobile/Sources/SeleneMobile/Views/RootTabView.swift`

**Step 1: Create `SeleneMobileApp.swift`**

```swift
import SwiftUI

@main
struct SeleneMobileApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
```

**Step 2: Create `RootTabView.swift`**

```swift
import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            ExploreView()
                .tabItem {
                    Label("Explore", systemImage: "book.pages")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
```

**Step 3: Create `SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    @State private var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    @State private var authToken = UserDefaults.standard.string(forKey: "authToken") ?? ""
    @State private var connectionStatus: String? = nil
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Selene Server (Tailscale)") {
                    TextField("https://100.x.x.x:5678", text: $serverURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("Auth Token", text: $authToken)
                }
                Section {
                    Button(isTesting ? "Testing…" : "Test Connection") {
                        testConnection()
                    }
                    .disabled(isTesting || serverURL.isEmpty)
                    if let status = connectionStatus {
                        Text(status)
                            .foregroundStyle(status.hasPrefix("✓") ? .green : .red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Settings")
            .onChange(of: serverURL) { _, v in UserDefaults.standard.set(v, forKey: "serverURL") }
            .onChange(of: authToken) { _, v in UserDefaults.standard.set(v, forKey: "authToken") }
        }
    }

    private func testConnection() {
        isTesting = true
        connectionStatus = nil
        Task {
            do {
                _ = try await APIClient.shared.testConnection()
                connectionStatus = "✓ Connected"
            } catch {
                connectionStatus = "✗ \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
```

**Step 4: Create a placeholder `ExploreView.swift`** (temporary — filled in next task)

```swift
import SwiftUI

struct ExploreView: View {
    var body: some View {
        NavigationStack {
            Text("Loading notes…")
                .navigationTitle("Explore")
        }
    }
}
```

**Step 5: Build and run in simulator**

In Xcode, run on iPhone 17 simulator. You should see a two-tab app with "Explore" and "Settings". Settings form should save URL and token to UserDefaults.

**Step 6: Commit**

```bash
git add SeleneMobile/Sources/SeleneMobile/App/ SeleneMobile/Sources/SeleneMobile/Views/
git commit -m "feat: add app entry point, RootTabView, SettingsView"
```

---

### Task 7: Build the Explore tab (note list)

**Files:**
- Modify: `SeleneMobile/Sources/SeleneMobile/Views/ExploreView.swift`
- Create: `SeleneMobile/Sources/SeleneMobile/Views/NoteDetailView.swift`

**Step 1: Replace `ExploreView.swift` with full implementation**

```swift
import SwiftUI

struct ExploreView: View {
    @State private var notes: [VaultNote] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var searchText = ""

    var filtered: [VaultNote] {
        if searchText.isEmpty { return notes }
        return notes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading notes…")
                } else if let error = errorMessage {
                    ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
                } else if notes.isEmpty {
                    ContentUnavailableView("No notes", systemImage: "doc.text")
                } else {
                    List(filtered) { note in
                        NavigationLink(value: note) {
                            Text(note.title)
                                .font(.body)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search notes")
                }
            }
            .navigationTitle("Explore")
            .navigationDestination(for: VaultNote.self) { note in
                NoteDetailView(note: note)
            }
            .refreshable { await loadNotes() }
            .task { await loadNotes() }
        }
    }

    private func loadNotes() async {
        isLoading = true
        errorMessage = nil
        do {
            notes = try await APIClient.shared.listNotes()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
```

**Step 2: Create `NoteDetailView.swift`**

```swift
import SwiftUI

struct NoteDetailView: View {
    let note: VaultNote
    @State private var detail: VaultNote? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
            } else if let error = errorMessage {
                ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
            } else if let content = detail?.content {
                ScrollView {
                    Text(content)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                detail = try await APIClient.shared.noteDetail(filename: note.filename)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
```

> **Note:** This is plain text rendering. Markdown rendering with `Text(content, format: .markdown)` or `AttributedString` requires converting the markdown — a future polish step. For now, plain text is sufficient to prove the pipeline works.

**Step 3: Build and run on simulator**

Configure a real server URL in Settings (your Tailscale IP or localhost if on the same Mac). Tap Explore — notes list should populate. Tap a note — detail should render.

**Step 4: Commit**

```bash
git add SeleneMobile/Sources/SeleneMobile/Views/ExploreView.swift \
        SeleneMobile/Sources/SeleneMobile/Views/NoteDetailView.swift
git commit -m "feat: Explore tab — note list + detail view via vault API"
```

---

### Task 8: Build the WidgetKit extension

**Files:**
- Create: `SeleneMobile/Sources/SeleneWidget/SeleneWidget.swift`
- Create: `SeleneMobile/Sources/SeleneWidget/Info.plist` (XcodeGen generates this)

**Step 1: Create `SeleneWidget.swift`**

```swift
import WidgetKit
import SwiftUI

struct SummaryEntry: TimelineEntry {
    let date: Date
    let headline: String
    let summaryDate: String
}

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: .now, headline: "Your Selene summary will appear here.", summaryDate: "")
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        Task {
            let entry = await fetchEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        Task {
            let entry = await fetchEntry()
            // Refresh every 30 minutes
            let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
            let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
            completion(timeline)
        }
    }

    private func fetchEntry() async -> SummaryEntry {
        do {
            let summary = try await APIClient.shared.latestSummary()
            return SummaryEntry(date: .now, headline: summary.headline, summaryDate: summary.date)
        } catch {
            return SummaryEntry(date: .now, headline: "Connect to Selene in Settings.", summaryDate: "")
        }
    }
}

struct SeleneWidgetEntryView: View {
    var entry: SummaryEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "moon.stars")
                    .foregroundStyle(.secondary)
                Text("Selene")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if !entry.summaryDate.isEmpty {
                    Text(entry.summaryDate)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Text(entry.headline)
                .font(family == .systemSmall ? .caption : .subheadline)
                .lineLimit(family == .systemSmall ? 3 : 5)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct SeleneWidget: Widget {
    let kind = "SeleneWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SummaryProvider()) { entry in
            SeleneWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Selene Today")
        .description("Shows your latest Selene daily summary.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
```

> **Important:** `APIClient.swift` must be in both the `SeleneMobile` and `SeleneWidget` targets. Update `project.yml` to add `Services/APIClient.swift` and `Models/` to the `SeleneWidget` sources, OR extract shared code into a Swift package. The simplest approach: duplicate the files in `Sources/SeleneWidget/Shared/` for now.

**Step 2: Add shared files to widget target in `project.yml`**

Update the `SeleneWidget` target in `project.yml`:

```yaml
  SeleneWidget:
    type: app-extension
    platform: iOS
    sources:
      - path: Sources/SeleneWidget
      - path: Sources/SeleneMobile/Services/APIClient.swift
      - path: Sources/SeleneMobile/Models/DailySummary.swift
      - path: Sources/SeleneMobile/Models/VaultNote.swift
```

**Step 3: Re-generate project**

```bash
cd SeleneMobile && xcodegen generate
```

**Step 4: Build in Xcode — select SeleneWidget target**

⌘B with SeleneWidget selected. Should compile cleanly.

**Step 5: Add widget to simulator home screen**

Run the app on a simulator, long-press the home screen, tap **+**, search for "Selene", and add the widget.

**Step 6: Commit**

```bash
git add SeleneMobile/Sources/SeleneWidget/ SeleneMobile/project.yml
git commit -m "feat: SeleneWidget — home screen summary widget (small + medium)"
```

---

## Phase 1: PencilKit Annotation

### Task 9: Add PencilKit annotation layer to NoteDetailView

**Files:**
- Modify: `SeleneMobile/Sources/SeleneMobile/Views/NoteDetailView.swift`
- Create: `SeleneMobile/Sources/SeleneMobile/Views/AnnotationCanvasView.swift`

**Step 1: Create `AnnotationCanvasView.swift`** (UIKit wrapper for PKCanvasView)

```swift
import SwiftUI
import PencilKit

struct AnnotationCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly
        canvas.delegate = context.coordinator
        // Show the PencilKit toolbar
        let toolPicker = PKToolPicker()
        toolPicker.setVisible(true, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        canvas.becomeFirstResponder()
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: AnnotationCanvasView
        init(_ parent: AnnotationCanvasView) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
```

**Step 2: Update `NoteDetailView.swift` to include the annotation layer**

Replace the detail view body with:

```swift
import SwiftUI
import PencilKit

struct NoteDetailView: View {
    let note: VaultNote
    @State private var detail: VaultNote? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var isAnnotating = false
    @State private var drawing = PKDrawing()
    @State private var isSubmitting = false
    @State private var submitMessage: String? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            if isLoading {
                ProgressView("Loading…")
            } else if let error = errorMessage {
                ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
            } else if let content = detail?.content {
                ScrollView {
                    Text(content)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if isAnnotating {
                    AnnotationCanvasView(drawing: $drawing)
                        .ignoresSafeArea()
                }
            }
            if let msg = submitMessage {
                Text(msg)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isAnnotating {
                    Button("Send to Selene") { submitAnnotation() }
                        .disabled(isSubmitting || drawing.strokes.isEmpty)
                } else {
                    Button("Annotate") { isAnnotating = true }
                }
            }
            if isAnnotating {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isAnnotating = false
                        drawing = PKDrawing()
                    }
                }
            }
        }
        .task {
            do {
                detail = try await APIClient.shared.noteDetail(filename: note.filename)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func submitAnnotation() {
        isSubmitting = true
        Task {
            let text = await ocrDrawing(drawing)
            guard !text.isEmpty else {
                submitMessage = "Could not read handwriting — try writing larger."
                isSubmitting = false
                return
            }
            do {
                try await APIClient.shared.submitAnnotation(filename: note.filename, text: text)
                submitMessage = "✓ Sent to Selene"
                isAnnotating = false
                drawing = PKDrawing()
            } catch {
                submitMessage = "✗ \(error.localizedDescription)"
            }
            isSubmitting = false
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            submitMessage = nil
        }
    }
}
```

**Step 3: Add Vision OCR helper**

Create `SeleneMobile/Sources/SeleneMobile/Services/OCRService.swift`:

```swift
import Vision
import PencilKit
import UIKit

@MainActor
func ocrDrawing(_ drawing: PKDrawing) async -> String {
    // Render the PKDrawing to a UIImage at screen scale
    let scale = UIScreen.main.scale
    let bounds = drawing.bounds.insetBy(dx: -20, dy: -20)
    guard bounds.width > 0, bounds.height > 0 else { return "" }
    let image = drawing.image(from: bounds, scale: scale)

    return await withCheckedContinuation { continuation in
        guard let cgImage = image.cgImage else {
            continuation.resume(returning: "")
            return
        }
        let request = VNRecognizeTextRequest { req, _ in
            let text = (req.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ") ?? ""
            continuation.resume(returning: text)
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }
}
```

**Step 4: Build and test on a physical iPad**

PencilKit drawing policy `.pencilOnly` only activates with a real Apple Pencil. To test on simulator, temporarily change `drawingPolicy` to `.anyInput`.

Open a note, tap "Annotate", draw something, tap "Send to Selene". Check the server:

```bash
sqlite3 data/selene.db "SELECT * FROM note_annotations ORDER BY id DESC LIMIT 3;"
```

Expected: your handwritten text, OCR'd, stored as a row.

**Step 5: Commit**

```bash
git add SeleneMobile/Sources/SeleneMobile/Views/NoteDetailView.swift \
        SeleneMobile/Sources/SeleneMobile/Views/AnnotationCanvasView.swift \
        SeleneMobile/Sources/SeleneMobile/Services/OCRService.swift
git commit -m "feat: PencilKit annotation layer + Vision OCR → submit to vault API"
```

---

### Task 10: Wire annotations into the librarian (export-obsidian)

**Files:**
- Modify: `src/workflows/export-obsidian.ts`
- Modify: `src/lib/vault-db.ts`

**Step 1: Export `getAnnotationsForNote` from vault-db.ts**

Add to `src/lib/vault-db.ts`:

```typescript
export function getAnnotationsForNote(notePath: string): NoteAnnotationRow[] {
  return db.prepare(
    `SELECT * FROM note_annotations WHERE note_path = ? AND processed = 0 ORDER BY created_at`
  ).all(notePath) as NoteAnnotationRow[];
}
```

**Step 2: Find where export-obsidian builds the LLM prompt for a note**

```bash
grep -n "prompt\|PROMPT\|essence\|generate" src/workflows/export-obsidian.ts | head -20
```

Identify the function that constructs the LLM prompt for a note (look for where `generate()` is called with note content).

**Step 3: Inject annotation text into the note prompt**

In `export-obsidian.ts`, find where it calls `generate()` for individual notes. Import and call `getAnnotationsForNote`:

```typescript
import { getAnnotationsForNote, markAnnotationProcessed } from '../lib/vault-db';
```

Before calling `generate()` for a note, check for annotations:

```typescript
const annotations = getAnnotationsForNote(note.filename ?? '');
const annotationBlock = annotations.length > 0
  ? `\n\nUser annotations on this note:\n${annotations.map(a => `- ${a.annotation_text}`).join('\n')}\n\nPlease incorporate these insights when curating this note.`
  : '';

// Pass annotationBlock into the prompt string (append to content variable before generate())
```

After a successful export run for that note, mark annotations processed:

```typescript
annotations.forEach(a => markAnnotationProcessed(a.id));
```

**Step 4: Verify annotation round-trip**

```bash
# Add a test annotation
curl -s -X POST "http://localhost:5678/api/vault/notes/$(ls ~/selene-data/vault/Selene/Notes/ | head -1)/annotations" \
  -H "Authorization: Bearer $(grep API_TOKEN .env | cut -d= -f2)" \
  -H "Content-Type: application/json" \
  -d '{"text": "This connects to my urbanism research"}'

# Trigger export
npx ts-node src/workflows/export-obsidian.ts

# Verify annotation was processed
sqlite3 data/selene.db "SELECT id, processed FROM note_annotations ORDER BY id DESC LIMIT 3;"
```

Expected: `processed = 1` for the test annotation.

**Step 5: Commit**

```bash
git add src/workflows/export-obsidian.ts src/lib/vault-db.ts
git commit -m "feat: librarian reads note_annotations on export, marks processed"
```

---

## Phase 2: Capture Tab

### Task 11: Build the Capture tab

**Files:**
- Create: `SeleneMobile/Sources/SeleneMobile/Views/CaptureView.swift`
- Modify: `SeleneMobile/Sources/SeleneMobile/Views/RootTabView.swift`

**Step 1: Create `CaptureView.swift`**

```swift
import SwiftUI
import Speech
import AVFoundation

struct CaptureView: View {
    @State private var title = ""
    @State private var content = ""
    @State private var isSubmitting = false
    @State private var submitResult: String? = nil
    @State private var isRecording = false
    private let speechRecognizer = SFSpeechRecognizer(locale: .current)
    @State private var recognitionTask: SFSpeechRecognitionTask? = nil
    @State private var audioEngine = AVAudioEngine()

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("What's this about?", text: $title)
                }
                Section("Note") {
                    TextEditor(text: $content)
                        .frame(minHeight: 120)
                    HStack {
                        Spacer()
                        Button {
                            isRecording ? stopRecording() : startRecording()
                        } label: {
                            Label(isRecording ? "Stop" : "Dictate", systemImage: isRecording ? "stop.circle.fill" : "mic")
                                .foregroundStyle(isRecording ? .red : .accentColor)
                        }
                    }
                }
                if let result = submitResult {
                    Section {
                        Text(result)
                            .foregroundStyle(result.hasPrefix("✓") ? .green : .red)
                    }
                }
            }
            .navigationTitle("Capture")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send") { send() }
                        .disabled(title.isEmpty || content.isEmpty || isSubmitting)
                }
            }
        }
    }

    private func send() {
        isSubmitting = true
        Task {
            do {
                struct IngestBody: Encodable { let title: String; let content: String }
                let body = try JSONEncoder().encode(IngestBody(title: title, content: content))
                struct WebhookResponse: Decodable { let status: String; let id: Int? }
                let serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
                let token = UserDefaults.standard.string(forKey: "authToken") ?? ""
                guard let url = URL(string: "\(serverURL)/webhook/api/drafts") else { return }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = body
                let (data, _) = try await URLSession.shared.data(for: req)
                let response = try JSONDecoder().decode(WebhookResponse.self, from: data)
                submitResult = "✓ Saved (id: \(response.id ?? 0))"
                title = ""
                content = ""
            } catch {
                submitResult = "✗ \(error.localizedDescription)"
            }
            isSubmitting = false
        }
    }

    private func startRecording() {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { return }
            DispatchQueue.main.async {
                let inputNode = audioEngine.inputNode
                let request = SFSpeechAudioBufferRecognitionRequest()
                recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
                    if let result { content = result.bestTranscription.formattedString }
                }
                let format = inputNode.outputFormat(forBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                    request.append(buffer)
                }
                try? audioEngine.start()
                isRecording = true
            }
        }
    }

    private func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.finish()
        recognitionTask = nil
        isRecording = false
    }
}
```

**Step 2: Add Capture tab to `RootTabView.swift`**

```swift
CaptureView()
    .tabItem {
        Label("Capture", systemImage: "pencil.and.outline")
    }
```

**Step 3: Build and test**

Run on simulator. Type a title and note, tap Send. Verify in server logs and database:

```bash
sqlite3 data/selene.db "SELECT id, title, created_at FROM raw_notes ORDER BY id DESC LIMIT 3;"
```

**Step 4: Commit**

```bash
git add SeleneMobile/Sources/SeleneMobile/Views/CaptureView.swift \
        SeleneMobile/Sources/SeleneMobile/Views/RootTabView.swift
git commit -m "feat: Capture tab — text + voice dictation → webhook"
```

---

## Wrap-Up

### Final checklist

- [ ] `GET /api/summary/latest` returns headline + content
- [ ] `GET /api/vault/notes` lists all vault notes
- [ ] `GET /api/vault/notes/:filename` serves note content
- [ ] `POST /api/vault/notes/:filename/annotations` stores annotation, returns `{ok: true}`
- [ ] Note list renders in Explore tab on simulator
- [ ] Note detail renders on tap
- [ ] Widget shows today's summary on home screen (small + medium)
- [ ] Annotate button on note detail shows PencilKit canvas
- [ ] Drawing + "Send to Selene" produces OCR'd text in `note_annotations` table
- [ ] After export-obsidian runs, annotation row is marked `processed = 1`
- [ ] Capture tab sends note to webhook, appears in `raw_notes`

### User guide

After Phase 0 is complete, create `docs/guides/features/selene-mobile.md` using `docs/guides/features/_TEMPLATE.md`. Add link to `docs/USER-EXPERIENCE.md`.

---

## Notes for Implementer

- **Xcode is required** for this work. All Swift compilation happens in Xcode, not `ts-node`.
- **Physical iPad required** for testing PencilKit with Apple Pencil. Simulator can test with `anyInput` policy.
- **Tailscale must be running** on both Mac and iPhone/iPad for real-device testing.
- **XcodeGen** is a code generator — run `xcodegen generate` from `SeleneMobile/` any time `project.yml` changes.
- The `project.yml` in this plan is a starting point — Xcode may need minor adjustments for signing (set your Apple ID in Xcode → Signing & Capabilities).
