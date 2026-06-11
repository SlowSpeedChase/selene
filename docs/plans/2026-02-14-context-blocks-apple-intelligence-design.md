# On-Device Apple Intelligence Integration (Foundation Models, iOS/macOS 27)

> **Originally:** "Context Blocks + Apple Intelligence Integration" (2026-02-14)

**Status:** Vision (needs re-planning against current architecture)
**Date:** 2026-02-14
**Revised:** 2026-06-09 — re-scoped after WWDC 2026 (iOS/macOS 27 Foundation Models) and the 2026-03-21 simplification.

---

## ⚠️ Revision banner — read first

This doc was authored 2026-02-14 against two things that **no longer exist**:

1. **SeleneChat** (the macOS SwiftUI app) and the **thread / thread-chat system** were
   **archived in the 2026-03-21 codebase simplification** (`docs/plans/2026-03-21-codebase-simplification-design.md`).
   The original premise — "thread conversations pull all notes, truncate at 3000 tokens" — describes a
   feature that is gone. There is no `threads` table, no `note_chunks` table, and no thread-chat retrieval path
   in the current code (verified 2026-06-09).
2. **iOS 26 Foundation Models assumptions** — the original routing table was built around a fixed
   ~3B on-device model with a **4,096-token context window**. WWDC 2026 (iOS/macOS 27) shipped a
   **larger on-device model, an expanded context window, on-device fine-tuning, full multi-step tool calling,
   expanded structured output, multimodal image input, and a provider-abstraction layer** — which invalidates
   most of the "Apple is too small, route to Ollama" reasoning below.

The companion **implementation plan (`2026-02-14-context-blocks-apple-intelligence-plan.md`) is fully obsolete**
(2114 lines of Swift TDD against `SeleneChat/...` paths that no longer exist). It is retained for history only
and carries a superseded banner.

**What survives:** the *idea* that Selene should use Apple's on-device models where they beat a network/Ollama
round-trip. The rest of this doc re-grounds that idea in (a) the **current** architecture and (b) **iOS 27**
capabilities. This is **Vision**, not Ready — it needs a fresh plan against real current files before any code.

---

## Current architecture (what we're actually integrating into)

Selene today (verified 2026-06-09):

- **Server-side TypeScript** (Fastify, port 5678) + **Ollama** local LLM. Core models:
  `mistral:7b` (extraction/synthesis/summary), `nomic-embed-text` (768-D embeddings),
  `qwen2.5vl:7b` (e-ink vision OCR). See `src/lib/ollama.ts`, `src/lib/prompts.ts`.
- **Capture paths** → webhook → `src/workflows/ingest.ts`:
  Drafts; iOS Shortcut + **Claude Vision API** (whiteboard); Apple **Voice Memos** via
  **Whisper.cpp** (`src/workflows/voice-ingest.ts`, `src/lib/whisper.ts`); Kindle Scribe PDFs via
  **Ollama `qwen2.5vl:7b`** (`src/workflows/eink-ingest.ts`).
- **Process pipeline**: `process-llm.ts` (concept/category/theme extraction → JSON),
  `distill-essences.ts`, `synthesize-topics.ts` (8-category clustering), `export-obsidian.ts`.
- **Delivery**: Apple Notes digest (AppleScript, `src/lib/apple-notes.ts`), APNs push (`src/lib/apns.ts`),
  TRMNL e-ink.
- **Shipped iPad companion: SeleneMarkup** — talks to Selene over LAN/Tailscale; cluster browse →
  PencilKit canvas → **Vision OCR** (`VNRecognizeTextRequest`) → `POST /api/notes/:id/annotations`
  (`src/routes/notes.ts`, `src/routes/pkm.ts`). This is **the live Apple-side surface** and the natural
  home for Foundation Models code.
- **Two-file fact store**: `facts.db` (precious, append-only) + `selene.db` (disposable/derived),
  with a regenerating `rebuild`. Any new derived data (e.g. chunks) lives in `selene.db`.

**Key architectural fact:** Selene's core is **server-side Node/TS on a Mac**. Foundation Models is a
**Swift, on-Apple-device** framework. So integration lands at the **edges** — the SeleneMarkup iPad app,
the iOS Shortcut, or a small Swift helper invoked by the Mac — *not* inside the Node workflows, unless the
new Python SDK / Linux support (see below) proves usable server-side.

> **Likely true home: the Lumen repo.** Selene is being rewritten as an Apple-native app in a separate repo
> (**Lumen**). The on-device slices below are a natural fit for that rewrite rather than something to bolt onto
> Selene's TS core. Treat this doc as the *capability map / rationale*; the actual Swift implementation will
> most likely live in Lumen. (Lumen is outside this repo's scope — cross-reference, don't duplicate.)

---

## What iOS/macOS 27 Foundation Models newly enable

From WWDC 2026 (sources in the session that produced this revision):

| Capability (iOS 27) | What it changes for Selene |
|---|---|
| **Larger on-device model + expanded context window** | The "Apple's 4K context is too tight, must use Ollama" rule is largely retired. More tasks can run on-device. |
| **Expanded `@Generable` structured output** (nested types, enums, optionals, arrays) | Direct fit for Selene's JSON-emitting prompts (`EXTRACT_PROMPT` etc.). Reliable typed output instead of parsing free text. |
| **Multi-step tool calling inside `LanguageModelSession`** | Agent-style flows (e.g. classify → look up cluster → route) without hand-rolled orchestration. |
| **Multimodal image input** | On-device handwriting / whiteboard interpretation — could replace the paid **Claude Vision API** call and the Ollama `qwen2.5vl` OCR for some paths. |
| **On-device fine-tuning / adapters** | A Selene-tuned classifier for the fixed 8-category taxonomy, private, no data leaves device. |
| **`LanguageModel` provider-abstraction protocol** (swap Apple ↔ Claude ↔ Gemini) | One code path; pick provider per task without rewrites. |
| **Python SDK + Linux support** | *Potentially* lets the server itself call Foundation Models — **unverified**: may still require Apple hardware/entitlements. Spike before betting on it. |
| **`SpeechAnalyzer` / `SpeechTranscriber`** (on-device, ~2× faster than Whisper Large v3 Turbo) | Replacement for the Whisper.cpp voice path on Apple silicon. |
| **App Intents is now the only Siri surface** (SiriKit deprecated) + Siri "Extensions" | A new **capture + query** surface: "Hey Siri, add to Selene…" / "what did Selene capture about X". |

**Device/OS reality:** these are on-device frameworks requiring Apple Intelligence + recent Apple silicon
(iOS/macOS 27). Backwards-compatible: iOS 18 Foundation Models code still compiles. Anything Selene ships
must degrade gracefully where Apple Intelligence is unavailable (same `isAvailable()` discipline the Node
workflows already use for Ollama).

---

## Re-scoped integration opportunities (ranked by leverage)

These replace the original "chunking + LLM router + thread-chat retrieval" scope. Each is an **independent,
shippable slice** — pick one to plan first; do **not** treat this list as one project.

### A. `@Generable` structured extraction (highest leverage, lowest risk)
**Where:** the work `process-llm.ts` does via `EXTRACT_PROMPT` (concepts, category, themes, sentiment,
energy → JSON). **What:** define a Swift `@Generable` struct mirroring that JSON and run extraction on-device
in SeleneMarkup for notes captured/annotated on the iPad, *or* via a Mac-side Swift helper the server shells
out to. Removes brittle JSON parsing; the schema *is* the contract. **Caveat:** the server pipeline is the
source of truth today — decide whether on-device extraction *replaces* or *pre-fills* the Ollama pass.

### B. On-device transcription: Whisper.cpp → `SpeechAnalyzer`
**Where:** `src/workflows/voice-ingest.ts` + `src/lib/whisper.ts`. **What:** on Apple silicon, use
`SpeechTranscriber` (faster, OS-managed, already co-located with Voice Memos). **Caveat:** this is a Swift
framework; the current path is a Node workflow shelling out to a binary. Cleanest as a small Swift CLI the
workflow invokes (mirrors the existing `whisper-cli` shell-out), preserving the Node pipeline.

### C. On-device multimodal OCR for capture
**Where:** the iOS Shortcut whiteboard path (today: **Claude Vision API**, paid + networked) and
`eink-ingest.ts` (today: Ollama `qwen2.5vl:7b`). **What:** Foundation Models multimodal image input to
interpret handwriting/sketches on-device — cheaper, private, offline-capable. **Caveat:** validate quality vs
`qwen2.5vl`/Claude on real Kindle Scribe + whiteboard samples before switching; OCR fidelity is the whole game.

### D. Siri / App Intents capture + query surface (net-new)
**Where:** SeleneMarkup (the live Apple surface) + Selene's REST API (`src/routes/*`). **What:** App Intents
(now the mandatory Siri path) for voice capture into the webhook and natural-language query over clusters/notes.
Builds on existing APNs + REST infra. **Caveat:** scope carefully — this is a new feature, not a swap; needs
its own design pass and acceptance criteria.

### E. Provider-abstraction cleanup (enabling, optional)
If/when more than one of A–C ships, adopt the `LanguageModel` protocol so Apple-on-device / Claude / Gemini
are swappable per task. Only worth it once there's a second provider in play — premature otherwise.

**Embeddings note:** keep `nomic-embed-text` (768-D, Ollama) as the embedding source of record for now —
Apple's on-device contextual embeddings are lower-dimensional and the corpus is small; no pressure to move.

---

## Scope check

**Not Ready.** This is a menu of independent slices, not a <1-week unit, and the original plan's target app is
archived. Before any slice becomes Ready it needs:

- [ ] A pick of **one** slice (recommend **A: `@Generable` extraction** — most concrete, maps 1:1 onto an
      existing prompt, smallest blast radius).
- [ ] A decision on the **Swift-edge vs Node-core boundary**: does on-device work *replace* an Ollama step, or
      *pre-fill* it and let the server reconcile? (The fact-store `rebuild` invariant means derived data must
      stay regenerable from `facts.db`.)
- [ ] A **spike** on whether the FM Python SDK / Linux support is usable from the Node server at all, or whether
      everything must live behind a Swift binary / the iPad app.
- [ ] Acceptance criteria + ADHD check written against the chosen slice and **real current files**.

## ADHD check (direction, not yet slice-specific)

- **Reduces friction:** on-device capture interpretation (C) and Siri capture (D) shorten the path from thought
  to captured note — the core ADHD win.
- **Faster feedback:** on-device extraction/transcription (A, B) cut the network/Ollama round-trip, so capture
  feels instant.
- **Invisible by default:** provider routing and structured output are plumbing — no new cognitive load.
- **Privacy:** on-device keeps personal notes off the network, which lowers the activation cost of capturing
  sensitive thoughts.

---

## What changed from the original (summary for the curious)

| Original (2026-02-14) | Now (2026-06-09 revision) |
|---|---|
| Target: SeleneChat macOS app + thread-chat | SeleneChat archived → target is SeleneMarkup iPad app / Swift edge |
| Premise: fix all-notes-truncated thread retrieval | That feature was archived; premise void |
| Apple model: ~3B, fixed 4K context → route most tasks to Ollama | iOS 27: bigger model + expanded context → far more is on-device-viable |
| `note_chunks` table + chunk retrieval + LLM Router | Re-scoped to structured extraction / transcription / OCR / Siri slices |
| Status: Ready (10-task Swift TDD plan) | Status: Vision — plan obsolete, needs re-planning |

---

## Related

- **Lumen** (separate repo) — the Apple-native rewrite of Selene; the likely implementation home for the
  on-device slices in this doc.
- `docs/plans/2026-03-21-codebase-simplification-design.md` (what archived SeleneChat/threads)
- `docs/plans/2026-05-26-selene-mobile-companion-design.md` (SeleneMarkup — the live Apple surface)
- `docs/plans/2026-05-31-fact-store-design.md` (the `facts.db`/`selene.db` durability boundary)
- `src/workflows/voice-ingest.ts`, `src/workflows/eink-ingest.ts`, `src/workflows/process-llm.ts`,
  `src/lib/prompts.ts` (the concrete integration targets)
