# macOS 27 Re-evaluation — Apple-Native Direction (Path B)

**Date:** 2026-06-09
**Status:** Vision (needs refinement → the near-term validation spike can be promoted to Ready)
**Topic:** strategy, apple-intelligence, foundation-models, private-cloud-compute, app-intents, lumen, product-direction

---

## Why now

WWDC 2026 (June 8–9) opened **Private Cloud Compute (PCC)** and the **Foundation Models framework** to third-party developers. The capabilities that touch Selene/Lumen:

- **Free PCC, no keys, no account.** The framework auto-routes a request **on-device → PCC (32K context, configurable reasoning) → third-party model** (Claude/Gemini via the public `LanguageModel` protocol). Free for developers under 2M App Store downloads.
- **`fm` CLI** — on-device + PCC inference from the terminal / shell scripts (`fm chat`, pipe text to summarize/extract/generate).
- **Vision OCRTool** and a **Spotlight-powered local RAG** search tool, built in.
- **Siri is now an agent** that takes actions *inside* third-party apps — exclusively through **App Intents** (SiriKit deprecated).
- Framework **runs on Linux** via Swift's open-source runtime; goes **open source** later this summer.

These dissolve the three constraints that forced Selene's current split architecture:

| Constraint that shaped today's architecture | Dissolved by |
|---|---|
| "Local LLM needs a real always-on box" (→ Ollama on the Mac mini) | Free on-device + PCC inference |
| "The App Store can't ship inference" (→ Lumen's planned notarized Node companion) | Foundation Models runs inside the sandbox |
| "Capture needs a webhook server" (→ Drafts → Fastify → SQLite) | App Intents / Siri is an OS-level capture path |

---

## Priorities (user-stated, in order)

1. **Something working that I use.** — Already met by Selene's prod pipeline. This is a **protect** goal, not a build goal: don't break the daily driver.
2. **Sellable.** — This is Lumen's reason to exist. The macOS 27 features are precisely what make a *solo-built, sellable* app feasible: a stranger won't install Ollama or paste API keys, but on-device/PCC inference is zero-config. **The native bet pays off more for the *sell* goal than the *use* goal.**

---

## Strategic direction — lean Apple-native, with two guardrails

Go native for the highest-leverage, hardest-to-replicate wins: **inference, OCR, and the Siri/App Intents interface.**

- **Guardrail 1 — bet the engine, not the data.** Notes stay in open formats (**SQLite + Obsidian markdown**) so the AI engine stays swappable (Apple ↔ Ollama ↔ Claude). Data lock-in is the only lock-in that matters, and this avoids it. (Apple's own framework exposes Claude/Gemini through the same protocol and is going open-source + Linux, so engine lock-in is low.)
- **Guardrail 2 — don't rip out unproven replacements.** Embeddings stay on `nomic-embed` until Apple ships a **confirmed** equivalent (see open question #1).

It does **not** require rewriting the working TypeScript pipeline into Swift on day one. The gains come from swapping the **inference engine** and adding the **Siri/app surface** — captured incrementally.

---

## Compute strategy — on-device first

The target is to run **all existing tasks on the on-device model**: preserves the founding "never leaves the Mac" privacy promise, is free, and is simple.

**⚠️ Availability gap (do not scope around this wrongly):** Apple's on-device model and the `fm` CLI **ship with macOS 27**. Because Path B keeps Selene's prod on the mini on **stable** macOS (the "don't wipe to beta" conclusion), an on-device engine swap **cannot happen in the Selene TypeScript pipeline while the mini is on stable.** This work is therefore **Lumen-side** (Swift, on a macOS 27 machine) — *or* it waits until the mini moves to **macOS 27 stable (~Sept 2026)**. The table below is **Lumen's target architecture**, not a near-term Selene change. The keystone measurement (below) informs *Lumen's* design; it is not a Selene engine-swap on the critical path.

**Assumption (to be tested, not asserted):** the on-device model is *good enough* for the small tasks. Selene runs on local `mistral:7b` (7B) today and the user trusts the output — but Apple's on-device model has historically been smaller (~3B), so parity is an **assumption the keystone measurement (Q2) must confirm**, not established evidence.

**PCC is an optional escalation**, reserved for the heavy *new* synthesis work (the "wants" coalescence — see [executive-assistant-wants](2026-06-07-executive-assistant-wants-design.md)), and only adopted after measurement. No manual token/compute budgeting is required — the framework routes automatically, and both tiers are free (cost is latency/battery, not dollars).

| Task | Today | Target tier (Lumen / post-27-stable) | Note |
|---|---|---|---|
| Concept extraction | `mistral:7b` | on-device | assumed sufficient — Q2 confirms |
| Essence / summary | `mistral:7b` | on-device | small, bounded |
| Embeddings (clustering/connections) | `nomic-embed` | **stays for now** | native path **exists**: `NLContextualEmbedding` (NaturalLanguage fwk, 512-dim, ≤256 tok, on-device) — pending quality/length parity check (Q1) |
| Synthesis / "wants" coalescence | `mistral:7b` | on-device, **maybe PCC** | the one place extra reasoning may pay off |
| OCR (eink/folio) | vision models | on-device OCRTool | Apple ships a Vision-backed tool |

---

## Path B — earned replacement (chosen)

Considered three paths: **A** engine-swap-in-place (protects use, does nothing for sellability), **B** Lumen-as-sellable-home with Selene as daily driver until parity, **C** flag-day collapse (violates priority #1 — months not using a stable tool, on a beta OS). **B chosen.**

- **Selene keeps running untouched** as the daily driver (priority #1 protected).
- New energy goes into **Lumen** as the native, Siri-integrated, zero-config App Store product (priority #2), reading Selene's output as **oracle** — the no-write-back boundary already designed in [Lumen](#related).
- **Lumen takes over only when it hits parity on all four** (the takeover bar, below). Merge by **earned replacement**, never a flag-day rewrite. This also lets all the painful productization work (multi-user, support, strangers' privacy) be deferred until the personal version has earned it.

### Takeover bar — Lumen becomes the daily driver only when it matches Selene on **all four**:

1. **Capture** — near-zero friction (one tap / Siri via App Intents).
2. **Process** — categorize into the taxonomy + write the essence at quality matching Selene's output (Selene-as-oracle *measures* this parity).
3. **Surface back** — browse by cluster, the daily digest, the "wants"/worksheet view.
4. **Keep history** — the existing ~78 MB of real notes come along (read or migrated), nothing lost.

All four are required; none is individually deprioritized.

---

## Consequence for the wipe / beta question

The trigger for this whole discussion was "wipe the Mac, install the macOS 27 beta, dedicate it to Selene/Lumen." Because **protecting the daily Selene is priority #1**, the answer is: **do not wipe the Mac mini that runs prod Selene onto a beta OS.** Native/beta work belongs where it *cannot* take down the daily tool:

- a **separate APFS volume** (boot into macOS 27 without touching the prod volume), or
- a **spare Mac**, or
- **beta-only-for-Lumen-dev** while prod Selene stays on stable.

(Independent of this design: there is unpushed work — ~31 commits on `selene/main`, several local-only branches, ~26 Lumen commits — and the precious note DBs live only in `~/selene-data` + Time Machine. Any machine wipe must be preceded by pushing all branches to GitHub and making a second copy of `~/selene-data` off the TM drive. Tracked separately from this design.)

---

## Open questions

1. **~~Does Foundation Models expose an embedding API?~~ — RESOLVED (2026-06-09).** Foundation Models itself does **not**; its built-in **Spotlight Search Tool** does local RAG "with no embeddings, no vector DB, no setup." But Apple's **NaturalLanguage framework** provides **`NLContextualEmbedding`** — BERT sentence embeddings, **512-dim, ≤256 tokens, on-device, privacy-preserving** — a genuine native replacement candidate for `nomic-embed`. *Remaining sub-question (for the spike):* does 512-dim / 256-token output cluster Selene's notes at parity with `nomic-embed` (768-dim)? **Apple/Swift-only → Lumen-side**, not the TS pipeline.
2. **Does the on-device model match `mistral:7b`** on *the user's own* concept-extraction/essence output? **The keystone measurement** — on-device is historically smaller (~3B) so this is a real risk, not a formality. Run via the `fm` CLI on a macOS 27 separate volume against the **dev showcase corpus** (`test_run='dev-seed'`) — **never real prod notes** (prod-data guard + keeps a model-capability test clean of the privacy boundary). De-risks the entire direction.

---

## Near-term next step (a spike, not a rewrite)

Stand up **macOS 27 on a separate volume** and run the validation spike — **the one part of this design promotable to Ready first**:

1. **Keystone (Q2):** on-device model vs `mistral:7b` on the **dev showcase corpus** via the `fm` CLI — does extraction/essence quality hold?
2. **Embedding parity (Q1 sub-question):** does `NLContextualEmbedding` cluster the same corpus at parity with `nomic-embed`?

A few hours of work, zero threat to prod (separate volume + dev corpus only). **Both results inform *Lumen's* design** — neither is a near-term change to the Selene pipeline on the stable mini.

---

## Related

- [2026-02-14-context-blocks-apple-intelligence-design.md](2026-02-14-context-blocks-apple-intelligence-design.md) — the **tactical** on-device Foundation Models slices (`@Generable` structured extraction, `SpeechAnalyzer`, on-device OCR, Siri/App Intents capture, provider abstraction). This doc is the strategic umbrella; that doc holds the concrete slices.
- [2026-06-07-executive-assistant-wants-design.md](2026-06-07-executive-assistant-wants-design.md) — the heavy synthesis ("wants" coalescence) that is the primary candidate for PCC escalation.
- Lumen design (separate repo `~/Lumen`) — the Apple-native port that becomes the sellable home; reads prod Selene output as oracle, never writes back.
