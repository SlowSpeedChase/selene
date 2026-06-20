# macOS 27 Re-evaluation — Apple-Native Direction (Path B)

**Date:** 2026-06-09 (validation spike run **2026-06-19**)
**Status:** Vision for the broader Path B direction; the **validation spike is Ready → Done** — results in [Spike results (2026-06-19)](#spike-results-2026-06-19) below.
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

1. **~~Does Foundation Models expose an embedding API?~~ — RESOLVED (2026-06-09).** Foundation Models itself does **not**; its built-in **Spotlight Search Tool** does local RAG "with no embeddings, no vector DB, no setup." But Apple's **NaturalLanguage framework** provides **`NLContextualEmbedding`** — BERT sentence embeddings, **512-dim, ≤256 tokens, on-device, privacy-preserving** — a genuine native replacement candidate for `nomic-embed`. *Remaining sub-question (for the spike):* does 512-dim / 256-token output cluster Selene's notes at parity with `nomic-embed` (768-dim)? **Apple/Swift-only → Lumen-side**, not the TS pipeline. **— ANSWERED (2026-06-19): not yet at parity.** Confirmed 512-dim on-device; it captures real structure (**6.6× better than random** at finding the same neighbors) but only **42% top-5 nearest-neighbor recall** vs `nomic` → a noticeably different "related-notes" graph. Validates Guardrail 2: **embeddings stay on `nomic`.** (Caveat: naive mean-pooling of token vectors — a floor, not a ceiling.) Note since clustering is now category-based, embeddings only drive **connections**, so the spike measured neighbor-graph agreement, not partition parity. See [Spike results](#spike-results-2026-06-19).
2. **~~Does the on-device model match `mistral:7b`~~ — ANSWERED (2026-06-19): partially.** Measured on the dev showcase corpus (n=81). **Essence/summary holds (0.81 vs a 0.90 mistral-self-consistency ceiling — gap 0.09).** **Categorization does NOT hold out-of-the-box (0.68 vs 0.95 — gap 0.27, far beyond the ~0.05 sampling-noise floor).** First read as the predicted ~3B-vs-7B capability gap. The leading hypothesis — that it was an artifact of the free-text prompt ported from mistral, fixable with `@Generable` guided generation constraining output to the 8-category taxonomy — was **tested 2026-06-19 and FALSIFIED**: guided generation moved agreement only 0.68 → 0.69. The disagreements are systematic boundary calls (the on-device model draws broader categories: work/systems → *Projects & Tech*, health/relationships/daily → *Personal Growth*), and are NOT explained by cross-refs. So the gap is a **semantic taxonomy-boundary disagreement, not a formatting/capability problem** — and it is measured against mistral-as-oracle, not ground truth, so part of it is arguable labelings. Next lever: category **definitions + few-shot** targeting the confusable pairs, plus a **human-judged** sample to see whether on-device is *wrong* or merely *different*. See [Spike results](#spike-results-2026-06-19). *(Implemented via the FoundationModels Swift API in `LumenKit`, not the `fm` CLI — same on-device model, but the API is Lumen's real shipping path.)*

---

## Near-term next step (a spike, not a rewrite) — ✅ DONE 2026-06-19

Stand up **macOS 27 on a separate volume** and run the validation spike — **the one part of this design promotable to Ready first**:

1. **Keystone (Q2):** on-device model vs `mistral:7b` on the **dev showcase corpus** — does extraction/essence quality hold?
2. **Embedding parity (Q1 sub-question):** does `NLContextualEmbedding` match `nomic-embed` on the same corpus?

A few hours of work, zero threat to prod (separate volume + dev corpus only). **Both results inform *Lumen's* design** — neither is a near-term change to the Selene pipeline on the stable mini.

---

## Spike results (2026-06-19)

Run on the rebuilt macOS 27 mini (the wipe described in the migration runbook), inside `LumenKit` via the **FoundationModels Swift API** (the real Lumen shipping path) + `NLContextualEmbedding`, **not** the `fm` CLI. Measured against the **dev-seed showcase corpus only** (`test_run='dev-seed'`, 81 processed notes / 80 embedded), exported read-only from `~/selene-data-dev` — **zero prod notes**, per the data guard.

### Q2 keystone — on-device generation vs `mistral:7b`

| metric | mistral re-extracting its own oracle (noise ceiling) | Apple on-device | gap |
|---|---|---|---|
| category match | **0.95** (n=81) | **0.68** | **−0.27** |
| essence similarity | **0.90** (n=61) | **0.81** | **−0.09** |

- **Essence/summary: good enough.** 0.81 against a 0.90 ceiling — on-device summarizes ~as well as mistral.
- **Categorization: a real gap, not sampling noise.** The mistral-vs-itself ceiling (0.95) bounds temperature noise at ~5%; on-device's 0.68 is a genuine gap.
- **Guided-generation follow-up (2026-06-19b) — the format hypothesis FAILED.** Re-ran categorization with `@Generable` + `@Guide(.anyOf(Prompts.categories))` (decode-constrained to the exact 8-item taxonomy), temperature 0, taxonomy in `instructions`, schema auto-injected — **0.68 → 0.69 (+0.01).** It eliminated invalid-label/JSON-parse errors (1 failure in 81) but did **not** improve agreement, so output formatting was never the bottleneck. The misses are **systematic boundary calls** — the on-device model collapses toward broad attractors (work/systems → *Projects & Tech*; health/relationships/daily → *Personal Growth*) — and are **not** the oracle's cross-ref categories (only 6/81 notes even have one; 0/12 sampled matched). **The gap is taxonomy-boundary judgment, measured against mistral-as-oracle (not truth).** Keep guided generation for reliability; it is not the parity lever.
- **⚠️ CORPUS-VALIDITY FINDING (2026-06-19c) — the headline semantic numbers are measuring the wrong thing.** A human eval (the operator) of disagreement notes revealed the **dev-seed corpus is synthetic STRUCTURAL-test data, not semantically realistic** — templated noise ("Meeting note #282", thrice-repeated sentences, fictional projects) seeded to exercise content-hash/tags/clustering-determinism, never written to *mean* anything. So categorization "agreement" is two models filing gibberish, graded against a third arbitrary opinion. On the **4 of 6 sampled notes the operator could actually judge, on-device matched the human 3×, mistral 1×** — i.e. on-device was the *better* categorizer on meaningful notes; the "gap" was an artifact of mistral-as-oracle + an unreal corpus. **The 0.68/0.69 categorization and 0.42 neighbor numbers are not trustworthy quality signals; essence 0.81 is less affected but softer than presented.** What stays valid: the mechanical parity this corpus was built for (hash/tags/clustering determinism) and the architecture mapping.
- **Real next lever (revised):** rebuild a **small, genuinely realistic showcase corpus with the operator's OWN category labels as ground truth** (deletes the mistral-as-oracle problem), then re-run keystone + embedding parity against it. Category definitions/few-shot become meaningful only once the corpus and labels are real.

### Q1 embedding parity — `NLContextualEmbedding` (512-d) vs `nomic-embed` (768-d)

| metric | value |
|---|---|
| NL dimension | **512** (confirmed) |
| top-5 neighbor recall vs nomic | **0.42** |
| top-5 neighbor Jaccard | **0.30** |
| random-chance baseline | 0.063 → **6.6× lift** |

- NL **captures real semantic structure** (6.6× better than random at finding the same neighbors) but only **moderately agrees** with nomic on specific neighbors (42% of nomic's top-5 retained) → a noticeably different "related-notes" graph.
- **Not a drop-in replacement.** Confirms **Guardrail 2: embeddings stay on `nomic`.**
- Metric choice: Selene retired embedding-*clustering* for category-clustering, so embeddings now only feed **connections** (nearest-neighbor related notes). Neighbor-graph recall is the faithful, scale-invariant metric (the two models' cosine ranges differ; nomic's absolute 0.65/0.75 thresholds don't transfer). Caveat: NL sentence embedding is a naive mean-pool of token vectors — better pooling/normalization could lift agreement; treat 0.42 as a floor.

### Net read

The Path B bet holds, but the categorization verdict is **not yet earned** — it was measured on an unrealistic corpus against mistral-as-oracle, and the one human spot-check put on-device *ahead* of mistral on meaningful notes. Defensible reads today: **essence/summary is promising on-device; embeddings stay on nomic; categorization is UNDETERMINED pending a realistic, human-labeled corpus.** The biggest lesson of the spike is methodological: **a structural-parity corpus cannot evaluate semantic quality** — that needs real notes with the operator's own labels. None of this touches the stable-mini Selene pipeline — it is input to *Lumen's* engine design.

### Reproducibility (in the `~/Dev/Lumen` repo)

- `Tools/export-oracle-migrated.mjs` — two-DB read-only corpus exporter for the post-migration Selene schema (`facts.db` raw notes ⋈ `selene.db` processed/embeddings); regenerates `Tests/LumenKitTests/Fixtures/oracle-corpus.json` (gitignored).
- `Sources/LumenKit/Inference/NLEmbeddingProvider.swift` — `NLContextualEmbedding` `TextEmbedder` (actor, mean-pooled).
- `Tests/LumenKitTests/Phase5SpikeTests.swift` — keystone (on-device + mistral-ceiling).
- `Tests/LumenKitTests/Phase5EmbeddingParityTests.swift` — neighbor-graph parity.

### Follow-ups promotable to their own plans

1. ~~**`@Generable` categorization**~~ — DONE 2026-06-19, no lift (0.68 → 0.69). Superseded by: **category-definitions + few-shot** targeting the confusable pairs, and a **human eval** of disagreements (on-device wrong vs merely different). That eval is now the single highest-leverage open question — it decides whether the categorization gap is even real or just mistral-flavored.
2. **Better NL pooling** — try normalized / non-mean pooling; re-measure neighbor recall before concluding nomic is irreplaceable.
3. **PCC tier** — `fm`'s `pcc` model was unavailable in this headless context; re-check for the heavy "wants" synthesis escalation.

---

## Related

- [2026-02-14-context-blocks-apple-intelligence-design.md](2026-02-14-context-blocks-apple-intelligence-design.md) — the **tactical** on-device Foundation Models slices (`@Generable` structured extraction, `SpeechAnalyzer`, on-device OCR, Siri/App Intents capture, provider abstraction). This doc is the strategic umbrella; that doc holds the concrete slices.
- [2026-06-07-executive-assistant-wants-design.md](2026-06-07-executive-assistant-wants-design.md) — the heavy synthesis ("wants" coalescence) that is the primary candidate for PCC escalation.
- Lumen design (separate repo `~/Lumen`) — the Apple-native port that becomes the sellable home; reads prod Selene output as oracle, never writes back.
