# Siri Conversational AI — Ask Selene About Your Notes

**Status:** Vision
**Created:** 2026-06-17
**Updated:** 2026-06-17
**Topic:** siri, app-intents, foundation-models, conversational-ai, rag, seleneapp, swift

---

## Problem

Selene captures, processes, and *surfaces* notes — but there is no way to **ask it
questions**. "What was I thinking about the dev showcase?" / "What did I note about
sleep and focus?" / "Remind me what my plan for the iPad app was" have no answer
surface today.

The old chat surface (`SeleneChat`, a standalone macOS app) was **archived in the
2026-03-21 simplification** along with the thread system it depended on. The existing
SeleneApp iOS 27 design ([2026-06-14-seleneapp-ios27-siri-design.md](2026-06-14-seleneapp-ios27-siri-design.md))
gives Siri two narrow surfaces:

- **Tier 1 — navigation:** "Show my wants in Selene" opens the app at a screen.
- **Tier 2 — inline surfacing:** "What's today's Selene gift?" reads back a *fixed*
  query (the gift, the wants list).

Neither answers **open-ended conversational questions** over the whole corpus. The
user wants exactly that, voice-first: *"Hey Siri, ask Selene …"* → a spoken, grounded
answer drawn from their own notes, answered **on-device**.

This design fills that gap. It is the conversational generalization of Tier 2 and the
concrete execution of **slice D** (Siri / App Intents) from the Foundation Models slice
inventory ([2026-02-14-context-blocks-apple-intelligence-design.md](2026-02-14-context-blocks-apple-intelligence-design.md)).

---

## Solution

One App Intent, `AskSeleneIntent(question:)`, is the Siri surface. Inside it runs an
**on-device Foundation Models `LanguageModelSession`** equipped with Selene-specific
**FM `Tool`s** that retrieve from the notes database. The model calls those tools to
gather evidence, composes a grounded answer, and the intent returns it as **Siri
dialog** (spoken) plus an optional snippet view with deep links back into the app.

The **same engine** backs an in-app chat screen, so the feature is fully testable
without Siri and works as a normal "chat with my notes" screen too.

This is **not** a generic note search (Apple Notes + Spotlight does that). The moat is
that answers are grounded in the user's **own curated taxonomy, wants lifecycle, and
attention graph** — Selene's ADHD-specific layer — which Apple's generic personal
context cannot see.

### Architectural correction (load-bearing)

The 2026-06-14 doc frames Tier 2 as *"Siri can answer queries inline … using
multi-step tool calling inside a `LanguageModelSession`; the LM calls App Intents as
tools."* That is **backwards** in the current frameworks:

> **Foundation Models' `Tool` protocol is for *in-app* tool calling and runs
> *parallel* to App Intents. Foundation Models has no direct Siri integration.**
> (Verified against WWDC 2026 Foundation Models guidance, June 2026.)

So the bridge is the **inverse**: **Siri → an App Intent (`AskSeleneIntent`) that
*hosts* a `LanguageModelSession` + FM `Tool`s → returns a spoken dialog result.** App
Intents are the Siri surface; FM Tools are how the model reaches the database from
*inside* that intent. This doc adopts the corrected topology; the 2026-06-14 Tier 2
extensions (`SurfaceGiftExtension`, `SurfaceWantExtension`) become **two tools of this
general engine** rather than separate Siri surfaces.

---

## Design

### Components

**1. Siri surface — `AskSeleneIntent`**

```
AskSeleneIntent: AppIntent
  @Parameter question: String
  perform() async -> some IntentResult & ProvidesDialog & ShowsSnippetView
```

- Returns `ProvidesDialog` (Siri speaks the answer) + an optional `SnippetView`
  listing the cited notes with deep links (`selene://note/<source_uuid>`).
- Registered through `AppShortcutsProvider` with compile-time phrases:
  "Ask Selene", "Ask Selene about …", "Ask Selene what I noted about …".
- On OS versions / devices without Apple Intelligence, degrades to opening the in-app
  chat screen with the question pre-filled (same `isAvailable()` discipline Selene
  already uses for Ollama).

**2. Engine — `SeleneChatEngine`**

Wraps `LanguageModelSession(tools:instructions:)`. Shared by both the intent and the
in-app chat screen.

- **Instructions** = an ADHD-aware system prompt: concise spoken answers, always cite
  the source notes used, prefer surfacing *intention* ("what you were trying to do")
  over raw recall, say "I don't have a note about that" rather than inventing. Ports
  the system-prompt + citation discipline from archived
  `SeleneChat/.../ChatViewModel.swift` and `OllamaService.swift`.
- The model decides which tools to call; the engine does **not** hand-roll intent
  classification the way the archived `QueryAnalyzer` did — FM multi-step tool calling
  replaces that.

**3. Retrieval tools** (FM `Tool` conformers — `@Generable` arguments, `call()`
returns structured snippets). Each maps to a proven archived `DataProvider` method:

| Tool | Returns | Archived analogue |
|---|---|---|
| `SearchNotesTool(query, limit)` | top notes (hybrid semantic + keyword) | `searchNotesSemantically` / `searchNotes` |
| `GetClusterSynthesisTool(cluster)` | `topic_clusters.synthesis_text` for a category | cluster browse |
| `GetRecentNotesTool(days, limit)` | time-scoped recent notes | `getRecentNotes` |
| `GetRelatedNotesTool(noteId, limit)` | `note_connections` neighbours | `getRelatedNotes` |
| `GetDailyGiftTool()` | today's gift items | daily-gift `fetchGiftItems` |
| `GetWantsTool()` | active wants | wants design (Act 1) |

Tools return `source_uuid` + `title` + `essence` (never raw content where an essence
exists) so the answer can cite and deep-link, reusing the Core Spotlight
`uniqueIdentifier = source_uuid` convention from the 2026-06-14 doc.

**4. Data seam**

Tools call the **Fastify server** (`:5678` prod / `:5679` dev) today — identical to how
SeleneApp already reaches the backend. Post-LumenKit Phase 1 they call `LumenKit`
in-process (offline-capable). **The App Intent and tool definitions do not change
across the cut-over**; only the data source behind each tool does.

```
Hey Siri, ask Selene …
  → AskSeleneIntent.perform()
      → SeleneChatEngine (LanguageModelSession)
          ⇄ FM Tools  →  Fastify :5678  →  facts.db + selene.db
                          (later: LumenKit in-process)
      → grounded answer
  → Siri dialog (spoken) + snippet with deep links
```

**5. Privacy**

On-device Foundation Models by default — **notes never leave the device** for the
common path. Optional Private Cloud Compute escalation for heavy synthesis only (per
[2026-06-09-macos27-apple-native-reevaluation-design.md](2026-06-09-macos27-apple-native-reevaluation-design.md)).
No external/Claude call by default. This is a simplified version of the archived
`PrivacyRouter` tiering (on-device → PCC → external), collapsed to on-device + optional
PCC.

### Backend dependency (built in *this* repo when the slice ships — not now)

The live Fastify server has **no semantic-search HTTP endpoint**. Semantic retrieval
exists only as a *private* helper inside the worksheet route
(`findRelatedNotes()` in `src/routes/worksheets.ts`). `SearchNotesTool` needs a public
seam.

When Phase 1 is implemented, add:

```
GET /api/search?q=<text>&limit=<n>   (authenticated)
  → embed(q)                      // src/lib/ollama.ts  (nomic-embed-text, 768-D)
  → searchSimilarNotes(vector)    // src/lib/lancedb.ts (cosine distance)
  → fall back / merge with
    searchNotesKeyword(q)         // src/lib/db.ts (LIKE on title+content)
  → [{ id, source_uuid, title, essence, similarity }]
```

This reuses existing, tested primitives — it is a thin endpoint, not new retrieval
logic. **It is the only change required in the `slowspeedchase/selene` backend repo;**
all other work is Swift in `~/SeleneApp`.

### Phasing

- **Phase 1 — prove the RAG loop.** In-app chat screen + `SeleneChatEngine` + two core
  tools (`SearchNotesTool`, `GetClusterSynthesisTool`) against the Fastify seam.
  Backend prereq: the `/api/search` endpoint above. Deliverable: typing a question in
  the app returns a grounded, cited answer on-device.
- **Phase 2 — Siri surface.** `AskSeleneIntent` returning spoken dialog +
  `AppShortcutsProvider` phrases. Reuses the Phase 1 engine unchanged.
- **Phase 3 — ADHD-moat tools.** Add `GetWantsTool`, `GetDailyGiftTool`,
  `GetRelatedNotesTool`; citations + deep links in the snippet view; log "what you
  asked Selene about" to `attention_log` as a positive salience signal (the **one**
  sanctioned `facts.db` write — consistent with the daily-gift attention model).
- **Phase 4 — offline.** Cut tools over from Fastify to `LumenKit` in-process; add the
  provider abstraction (slice E) so the engine can swap Apple ↔ Claude per task.

---

## Implementation Notes

- **Repo split:** all Swift lands in `~/SeleneApp` (`Apps/SeleneApp/` for UI + intents,
  `Sources/LumenKit/` for the eventual in-process data layer). The **only** change in
  `slowspeedchase/selene` is the `/api/search` endpoint (Phase 1 prereq).
- **Prior art to port (not resurrect):** `archive/shelved-2026-03-21/SeleneChat/` —
  `ChatViewModel.swift` (conversation loop, citation extraction), `OllamaService.swift`
  (prompt assembly), `DataProvider.swift` (the retrieval method catalogue that the FM
  tools mirror), `PrivacyRouter.swift` (tiering). These inform the FM-native rewrite;
  the archived Ollama/SwiftUI app itself is **not** revived.
- **Embeddings:** stay on `nomic-embed-text` (768-D) via the server until an
  `NLContextualEmbedding` parity spike confirms on-device retrieval quality (the spike
  is already on the macOS 27 migration runbook). Do not embed on-device and compare
  against server vectors without normalization parity.
- **Data durability:** reads are oracle-only across `facts.db` (precious) + `selene.db`
  (disposable). The sole write is the Phase 3 `attention_log` signal, which lives in
  `facts.db` and is the already-sanctioned attention channel.
- **Dev/prod:** the two Xcode schemes (`com.selene.app` / `com.selene.app.dev`,
  purple-tinted) and `:5678` / `:5679` seams apply unchanged.
- **Context budget:** rely on **retrieval (RAG)**, never dump the corpus — tools return
  small cited snippets sized to the on-device model's context window.

---

## Ready for Implementation Checklist

Before creating a branch, all items must be checked:

- [ ] **Acceptance criteria defined** — drafted below; needs the open questions
      resolved first.
- [x] **ADHD check passed** — see below.
- [ ] **Scope check** — Phase 1 alone is likely > 1 week (new endpoint + first
      on-device FM integration). **Split: promote Phase 1 as its own slice** before
      this can be Ready.
- [ ] **No blockers** — open questions below (OS availability, retrieval parity) block
      Ready.

### Acceptance Criteria (draft, Phase 1)

- [ ] `GET /api/search?q=&limit=` returns cited semantic+keyword hits on the dev server.
- [ ] In-app chat screen answers a question grounded in real notes, on-device, with at
      least one correct citation/deep link.
- [ ] Graceful fallback message when Apple Intelligence is unavailable.

### ADHD Design Check

- [x] **Reduces friction?** Ask by voice — no unlocking, searching, or digging.
- [x] **Visible?** The answer is spoken aloud and shown as a snippet; nothing to
      remember to check.
- [x] **Externalizes cognition?** The system recalls *for* you on demand — the point of
      Selene.

---

## Open Questions

1. **OS availability:** does `AskSeleneIntent` return an **inline spoken answer**
   without opening the app on the user's current OS (iOS 26), or does that require iOS
   27-stable? Confirm FM Tool-calling + dialog-returning intents on the target beta.
2. **Retrieval parity:** server `nomic-embed-text` vs on-device `NLContextualEmbedding`
   — run the runbook spike before Phase 4 in-process retrieval.
3. **Relationship to Tier 2:** confirm that `SurfaceGiftExtension` /
   `SurfaceWantExtension` from the 2026-06-14 doc are **absorbed** as two tools of this
   engine (recommended) rather than kept as separate Siri surfaces.
4. **Scope split:** carve Phase 1 (chat screen + `/api/search`) into its own Ready
   slice with its own acceptance criteria and writing-plan.

---

## Links

- **Extends:** [2026-06-14-seleneapp-ios27-siri-design.md](2026-06-14-seleneapp-ios27-siri-design.md) (generalizes Tier 2), [2026-02-14-context-blocks-apple-intelligence-design.md](2026-02-14-context-blocks-apple-intelligence-design.md) (slice D)
- **Strategy:** [2026-06-09-macos27-apple-native-reevaluation-design.md](2026-06-09-macos27-apple-native-reevaluation-design.md)
- **Moat data:** [2026-06-07-executive-assistant-wants-design.md](2026-06-07-executive-assistant-wants-design.md), [2026-06-13-act0-daily-gift-design.md](2026-06-13-act0-daily-gift-design.md)
- **Prior art:** `archive/shelved-2026-03-21/SeleneChat/`
- **Branch:** (added when implementation starts)
- **PR:** (added when complete)
