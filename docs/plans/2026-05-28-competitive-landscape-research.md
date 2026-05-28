# Competitive Landscape — What Selene Can Learn

**Date:** 2026-05-28
**Status:** Research (informs future Vision docs)
**Topic:** strategy, competitive-landscape, pkm, adhd, synthesis, agent-layer

---

## Purpose

A scan of the tools doing something adjacent to Selene, read **not** as "who's a threat"
but as "what have other people already figured out that we should steal, adapt, or
deliberately reject." The competitive matrix is demoted to an appendix; the body of this
doc is **leverage** — lessons mapped to Selene's real code and roadmap, each with a
concrete next step.

**One-line finding:** No tool ships Selene's full stack (ADHD-first + fully local + automatic
clustering→narrative synthesis + proactive digest + multimodal capture). But the *commodity*
layers (local RAG, auto-organizing notes) are crowded, and a handful of products have each
solved one piece better than we have. Those pieces are the point of this doc.

---

## The leverageable lessons (prioritized)

### 1. Make the digest *agentic*, not just a summary

- **Who taught us:** Saner.ai (morning proactive scan that says "here's what to look at"), Limitless/Rewind (daily briefing with follow-up suggestions).
- **Why it fits:** Our 6am Apple Notes digest (`send-digest.ts`) currently *reports* (yesterday's captures, themes). The competitors *direct attention* — they answer "what should I do with this?" not just "here's what happened." For ADHD, a wall of summary is still a wall; a single "the one thing worth re-reading today" is the win.
- **Maps to:** `src/workflows/send-digest.ts`; the planned "Topics circling" section in `2026-05-26-synthesis-retrieval-agent-design.md`.
- **Next step:** Add a "Worth your attention today" lead line to the digest — one resurfaced note or one circling topic, chosen by the synthesis cluster with the most new activity. One extra Ollama call, top of the note, above the summary.

### 2. Resurface the *forgotten*, not just the recent

- **Who taught us:** Reflect (scheduled spaced-repetition email that resurfaces "hidden gems"), MyMind (calm recall), Daily Brain Bits (emails your own old notes back on a spaced schedule).
- **Why it fits:** This is the most on-thesis idea in the whole landscape for us. "Out of sight, out of mind" is literally an ADHD principle in `.claude/ADHD_Principles.md`. Today Selene surfaces recent + active topics; almost nobody's digest reaches *backward* into the archive.
- **Maps to:** `pkm_review_state` table + "haven't seen this in 7+ days" review queue and "on this day" already designed in `2026-04-12-pkm-browse-layer-design.md`. Reflect proves this deserves to be **pushed** (in the digest), not just **pulled** (a page you visit).
- **Next step:** When building the PKM browse layer, also emit one "from the archive" item into the daily digest — spaced resurfacing piggybacking on the surface we already deliver to. Cheap, high ADHD value.

### 3. Surface related context *at the moment of capture*

- **Who taught us:** Mem ("Heads Up" — shows related existing notes live as you write).
- **Why it fits:** We already have this *in one place only* — the "Selene remembers…" related-notes panel in interactive worksheets (nomic-embed-text + LanceDB, shipped 2026-05-27). Mem's lesson is that this belongs **everywhere a note enters**, not just the worksheet. The connective-tissue payoff happens at capture time, when the link is still in your head.
- **Maps to:** `src/workflows/ingest.ts` + the related-notes retrieval already built for worksheets; the `RetrieverAgent.searchBySimilarity` planned in the synthesis design.
- **Next step:** After ingest, optionally return the top 1–2 semantically-similar prior notes in the webhook response / Drafts confirmation ("this connects to 2 earlier notes"). Reuse the worksheet retrieval path — no new infra.

### 4. Synthesis should surface *tensions and changes of mind*, not just themes

- **Who taught us:** NotebookLM (explicitly finds contradictions and patterns across sources).
- **Why it fits:** Our synthesis prompt already gestures at this ("the open question that keeps resurfacing", "recurring questions, tensions") — NotebookLM validates leaning *harder* into it. A second-brain that says "you used to think X, lately you lean Y" is doing something search can't.
- **Maps to:** the synthesis prompt in `2026-05-26-synthesis-retrieval-agent-design.md` (Component 2).
- **Next step:** Add a "What's shifted" line to the per-cluster synthesis prompt — ask the model to name any contradiction or change in stance across the dated notes, or say "consistent" if none. Keep it one sentence so it stays honest and skimmable.

### 5. Task breakdown is the proven ADHD primitive

- **Who taught us:** Goblin Tools "Magic ToDo" (single most-loved ADHD utility: turn a vague intention into ordered steps), Tiimo (AI task breakdown).
- **Why it fits:** Task *initiation* is the ADHD wall, and breakdown is the established lever. We already planned this — worksheets Phase 2 "guided task-breakdown (one note/project → handwritten sub-steps → new linked notes)." The landscape says: this isn't a nice-to-have, it's the feature people switch apps for.
- **Maps to:** `2026-05-26-interactive-worksheets-design.md` (Phase 2 generators); the agent layer (`src/agents/`) could host a "breakdown" action.
- **Next step:** Prioritize the breakdown worksheet generator over the other Phase 2 types. It's mostly SQL + a prompt on the engine we've already built.

### 6. Proactively surface *candidate* tasks from notes (you still approve)

- **Who taught us:** Saner.ai ("tasks from your recent notes," surfaced unprompted).
- **Why it fits:** Our agent layer today *enriches existing Things tasks* — it waits for a task to exist. Saner runs the other direction: it reads your notes and proposes the tasks. This is exactly the "thought → task" half of the broken loop in `2026-03-21-close-the-loop-design.md`, and it stays inside our human-in-the-loop contract (agent *proposes*, you *decide*).
- **Maps to:** `src/agents/` (new "task-candidate" agent alongside `things-metadata-enricher`), the approval dashboard at `/dashboard`, and the archived task-extraction work (concept preserved, don't revive the old table).
- **Next step:** A read-only agent that scans recent notes for action-shaped language and proposes Things tasks into the existing approval dashboard. No new execution path — reuse `ActionExecutor` + approve/reject UI.

### 7. An *audio* digest of your topics

- **Who taught us:** NotebookLM (Audio Overview — turns your sources into a listenable conversation).
- **Why it fits:** Audio is a strong ADHD consumption channel (passive, mobile, no screen-pull). A 2-minute "here's what you've been circling" you can hear on a walk is a genuinely novel surface none of the local-first tools offer. Caveat: Selene archived its TTS/voice stack in the 2026-03-21 simplification, so this is a *bet*, not a quick win — only worth it if a local TTS path stays simple.
- **Maps to:** would consume `topic_clusters.synthesis_text` from the synthesis design; new optional workflow.
- **Next step:** Park as a Vision idea. Revisit only after synthesis ships and only if a local TTS (e.g. an Ollama-adjacent or macOS `say`-grade path) keeps it to one small workflow. Do not rebuild the archived voice infrastructure for this.

### 8. Guard the calm — and treat "local" as the moat, not an apology

- **Who taught us:** MyMind (deliberately no folders, no social, no streaks — calm by design) vs. Numo (gamified streaks/guilt). Reor's "for high entropy people" positioning. The whole local-first cluster (Khoj, Reor) treating privacy as the headline.
- **Why it fits:** The ADHD market is full of guilt mechanics (streaks, gamification) that backfire for the exact users they target. MyMind's restraint is a feature. Separately: *every* ADHD-marketed competitor is cloud — our fully-local processing is the one thing none of them can cheaply copy. Lean into it as positioning, not as a compromise on model quality.
- **Maps to:** product principles in `.claude/ADHD_Principles.md`; informs any future framing/landing copy.
- **Next step:** Adopt two soft rules: (a) **no streaks, no guilt mechanics, ever** — resurfacing is an offer, never a "you missed 3 days"; (b) when describing Selene, lead with "your notes never leave your machine," which is true and unmatched in the ADHD category.

---

## Anti-patterns — deliberately *not* copying

| Pattern | Who does it | Why we skip it |
|--------|-------------|----------------|
| Always-on passive capture (screen/audio recording) | Limitless / Rewind | Violates intentional capture; surveillance-shaped; huge privacy + storage cost. Selene's value is curation, not total recall. |
| Gamification / streaks / guilt | Numo | Backfires for ADHD; contradicts the "calm" lesson (#8). |
| Manual-linking-first knowledge graph | Obsidian, Roam, Reflect (core), Tana | The whole reason Selene exists is to *not* make the user link/tag. Auto-organization is the thesis — don't dilute it. |
| Cloud LLM on note content | Saner, Mem, Fabric, Notion, Tana | Gives up our only un-copyable differentiator. |
| Feature sprawl / multi-app suites | (our own 2026-03-21 history) | The simplification cut 20k→3.5k lines for a reason. Each lesson above must clear the "does this add cognitive overhead to *run*?" bar. |

---

## Quick wins vs. bigger bets

| Lesson | Effort | Verdict |
|--------|--------|---------|
| #1 Agentic digest lead line | Small | **Do soon** — one prompt change to `send-digest.ts`. |
| #2 Spaced resurfacing into digest | Small | **Do with PKM browse layer** — piggybacks on existing surface. |
| #3 Related notes at capture | Small | **Do** — reuse worksheet retrieval path. |
| #4 Tensions/changes-of-mind in synthesis | Small | **Do as part of synthesis build** — one prompt addition. |
| #5 Task breakdown worksheet | Medium | **Prioritize within worksheets Phase 2.** |
| #6 Candidate tasks from notes | Medium | **Strong bet** — closes the loop, fits agent contract. |
| #7 Audio digest | Large | **Park** — depends on a simple local TTS; don't revive archived voice stack. |
| #8 Calm + local positioning | Trivial | **Adopt as principle now.** |

---

## Appendix — who's who (compressed)

| Tool | Closest to Selene on | Diverges on | Cloud/Local |
|------|----------------------|-------------|-------------|
| **Saner.ai** | Thesis: ADHD-first, capture→auto-sort, morning proactive scan | Inbox/task-centric; no deep synthesis | Cloud |
| **Mem (2.0)** | Mechanics: auto-organize, Smart Collections clustering, daily digest | Not ADHD; weak handwriting/OCR | Cloud |
| **Khoj** | Local-first second brain; scheduled automation digests | No auto topic clustering/synthesis; not ADHD | Local (Ollama) |
| **Reor** | Architecture: Ollama + LanceDB + local embeddings + auto-link | On-demand only; no clustering/synthesis/digest | Local |
| **Reflect** | Proactive spaced-repetition resurfacing | Manual-linking core | Cloud (E2E) |
| **NotebookLM** | Cross-source synthesis, finds contradictions, audio overview | Project-scoped, reactive, cloud | Cloud |
| **MyMind** | Auto-tag everything, calm/no-pressure, privacy posture | No resurfacing push | Cloud |
| **Goblin Tools** | Task breakdown (the ADHD primitive) | Single utility, no note store | Cloud |
| Obsidian plugins (Smart Connections, Copilot, Smart Second Brain) | Local RAG/related-notes over a vault | Reactive; no synthesis/clustering; manual vault | Local option |
| Tiimo / Numo / Inflow / Llama Life | ADHD marketing | Task/time-management, not knowledge | Cloud |

**The unoccupied intersection (Selene's white space):** ADHD-first **+** fully local **+** automatic
clustering→narrative synthesis **+** proactive digest **+** multimodal (handwriting/e-ink/voice) capture.
The closest single rivals are Saner.ai (same thesis, opposite on privacy) and Mem (same mechanics, cloud);
Khoj/Reor prove the local stack is viable but stop at reactive search.

---

## Confidence & sourcing

Gathered via web research on 2026-05-28. Product-feature specifics — especially Mem 2.0's
exact feature set, Khoj's automation capabilities, NotebookLM's audio feature, and the
reported Limitless/Rewind→Meta acquisition — are **research-grade**: directionally reliable but
worth a manual check before any are quoted externally or used to justify a build decision.

---

## Related

- `docs/plans/2026-05-26-synthesis-retrieval-agent-design.md` — lessons #1, #4 land here
- `docs/plans/2026-04-12-pkm-browse-layer-design.md` — lesson #2 (spaced resurfacing) lands here
- `docs/plans/2026-05-26-interactive-worksheets-design.md` — lesson #5 (task breakdown) lands here
- `docs/plans/2026-03-21-close-the-loop-design.md` — lesson #6 (candidate tasks) revives this idea against the agent layer
- `.claude/ADHD_Principles.md` — lessons #2, #8
