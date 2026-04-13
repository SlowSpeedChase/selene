# Per-Stage Model Audit for Selene

**Status:** Brainstorming (WIP — paused mid-design)
**Date:** 2026-04-12
**Scope:** Weekend experiment, structured to grow into a reusable harness
**Motivation:** Curiosity-driven — no specific quality complaint, just asking whether better local models for specific stages are leaving wins on the table

---

## Context

Selene currently uses a single Ollama model (`mistral:7b`) for every LLM stage and `nomic-embed-text` for embeddings. The four LLM-using workflows in `src/workflows/` each consume a different input shape:

| Workflow | Input Shape | Task Character |
|----------|-------------|----------------|
| `process-llm.ts` | One raw note | Structured extraction (concepts, category, sentiment) |
| `distill-essences.ts` | One raw note (+ context) | Creative compression to one line |
| `export-obsidian.ts` | A cluster of notes | Synthesis / topic indexing / dashboard curation |
| `daily-summary.ts` | A day's worth of notes | Narrative synthesis |

These have genuinely different optimal-model profiles — structured output discipline, creative compression, and multi-note reasoning are not the same skill. Running one model across all four may be leaving quality on the table at one or more stages, but there's no evidence yet of *which* stage is weakest.

## Goal

Produce a short, decision-ready report that answers:

1. Which Selene stage has the biggest quality gap between `mistral:7b` and a reasonable local challenger?
2. How large is that gap relative to a cloud "quality ceiling" (Claude)?
3. Is any stage worth a permanent model swap?

Non-goals: shipping a production model swap this weekend, exhaustively benchmarking every Ollama model, building a CI-grade eval harness.

## Constraints (locked in)

- **Local-only for production.** Cloud models (Claude) are allowed *only* as a quality ceiling / LLM-as-judge reference — never as a production path.
- **Effort budget:** one weekend (~4–6 hours). Structured so the same files could grow into a reusable harness (Approach C) on a future weekend without rewrites.
- **Privacy:** real notes must not leak into committed code or reports. Selene notes contain personal working-memory content.

## Approach: Breadth-first discovery sweep (Approach B)

Run 2 models across all 4 stages with a small fixture sample. Rank by quality gap, then decide on a future deep-dive.

**Models to compare:**
- `mistral:7b` — current production baseline
- 1 strong local challenger — TBD, likely `qwen2.5:7b` or `llama3.1:8b`
- Claude (cloud) — quality ceiling / judge only, not production

**Stages to sweep:** all four (`process-llm`, `distill-essences`, `export-obsidian`, `daily-summary`).

**Sample size:** ~5 real notes per stage (20 total). Small enough to eyeball, large enough to notice patterns.

**Scoring:** Claude as LLM-as-judge, structured rubric TBD. Probably paired comparison per stage output with a short justification.

**Output:** Markdown report in `benchmark-results/2026-04-12/` with side-by-side outputs and a short recommendations section.

## Harness-Shaped Internals

To avoid throwaway work, the weekend-1 code should be structured so the same files grow into Approach C (ongoing harness) later. Expected layout (not yet finalized):

```
scripts/benchmark/
  run.ts              # Entry point: takes --stage, --models, --fixtures
  stages/             # One adapter per Selene workflow stage
  judges/             # Claude-as-judge + future human-rating
  fixtures/           # Loader — real (gitignored) or synthetic (committed)
  report.ts           # Markdown report writer
data/benchmark-fixtures/   # gitignored; real notes from data/selene.db
benchmark-results/YYYY-MM-DD/  # gitignored; generated reports
```

## Open Questions (picked up next session)

1. **Fixture strategy** — the hinge decision that was *not* resolved before pausing:
   - **Option 1:** Real notes, gitignored (`data/benchmark-fixtures/`). Fastest, realistic, private, but not shareable. **Currently recommended** as weekend-1 default.
   - **Option 2:** Synthetic-only, committed. Shareable + CI-friendly, but may not match real distribution.
   - **Option 3:** Real notes, Ollama-anonymized via a redactor prompt, committed. Shareable *and* realistic-ish, but redactor quality is its own failure surface.
2. **Challenger model** — `qwen2.5:7b` vs `llama3.1:8b` vs something else? Depends on what's already pulled in Ollama locally.
3. **Judge rubric** — paired comparison only, or multi-axis scoring (faithfulness, concision, structure compliance)?
4. **Stopping criterion** — explicit rule: "4 hours in, if signal is ambiguous, stop and write what I've got." Guards against scope creep on a curiosity-driven audit.
5. **Does an audit of `nomic-embed-text` (embeddings) belong in scope, or is that a separate effort?** Currently out of scope for weekend 1.

## Decisions So Far

- ✅ Motivation: curiosity-driven audit, not a fix for a known problem
- ✅ Cloud policy: reference ceiling only, never production
- ✅ Effort tier: weekend experiment with harness-shaped internals (not throwaway, not full harness upfront)
- ✅ Scope: all four LLM stages, breadth-first (Approach B)
- ⏸ Fixture strategy: paused at option 1 vs 2 vs 3
- ⏸ Challenger model selection: not yet decided
- ⏸ Scoring rubric: not yet designed
- ⏸ Success criteria + acceptance criteria: not yet written

## ADHD Check (Deferred)

Not yet evaluated — this is infrastructure work, not a user-facing feature. The ADHD question for this design is indirect: *does improving any stage meaningfully improve the user's working-memory externalization?* That's exactly what the audit is trying to find out.

## Scope Check (Deferred)

Needs explicit acceptance criteria before this can move to "Ready." Currently sized as a weekend, but with open questions 1–4 above unresolved, the true scope is uncertain.

---

**Resume instructions for future session:**
Pick up at Open Question 1 (fixture strategy). Once fixture strategy is locked, walk through the remaining design sections (rubric, challenger model, stopping criterion, acceptance criteria), then move to `writing-plans` per the brainstorming skill.
