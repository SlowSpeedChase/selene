# Development Playbook

> A reusable, project-agnostic development process — extracted from the Selene project and
> generalized so you can drop it into any new repo. It is built for a **human + AI-agent pair**
> working in [Claude Code](https://claude.com/claude-code), but the structure works with any
> AI coding assistant (swap the tool-specific bits noted with `‹tool-specific›`).

**How to read this:** Sections 1–2 are the *why* (read once). Sections 3–8 are the *how* (the
operating system). Section 9 is **copy-paste templates** — that's what you actually deploy.

---

## 0. The core bet (read this first)

This whole process exists to solve **one problem**: a human + AI pair cannot hold the full state
of a project in their heads — and the AI's context window is small and resets every session. So
instead of relying on memory, **we externalize state into files**: what we're building, why,
which stage it's in, what's left, and what we learned.

Every rule below is downstream of that bet. If a practice doesn't make project state *more
visible and durable*, drop it. If it does, keep it even when it feels like overhead — the overhead
is the point.

---

## 1. Setup checklist for a new project

Do this once, when starting a new repo. Each item maps to a layer explained later.

- [ ] **Create the single entry-point file** — `CLAUDE.md` at the repo root (§3). This is the
      first thing your AI assistant reads. ‹tool-specific: the filename `CLAUDE.md` is what Claude
      Code auto-loads; other tools use `.cursorrules`, `AGENTS.md`, `GEMINI.md`, etc.›
- [ ] **Create the design-doc index** — `docs/plans/INDEX.md` with four sections:
      `Vision`, `Ready`, `In Progress`, `Done` (§4).
- [ ] **Create the templates folder** — copy the three templates from §9 into `templates/`:
      `DESIGN-DOC-TEMPLATE.md`, `BRANCH-STATUS.md`, and a `_GUIDE-TEMPLATE.md` if you write user guides.
- [ ] **Create the archive folder** — `docs/completed/` (closure summaries land here, §7).
- [ ] **Create a status file** — `.claude/PROJECT-STATUS.md` (the one living "current state" doc, §3).
- [ ] **Define your project-fit check** — replace the `‹project-fit check›` placeholder (§4.2) with
      2–4 questions every feature must pass. (Selene used ADHD-design questions; yours will differ.)
- [ ] **Decide your AI-skill mapping** — fill in the stage→discipline table (§6) for whatever
      assistant you use.
- [ ] **Set commit/PR conventions** — adopt the format in §9.4.

When all boxes are checked, the project has a working "operating system" and you can start feature work.

---

## 2. The five principles

| Principle | What it means | Why it matters |
|-----------|---------------|----------------|
| **Visibility** | All work state lives in files, never only in a chat or someone's head. | The AI resets every session; the next session reads the files and resumes. |
| **Isolation** | Each piece of work gets its own branch/worktree. | Parallel work never collides; an abandoned experiment is one `rm` away. |
| **Checkpoints** | Work moves through explicit stages with checklists. | "Done" is defined, not vibed. Nothing ships half-finished. |
| **Traceability** | Idea → design doc → branch → archive summary form an unbroken chain. | Six months later you can answer "why does this exist?" from the repo alone. |
| **Currency** | Branches rebase on the main branch frequently. | Small frequent rebases are painless; large ones cause merge hell. |

---

## 3. Layer 0 — Context architecture (the entry-point file)

The single most important file is the one your AI reads first. Its job is **not** to contain all
knowledge — it's to be a **map** that says "load X only when you're doing Y." A bloated entry-point
file wastes the AI's limited context on every session.

### 3.1 Structure of the entry-point file (`CLAUDE.md`)

```
# ‹Project Name› Context

> This is THE single entry point. The AI loads this automatically.

## Purpose
‹One paragraph: what this project is and who it's for.›

## Tech Stack
‹Bullet list: languages, frameworks, datastores, external services.›

## Context Navigation        ← the heart of the file
| Task | Primary Context | Supporting Context |
|------|-----------------|--------------------|
| Modify a workflow | @src/workflows/ | @.claude/OPERATIONS.md |
| Plan new work | @docs/plans/INDEX.md | @‹this playbook› |
| Run tests | @.claude/OPERATIONS.md | — |
| ‹task› | @‹file to load› | @‹supporting file› |

## Critical Rules (Do NOT)
‹The non-negotiables: "never commit .env", "never use `any` type",
 "always use parameterized SQL", "never test against the prod database".›

## Quick Command Reference
‹The 5–10 commands you run constantly: build, test, run server, query DB.›
```

### 3.2 The supporting `.claude/` files

Split detail out of the entry-point into purpose-specific files the navigation table points to:

| File | Holds |
|------|-------|
| `.claude/OPERATIONS.md` | Commands, testing procedures, debugging, daily checklist |
| `.claude/DEVELOPMENT.md` | Architecture decisions, patterns, the "why" of the design |
| `.claude/PROJECT-STATUS.md` | **The** living "current state" doc — updated every session |
| `.claude/GITOPS.md` | The branch workflow (i.e. §4–7 of this playbook, project-specific) |

**Rule:** there is exactly **one** living status file (`PROJECT-STATUS.md`). Never create
`FEATURE_COMPLETE.md` / `THING_STATUS.md` scatter files — they rot and contradict each other.

---

## 4. Layer 1 — Design docs (the planning layer)

Before any code, an idea becomes a **design doc** that moves through four states. The index file
`docs/plans/INDEX.md` lists every doc under its current state.

```
Vision  →  Ready  →  In Progress  →  Done
```

- **Vision** — a rough idea, captured so it isn't lost. No commitment.
- **Ready** — passed the readiness gate (§4.2). Eligible to start.
- **In Progress** — has an active branch.
- **Done** — merged; an archive summary exists in `docs/completed/`.

### 4.1 Why a planning layer at all?

It separates *deciding what to build* from *building it*. The AI is excellent at implementation but
will happily build the wrong thing fast. The design doc is the cheap place to be wrong. (This is
where a **brainstorming** discipline lives — explore intent and approaches *before* touching code.
‹tool-specific: Claude Code's `superpowers:brainstorming` skill.›)

### 4.2 The "Ready" gate

A design doc is **Ready** only when all of these are checked:

- [ ] **Acceptance criteria defined** — how you'll know it works.
- [ ] **`‹project-fit check›`** — 2–4 project-specific questions every feature must answer.
      *Selene used: "Does it reduce friction? Is it visible? Does it externalize cognition?" (an
      ADHD-design lens). Replace with whatever your project's north star is — e.g. "Does it improve
      p95 latency? Is it accessible? Does it have an audit trail?"*
- [ ] **Scope check** — fits in roughly **one week** of focused work. Bigger → split it.
- [ ] **No blockers** — dependencies identified and available.

### 4.3 Design-doc filename convention

`docs/plans/YYYY-MM-DD-‹topic›-design.md` — date-prefixed so the folder sorts chronologically.
(Template in §9.1.)

---

## 5. Layer 2 — GitOps branches (the implementation layer)

When a design doc is Ready, it gets a branch. Each branch carries a **`BRANCH-STATUS.md`** file —
its visible state — and moves through six stages.

### 5.1 Isolation via worktrees

```bash
# One isolated working copy per feature — your main checkout stays clean
git worktree add -b ‹feature-name› .worktrees/‹feature-name› main
cd .worktrees/‹feature-name›
cp ../../templates/BRANCH-STATUS.md ./BRANCH-STATUS.md
```

Worktrees (vs. plain branches) let the human and AI keep multiple features physically separate on
disk — no stashing, no "wait, which branch am I on?". Abandoning an experiment is
`git worktree remove`.

### 5.2 The six stages

| Stage | Purpose | Key checklist items |
|-------|---------|---------------------|
| **planning** | Finalize approach | Design approved, implementation plan written |
| **dev** | Build it | Tests first, core implementation, no type/lint errors |
| **testing** | Verify it works | All tests pass, manual test, edge cases |
| **docs** | Document it | Status/index updated, user guide written if user-facing |
| **review** | Get approval | Code reviewed, feedback addressed |
| **ready** | Prepare to merge | Rebased, final tests, all boxes checked |

Move to the next stage only when **every** box in the current one is checked. On transition:
update `Current Stage:` in `BRANCH-STATUS.md` and commit `checkpoint: ‹stage› complete`.

### 5.3 Working through a checklist (the loop)

For each unchecked item, the AI: (1) states what the item requires, (2) offers to do it, (3) does
it, (4) marks complete **only when actually done** — never pre-checks. Blocked items get a
`BLOCKED: ‹reason›` prefix and move to a "Blocked" section so they stay visible.

### 5.4 Rebase strategy (Currency in practice)

Rebase **before** starting a session, **after** any other branch merges, and before the `review`
and `ready` stages.

```bash
git fetch origin
git rebase origin/main
# resolve conflicts → git add ‹files› → git rebase --continue
```

**Session-start ritual (mandatory):** before *any* work on a branch, check divergence and offer to
rebase if behind:

```bash
git fetch origin
BEHIND=$(git rev-list --count HEAD..origin/main)
# If BEHIND > 0: "Main has $BEHIND new commits. Rebase now before continuing?"
```

---

## 6. Skill-gated stages (enforcing discipline)

Each stage **requires** a specific discipline before the AI starts that stage's work. This is what
keeps quality from being optional. With Claude Code + Superpowers these are literal skills; with any
other assistant, treat them as checklists the AI must follow.

| Stage | Discipline to invoke | ‹tool-specific: Superpowers skill› |
|-------|----------------------|------------------------------------|
| planning | Brainstorm intent, then write a step-by-step plan | `brainstorming`, `writing-plans` |
| dev | Test-driven development; split independent work to subagents | `test-driven-development`, `subagent-driven-development` |
| testing | Systematic debugging; verify with evidence before claiming done | `systematic-debugging`, `verification-before-completion` |
| review | Request review, then receive feedback rigorously (verify, don't rubber-stamp) | `requesting-code-review`, `receiving-code-review` |
| ready | Finish-the-branch ritual (merge/PR/cleanup decision) | `finishing-a-development-branch` |

**The principle that survives tool swaps:** *no stage is "done" on assertion alone — it's done when
the discipline for that stage has been run and produced evidence.* "Tests pass" means you ran them
and saw green, pasted into the record — not that you believe they would.

---

## 7. Closure ritual (the chain stays unbroken)

A feature isn't done at merge — it's done when its trail is complete. Run every step:

```bash
# Step 1 — Merge
git checkout main && git pull origin main
git merge ‹feature-name›            # or merge a reviewed PR on the host
# (To squash into one commit instead: git merge --squash ‹feature-name›
#  then git commit, which is required before the push below.)
git push origin main
```

- **Step 2 — Archive summary:** create `docs/completed/YYYY-MM-DD-‹feature-name›.md` with: summary,
  key changes, link back to the design doc, and **lessons learned** (what was harder than expected —
  this is the highest-value field).
- **Step 3 — Index:** move the design doc from `In Progress` → `Done` in `docs/plans/INDEX.md`.
- **Step 4 — Status:** update `.claude/PROJECT-STATUS.md`.
- **Step 5 — Cleanup:** `git worktree remove .worktrees/‹feature-name›`.

### Post-merge verification checklist (the AI must confirm all before announcing "done")

- [ ] Archive summary exists in `docs/completed/`
- [ ] Design doc moved to `Done` in the index
- [ ] `PROJECT-STATUS.md` updated
- [ ] Worktree removed
- [ ] No stray `BRANCH-STATUS.md` left in the main checkout (`ls BRANCH-STATUS.md` should fail)
- [ ] No orphaned files in the repo root

---

## 8. Supporting disciplines

These aren't stages — they're standing rules that keep the system from rotting.

### 8.1 Documentation drift prevention
Before changing how any documented process works, **find every reference first**, then update or
delete *all* of them — never leave the old pattern documented beside the new one:
```bash
grep -r "‹old-pattern-name›" docs/ .claude/
```

### 8.2 User guides per user-facing capability
If a feature changes something a user *interacts with*, it gets/updates a guide in
`docs/guides/features/‹capability›.md`, linked from a single hub page. Invisible
refactors note "no user-facing change" and skip it. **Write guides against the real code, not the
design doc** — design docs go stale; the code is truth.

### 8.3 Persistent AI memory
Durable facts that aren't in the code — user preferences, why a non-obvious decision was made,
active design state, gotchas — go in a persistent memory store the AI loads each session
(‹tool-specific: Claude Code's per-project `memory/` + `MEMORY.md` index›). **Don't** memorize what
the repo already records (file structure, git history, past fixes). One fact per memory; link
related ones. When a memory turns out wrong, delete it.

### 8.4 The "no scatter-status-files" rule
One living status doc (`PROJECT-STATUS.md`), one design index (`docs/plans/INDEX.md`), one archive
(`docs/completed/`). Never spawn `*_COMPLETE.md` / `*_STATUS.md` files — they multiply and contradict.

---

## 9. Copy-paste templates

### 9.1 `templates/DESIGN-DOC-TEMPLATE.md`

```markdown
# ‹Topic› Design

**Status:** Vision | Ready | In Progress | Done
**Created:** YYYY-MM-DD
**Updated:** YYYY-MM-DD

## Problem
What problem does this solve? Why does it matter?

## Solution
High-level approach. What are we building?

## Design
Architecture, components, data flow, key decisions.
(Consider 2–3 approaches with trade-offs and a recommendation.)

## Implementation Notes
Technical details, affected files, dependencies on other work.

## Ready for Implementation Checklist
Before creating a branch, all items must be checked:
- [ ] Acceptance criteria defined — how do we know it's done?
- [ ] ‹project-fit check› passed (see below)
- [ ] Scope check — ships in < 1 week of focused work?
- [ ] No blockers — dependencies resolved?

### Acceptance Criteria
- [ ] ‹observable outcome 1›
- [ ] ‹observable outcome 2›

### ‹Project-Fit Check›
‹2–4 questions every feature must answer. Selene used an ADHD-design lens:
 "Reduces friction? Visible? Externalizes cognition (system remembers, not user)?"
 Replace with your project's north star. If a feature fails all of them, reconsider it.›

## Links
- **Branch:** (added when implementation starts)
- **PR:** (added when complete)
```

### 9.2 `templates/BRANCH-STATUS.md`

```markdown
# Branch Status: ‹feature-name›

**Created:** YYYY-MM-DD
**Design Doc:** docs/plans/YYYY-MM-DD-‹topic›-design.md
**Current Stage:** planning
**Last Rebased:** YYYY-MM-DD

## Overview
Brief description of what this branch implements.

## Dependencies
- None | Waiting on ‹branch› | Requires ‹external thing›

## Stages

### Planning
- [ ] Design doc exists and approved
- [ ] Conflict check completed (no overlapping work)
- [ ] Dependencies identified and noted
- [ ] Branch and worktree created
- [ ] Implementation plan written

### Dev
- [ ] Tests written first
- [ ] Core implementation complete
- [ ] All tests passing
- [ ] No linting/type errors
- [ ] Code follows project patterns

### Testing
- [ ] Unit tests pass
- [ ] Integration tests pass (if applicable)
- [ ] Manual testing completed
- [ ] Edge cases verified

### Docs
- [ ] Status / index docs updated
- [ ] README updated (if interface changed)
- [ ] Code comments where needed
- [ ] User-facing change? If yes: feature guide created/updated + hub link added

### Review
- [ ] Requested review
- [ ] Review feedback addressed
- [ ] Changes approved

### Ready
- [ ] Rebased on latest main
- [ ] Final test pass after rebase
- [ ] BRANCH-STATUS.md fully checked
- [ ] Ready for merge

## Notes
Running notes, decisions, questions.

## Blocked Items
- [ ] BLOCKED: ‹item› — ‹reason›
```

### 9.3 `docs/plans/INDEX.md` skeleton

```markdown
# Design Docs Index

## Vision
- ‹idea› — docs/plans/YYYY-MM-DD-‹topic›-design.md

## Ready
- ‹topic› — docs/plans/YYYY-MM-DD-‹topic›-design.md

## In Progress
- ‹topic› — branch: ‹feature-name›

## Done
- ‹topic› — archived: docs/completed/YYYY-MM-DD-‹topic›.md
```

### 9.4 Commit & PR conventions

```
# Commit message
type(scope): description

[optional body]

# Types: feat | fix | docs | refactor | test | chore
# Scope: component name, or `docs`
# Examples:
#   feat(api): add task classification
#   fix(ui): resolve connection timeout
#   docs: update playbook with closure ritual
```

```markdown
## PR template
### Summary
- 1–3 bullets describing the change

### Changes
- Files/components changed; any breaking changes

### Test Plan
- [ ] Tests pass
- [ ] Manual verification done

### Design Doc
Link: docs/plans/YYYY-MM-DD-‹topic›-design.md
```

---

## 10. One-screen summary

```
IDEA
 └─ Design doc (Vision → Ready)            docs/plans/INDEX.md
     └─ Ready gate: criteria + project-fit + scope + no blockers
         └─ BRANCH (worktree, isolated)    .worktrees/‹name›
             └─ Stages, each gated by a discipline:
                planning → dev → testing → docs → review → ready
                (brainstorm) (TDD) (verify) (guides) (review) (finish)
                 ↑ rebase on main frequently the whole way through
                 └─ MERGE
                     └─ Closure: archive summary + index→Done
                        + status update + worktree removed + verified
                        └─ Lessons learned captured → AI memory
```

Everything above is downstream of one idea: **make project state durable and visible, because the
human+AI pair can't keep it in their heads.** Adapt the placeholders; keep the principle.
