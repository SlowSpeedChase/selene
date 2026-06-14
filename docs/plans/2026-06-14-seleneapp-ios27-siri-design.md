# SeleneApp — iOS 27, Apple-Native, Siri-Integrated

**Date:** 2026-06-14
**Status:** Vision (needs acceptance criteria + scope check per slice before Ready)
**Topic:** ios27, siri, app-intents, foundation-models, seleneapp, swift, selenemarkup, lumen

---

## What this is

SeleneMarkup (the iPad worksheet prototype at `~/SeleneMarkup`) is absorbed into a unified native app — **SeleneApp** (`~/SeleneApp`). This is the same app as "Lumen" (the earlier codename) but branded correctly from the start.

The goal is a native Apple app that:
- Uses iOS 27 App Intents as the Siri surface for retrieval and navigation
- Indexes Selene's processed notes into Core Spotlight so Apple Intelligence can see them
- Carries SeleneMarkup's existing SwiftUI UI as its foundation (nothing thrown away)
- Grows toward Foundation Models for on-device inference (phased, not day-one)
- Runs as two side-by-side apps on iPad: **Selene** (prod) and **Selene Dev** (dev, purple-tinted icon)

This is **Lumen Phase 2** (the iOS app) started early, and the earned-replacement path for SeleneMarkup.

---

## Why now

WWDC 2026 (June 8–9) confirmed:
- **App Intents is the only Siri surface** — SiriKit is deprecated. Building now means building the right thing.
- **Foundation Models** runs on-device, free, inside the App Store sandbox — the "we need Ollama on a Mac" architecture is no longer permanent.
- **Core Spotlight + Siri Extensions** — third-party apps can make content visible to Apple Intelligence without using Apple Notes.
- **`@Generable` structured output, multimodal input, on-device fine-tuning** — on-device slices that directly map to Selene's pipeline work.

The strategic direction is already committed: [2026-06-09-macos27-apple-native-reevaluation-design.md](2026-06-09-macos27-apple-native-reevaluation-design.md). This doc is the **tactical iOS-app execution** of that direction.

---

## Competitive positioning — ADHD layer on Apple's engine

Apple Notes + Siri will handle generic capture and retrieval well. That is not the threat; it is the freeing constraint.

**What Apple covers for free by iOS 27:**
- Capture → Siri → Apple Notes (zero-friction, out of the box)
- Spotlight RAG + Personal Context graph spanning Mail, Messages, Calendar, Notes
- "What did I note about X?" over Apple Notes via Siri Extensions
- Summarization and basic organization via Foundation Models

**What Selene is genuinely non-replicable:**
- **The ADHD-specific interaction model.** The daily gift (≤3 items, delight-first, guilt-free taps, attention log) is designed around a specific cognitive pattern. Apple builds for the average user.
- **The curated 8-category taxonomy + sub-categories.** This IS your mental model externalized. Apple's graph is generic; it doesn't know your specific categories matter to you.
- **The "wants" lifecycle.** Coalescence of fractured notes into named wants, held without nagging, resurfaced only on positive signal — an ADHD executive-function tool Apple has no roadmap for.
- **The attention log + salience decay.** Apple doesn't track what you engaged with and how that should decay over time to surface the right thing.
- **Control and inspectability.** You can read, rebuild, and modify your entire SQLite database. Apple's graph is opaque.

**The design rule:** don't try to replicate what Apple does natively. Use Apple's engine (Foundation Models for inference, Core Spotlight for visibility, App Intents for Siri surface). Own the cognitive layer on top.

**The App Store pitch:** "Apple Notes + Siri is a general-purpose tool. Selene is built for how your brain actually works."

---

## Structure

### Repository

| Before | After |
|---|---|
| `~/SeleneMarkup` — standalone Swift/SwiftUI iPad app | Retired |
| `~/Lumen` — new repo, Phase 0 scaffolding + Phase 1 plan | Renamed `~/SeleneApp` |

`~/SeleneApp` layout:
```
~/SeleneApp/
  Sources/LumenKit/       # Swift pipeline port (Phase 1, existing plan)
  Apps/SeleneApp/         # SwiftUI iOS app — SeleneMarkup's UI rebased here
  Apps/SeleneMac/         # Mac app (Phase 2, later)
  docs/plans/             # Design + implementation plans (Lumen Phase 0 scaffolding)
```

**Migration:** SeleneMarkup's SwiftUI source (worksheet view, PencilKit canvas, cluster browse, `HandwritingService`, `WorksheetViewModel`) moves into `Apps/SeleneApp/`. The SeleneMarkup GitHub repo is archived once the migration is complete.

### Data seam

- **Now:** `Apps/SeleneApp/` calls Selene's Fastify server at port 5678 (same as SeleneMarkup today)
- **Post-LumenKit Phase 1:** calls `LumenKit` directly in-process — offline-capable, no server dependency

The App Intent definitions do not change between phases; only the data source behind them does.

---

## Branding + dev/prod split

Two Xcode schemes in one project, mirroring the backend's prod/dev split:

| | Prod app | Dev app |
|---|---|---|
| **Display name** | Selene | Selene Dev |
| **Bundle ID** | `com.selene.app` | `com.selene.app.dev` |
| **Icon** | Selene icon | Same icon, purple tint (Xcode asset catalog Color Filter, zero code) |
| **Server** | Prod Fastify :5678 | Dev Fastify :5679 |
| **Side-by-side install** | Yes (different bundle IDs) | Yes |

`AppConfig.swift` reads a build setting (`SELENE_ENV`) to select the server URL — same pattern SeleneMarkup already uses.

---

## Screens — ADHD moat only

SeleneApp does NOT build a generic note browser. Apple Notes + Siri does that better. Every screen must be something Apple cannot replicate.

| Screen | What it is | Apple can do this? |
|---|---|---|
| **Daily gift** | ≤3 surfaced notes, delight-first, 4 guilt-free reaction taps, attention log | No |
| **Wants tracker** | Named wants, fragment coalescence, dormancy without nagging, resurface on positive signal | No |
| **Taxonomy browser** | 8 categories + sub-categories — your mental model, browsable | No |
| **Attention log / salience view** | What you engaged with, decayed over time | No |

Generic note search is intentionally absent — Spotlight + Siri handles it.

---

## App Intents / Siri — two tiers

### Tier 1 — Navigation intents (ship first, works on current Fastify seam)

Standard App Intents registered via `AppShortcutsProvider`. Siri opens the app and navigates to the right screen. No special iOS 27 features required — these work on iOS 16+.

| Intent | Example phrase | Navigates to |
|---|---|---|
| `OpenWorksheetIntent` | "Show me my Selene gift" | Daily gift / worksheet view |
| `OpenWantsIntent` | "Show my wants in Selene" | Wants tracker |
| `OpenClusterIntent(@Parameter cluster)` | "Show my research notes in Selene" | Named category/cluster |
| `LogReactionIntent(@Parameter reaction)` | "Mark that as important in Selene" | Logs attention signal, confirms inline |

Explicitly NOT built: a generic `SearchNotesIntent` — Apple Notes + Spotlight does this better.

### Tier 2 — Siri Extensions (iOS 27, design for now, build when stable ~Sept)

New in iOS 27: Siri can answer queries **inline** without opening the app, using multi-step tool calling inside a `LanguageModelSession`. The LM calls App Intents as tools to compose an answer.

| Extension | Example phrase | Behavior |
|---|---|---|
| `SurfaceGiftExtension` | "What's today's Selene gift?" | Siri reads the gift item inline — no app open |
| `SurfaceWantExtension` | "What wants does Selene have for me?" | Siri lists active wants inline |

Tier 2 requires iOS 27. Design the architecture to support it; ship Tier 1 first.

---

## Data visibility — Core Spotlight bridge

**SQLite stays the source of truth.** Apple Notes is never the database. The current Apple Notes digest (AppleScript output) stays as a human-readable mirror only.

**How Apple sees Selene's notes:**

The processing pipeline gains one new step — Core Spotlight donation — after processing, not during capture:

```
Capture (Drafts / Voice / future Siri)
  → Fastify → ingest.ts → facts.db
  → process-llm.ts (concepts, category, essence)
  → [NEW] CSSearchableItem donation → Core Spotlight index
      (title, essence, category, tags — NOT raw content)
  → export-obsidian, daily digest, etc.
```

Apple Intelligence's Personal Context graph receives the **processed, categorized, essence-extracted** version — not raw dumps. This is better than donating raw text.

**`NSUserActivity` donation (bonus signal):**

Every time the user views a note or taps a reaction in the daily gift, `SeleneApp` donates an `NSUserActivity`. Siri learns from these — which notes you return to, what you tap on. This signal aligns with and augments Selene's own attention log + salience decay, for free.

**What gets indexed in Spotlight:**
- `title` — note title
- `contentDescription` — the note's essence (distilled summary, not raw content)
- `keywords` — category + sub-category + top concepts
- `uniqueIdentifier` — `source_uuid` (for deep-link back to the note in the app)

Raw note content is NOT indexed — keeps the privacy promise and keeps the index noise-free.

---

## Foundation Models — phased on-device slices

These are baked into the architecture from day one but phased in delivery. From the existing slice inventory in [2026-02-14-context-blocks-apple-intelligence-design.md](2026-02-14-context-blocks-apple-intelligence-design.md):

| Slice | Replaces | Phase |
|---|---|---|
| **`@Generable` structured extraction** | Ollama `mistral:7b` JSON parsing | Phase 2 — first Foundation Models work |
| **On-device fine-tuning** (8-category classifier) | Generic Ollama classification | Phase 3 — private Selene-specific model |
| **Multimodal OCR** | Claude Vision API (paid) + `qwen2.5vl` | Phase 3 — replace paid API call |
| **`SpeechTranscriber`** | Whisper.cpp voice path | Phase 3 — ~2× faster, OS-managed |
| **Provider abstraction** (`LanguageModel` protocol) | Hard-coded Ollama calls | Phase 4 — swap Apple ↔ Claude ↔ Ollama per task |

**Availability gate:** all Foundation Models slices require iOS/macOS 27 with Apple Intelligence. Every slice must degrade gracefully where Apple Intelligence is unavailable (same `isAvailable()` discipline Selene already uses for Ollama).

**Embeddings note:** `nomic-embed-text` (768-D, Ollama) stays as the embedding source until `NLContextualEmbedding` parity is confirmed. The validation spike from the macOS 27 migration runbook covers this.

---

## Capture pipeline — unchanged

Capture stays exactly as-is: Drafts, Voice Memos, iOS Shortcut, Kindle Scribe. The Spotlight donation step is additive, not a replacement. Siri capture ("Hey Siri, add a note to Selene…") is a **later** priority — architecture supports it but it is not in scope for the first build.

---

## Relationship to existing designs

| Design | Relationship |
|---|---|
| [2026-06-09-macos27-apple-native-reevaluation-design.md](2026-06-09-macos27-apple-native-reevaluation-design.md) | Strategic umbrella — this doc is the tactical iOS execution |
| [2026-02-14-context-blocks-apple-intelligence-design.md](2026-02-14-context-blocks-apple-intelligence-design.md) | Foundation Models slice inventory — this doc adopts those slices phased |
| [2026-06-07-executive-assistant-wants-design.md](2026-06-07-executive-assistant-wants-design.md) | The wants lifecycle = a core SeleneApp screen (Act 1); Act 0 daily gift = another core screen |
| [2026-05-26-selene-mobile-companion-design.md](2026-05-26-selene-mobile-companion-design.md) | SeleneMarkup — this design supersedes it; SeleneMarkup's work is absorbed, not discarded |
| [2026-05-28-prod-dev-split-design.md](2026-05-28-prod-dev-split-design.md) | Dev/prod discipline — this doc extends the same pattern to the native app |
| Lumen Phase 0 scaffolding (in `~/SeleneApp/docs/plans/`) | Dev environment setup for the new repo — still applies |
| Lumen Phase 1 plan (LumenKit port) | Still valid — becomes the data layer that replaces the Fastify seam |

---

## Open questions (before any slice can be Ready)

1. **Repo migration:** does SeleneMarkup's Swift code move cleanly into `Apps/SeleneApp/` under the existing `~/Lumen` (soon `~/SeleneApp`) repo structure? Spike: copy the source, check `xcodegen` / SPM targets resolve.
2. **Validation spike (from macOS 27 runbook):** `fm` CLI quality vs `mistral:7b` + `NLContextualEmbedding` clustering parity — both needed before Phase 2 Foundation Models work begins.
3. **Core Spotlight: which notes?** All processed notes, or only notes above a salience threshold? (Start with all — filter later if the index grows noisy.)
4. **`AppShortcutsProvider` phrases:** Apple requires phrases to be declared at compile time. Finalize the exact phrase list before the App Intents slice is Ready.
5. **Tier 2 Siri Extensions API:** confirm exact iOS 27 API surface (new in beta — may shift before stable).

---

## ADHD check

- **Reduces friction:** Siri navigation intents (Tier 1) let the user jump directly into the daily gift or wants view without unlocking, finding the app, and navigating — one voice phrase.
- **Externalize working memory:** the taxonomy browser and wants tracker make the cognitive model visible without mental tracking.
- **Invisible by default:** Core Spotlight donation, `NSUserActivity`, Foundation Models inference — all automatic, zero new cognitive load.
- **Delight-first:** the daily gift screen is the first thing Siri can open — the most ADHD-positive surface leads.

---

## Next steps (to promote slices to Ready)

This design intentionally covers the full arc. The right move is to pick ONE slice for the first implementation plan:

**Recommended first slice:** the **repo migration + branding** (SeleneMarkup → `~/SeleneApp`, two schemes, purple dev icon). This is pure structure — zero risk, enables everything else, and gives you a working Selene-branded app on iPad immediately.

**Second slice:** **Tier 1 App Intents** (`OpenWorksheetIntent` + `OpenClusterIntent`) — these work on the current Fastify seam, no Foundation Models required, and they deliver the first Siri experience.

Invoke `writing-plans` for the first slice once the repo migration design is promoted to Ready.
