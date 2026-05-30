# Design: Dev/Prod boundary hardening — showcase corpus + Claude-out-of-prod guard

**Date:** 2026-05-29
**Status:** Vision → **Ready** (acceptance criteria + ADHD check + scope check below)
**Builds on:** [2026-05-28-prod-dev-split-design.md](2026-05-28-prod-dev-split-design.md) (the two-tier split, already SHIPPED)
**Related:** [[project_prod_dev_split]], [[project_lumen]] (prod stays the oracle)

---

## What & why

Selene already runs a **two-tier split** (live since PR #45): `~/selene` = dev sandbox
(fictitious data, ts-node, :5679, no scheduled agents) → merge to `main` → a launchd
deploy-watcher build-gates and auto-deploys to `~/selene-prod` (compiled `dist/`, **real**
data, iCloud vault, :5678, autonomous `com.selene.prod.*` agents).

This design does **not** rebuild that. We considered inserting a third "test on real data"
tier and **explicitly rejected it** (see Decisions). Two tiers is the right shape. What's
missing is what makes the existing two-tier *trustworthy*, and there are exactly two gaps:

- **A. The showcase corpus** — dev's fictitious dataset is the *only* thing that gates a
  feature before it reaches autonomous prod (the deploy-watcher only checks "does `tsc`
  compile"). Today that corpus is random fragment-soup, so passing on it predicts little.
  Make it a **designed corpus** that both *showcases* features (happy path looks great) and
  *gates* behavior (pathologies are present). This is the real lift.

- **B. The Claude-out-of-prod guard** — "minimal to no Claude interaction with prod" is
  currently a *convention*, and in fact the opposite of enforced: `settings.local.json`
  carries accumulated **allow-rules that explicitly grant Claude read access to real notes**
  (e.g. `SELENE_ENV=production sqlite3 ~/selene-data/selene.db "SELECT … content …"`, many
  `Read(~/selene-data/**)`). Make the boundary an enforced **guardrail**. Small, mechanical.

The two workstreams **do not gate each other** — B can ship in an afternoon while A iterates.

---

## Decisions (settled during brainstorming, 2026-05-29)

| Decision | Choice | Why |
|---|---|---|
| Add a third "test on real data" tier? | **No** — stay two-tier | A standing third env cuts against the deliberate ~20k→3.5k simplification; a real-data copy reintroduces write-back risk to the daily-driver + vault. |
| Where does real data live? | **Prod only** | Dev/test never touch real notes; keeps Claude's iteration off sensitive journal content (privacy boundary) and keeps prod clean as Lumen's oracle. |
| What does dev run on? | **One curated fictitious corpus** | Serves both develop-with and showcase purposes; no PII; deterministic. |
| Automated ground-truth assertion harness for the corpus? | **No (deferred, opt-in later)** | Pipeline runs Ollama at temp 0.8 → clusters/concepts/essences are non-deterministic, so any check is fuzzy/structural at best. Eyeball the output now; add a fuzzy harness later only if eyeballing proves too slow. |

---

## Workstream A — The showcase corpus (core lift)

### Current state (verified 2026-05-29)
`scripts/generate-dev-fixture.py` emits 500 notes by randomly recombining ~5 sentence
fragments across 5 note-kinds (project_idea / reflection / reading / task / meeting), titled
`Idea #N` etc. It optimizes for **volume**, not coverage. Limitations as a behavior gate:
- **No embedded structure** — no notion that "these N notes are one coherent project," so
  clustering / synthesis / `note_connections` have no *true* shape to produce.
- **Not adversarial** — no multi-topic monster notes (the eink-mega-bucket pathology), no
  near-duplicates, no length extremes.
- **Low lexical diversity** — ~12 projects / 15 topics recombined → embeddings collapse into
  artificially-tight clusters that don't resemble real-data messiness.
- **No feature-coverage intent** — it's a pile, not a tour of every feature.

### Target
Evolve `generate-dev-fixture.py` from random recombination to **designed scenarios layered on
top of the existing volume**. Both purposes served at once:

- **Showcase (happy path looks great):** a few **coherent project threads** (~10–15 notes each
  that *should* cluster together) so the constellation / clustering / synthesis / digest demos
  read like a real, legible knowledge base.
- **Gate (pathologies present):**
  - One or two deliberate **multi-topic monster notes** (the eink-mega-bucket case) to prove
    the content-clustering fix holds.
  - A handful of **near-duplicate pairs** so associations / `note_connections` have something
    true to find.
  - **Length extremes** (one-liners + long brain-dumps).
  - **Full category coverage** — every one of the 8 controlled categories represented.
  - Higher lexical diversity so embeddings don't collapse artificially.

Stays deterministic (seeded), zero real PII, feeds the **same** existing path:
`generate-dev-fixture.py` → `seed-dev-data.ts` (env-marker safety guard unchanged) →
`dev-process-batch.sh`. No schema change. No new infra.

### Explicitly out of scope (deferred)
The automated assertion harness ("assert the ~12 thread notes actually clustered"). If built
later it must be **fuzzy/structural** (temp 0.8 → non-deterministic), and should reuse the
Lumen parity taxonomy (pure-exact / single-pass-exact-on-sample / accumulated-fuzzy) rather
than reinvent it.

---

## Workstream B — The Claude-out-of-prod guard (small, mechanical)

### Principle
Block **prod *data*** (real notes), not **prod *operations*** (deploy / rollback / install /
log-tail / health). "Minimal to no interaction" is a **privacy guardrail that makes the safe
path the default — not an unbreakable wall.** A blanket block would wall Claude out of the
documented prod-down recovery procedure ([[project_prod_dev_split]]).

### Three mechanisms
1. **`permissions.deny` block** for the real-note surfaces — `Read`/`Edit`/`Write` on
   `~/selene-data/selene.db` and the iCloud vault path. `deny` takes precedence over `allow`,
   so this is the real teeth (vs. merely deleting allow-rules).
2. **PreToolUse Bash hook (`exit 2`)** that blocks *any Bash command referencing the prod data
   paths* — because the existing `Edit|Write` matcher does not touch Bash at all, which is
   exactly how the `sqlite3 … SELECT content` path stays open. Block **by path, not by parsing
   SQL** (distinguishing a row-count from a content-read is fragile; path matching is robust).
3. **Neutralize the explicit grants** already in `settings.local.json` (the
   `production sqlite3 … SELECT content` rule, the `Read(~/selene-data/**)` rules) — otherwise
   they keep handing Claude access regardless of the deny block.

### Two safety details (must be in the plan)
- **The substring trap:** prod is `~/selene-data/`; dev is `~/selene-data-**dev**/`. The
  discriminator MUST be precise (trailing-slash / path-boundary anchored) or the guard blocks
  every dev workflow too. `selene-data/` is not a substring of `selene-data-dev/…` — that
  boundary is load-bearing.
- **Operational allowlist + deliberate override:** deploy / rollback / install-prod /
  log-tail / health-check stay permitted, and there is a documented way for the *user* to lift
  the guard when a real incident requires it.

---

## Acceptance criteria

**A — Corpus**
- [ ] `generate-dev-fixture.py` produces a corpus containing: ≥2 coherent multi-note project
  threads, ≥1 multi-topic monster note, ≥1 near-duplicate pair, length extremes, and at least
  one note in each of the 8 controlled categories — while remaining deterministic and PII-free.
- [ ] After `reset-dev-data.sh` + `dev-process-batch.sh`, the dev vault/clusters are legible
  enough to *show* (happy-path threads cluster sensibly) AND surface the pathologies (the
  monster note exercises multi-membership clustering; near-dup pairs appear as connections).
- [ ] No production code path or schema changes; same generate→seed→process pipeline.

**B — Boundary**
- [ ] A Bash command reading real note content (`sqlite3 ~/selene-data/selene.db "SELECT
  content…"`, reading vault note files) is **denied** by the guard.
- [ ] Dev workflows against `~/selene-data-dev/` are **unaffected** (substring trap handled).
- [ ] Operational scripts (`deploy-prod.sh`, `rollback-prod.sh`, `install-prod.sh`, log tails,
  `/health`) still run; a documented override exists for incident recovery.
- [ ] The permissive real-data allow-rules in `settings.local.json` are removed/neutralized.

**Wrap-up**
- [ ] User-facing? Largely a dev-workflow/safety change → note "no end-user-facing change" OR,
  if the dev/showcase corpus is something the operator interacts with, add a short note to the
  releases/dev-environment guide. Decide at `docs` stage.

## ADHD check
- **Reduces friction:** ✅ a trustworthy dev gate means less anxiety about what auto-deploys to
  the daily-driver; the guard removes the "did I just let Claude read my journal" worry.
- **Externalizes / visible:** ✅ the showcase corpus makes "is the pipeline behaving" visible on
  safe data instead of held in the operator's head.
- **Realistic over idealistic:** ✅ rejected the heavier third-tier; shipped the smallest thing
  that closes the real gaps.

## Scope check
- Both workstreams < 1 week; B is hours. No new always-on infra, no new model/service.
- A reuses the existing fixture→seed→batch pipeline; B is settings/hook edits.

---

## Open questions (carry into the plan)
1. **Corpus size/shape balance:** how many designed-thread notes vs. background volume keeps
   both the showcase *and* the gate honest without bloating processing time in dev?
2. **Exact prod paths to guard:** confirm the canonical real-data paths — `~/selene-data/selene.db`,
   the iCloud vault path (`SELENE_VAULT_PATH`), digests, `eink/` — and which operational scripts
   must stay allowlisted.
3. **Override mechanism:** what's the cleanest deliberate-override for incident recovery (a
   documented temporary settings edit? an env flag the hook respects?).
4. **`settings.local.json` cleanup blast radius:** verify removing the prod-read allows doesn't
   break a dev script that legitimately shares a path prefix.

---

## Refinement — content-aware boundary (2026-05-29, post-review)

**Trigger:** during the roadmap review the operator clarified the boundary they actually want:

> "I recognize value in Claude being able to see that new columns are added correctly, do
> aggregated status, check for completeness, etc — but I don't love actual notes going into it."

That is a **content-vs-structure** line *inside the same prod DB path*, which collides with
Workstream B mechanism 2 as originally written ("block **by path, not by parsing SQL**").
A pure path-block is all-or-nothing: it would also kill the `.schema` / `PRAGMA` / `COUNT` /
`GROUP BY` / coverage checks the operator wants to keep. But teaching the hook to tell a
content-`SELECT` from a row-count by parsing arbitrary SQL is exactly the fragility the
original design rejected — and rightly so.

### Resolution: keep the robust path-block, add ONE sanctioned read-only hole

Do **not** parse SQL. Instead:

1. **Raw prod access stays path-blocked** — ad-hoc `sqlite3`/`ts-node`/`node -e`/`cat`/`grep`
   against `~/selene-data/…` (and the vault) is denied, unconditionally, by path. Robust.
2. **Add `scripts/selene-inspect.ts`** — a read-only inspector that is the *only* sanctioned way
   to look at the prod DB, and is **allowlisted** by exact command. Its design invariant is
   structural: it has **no code path that projects a content-bearing column** (`content`,
   `title`, `essence`, `transcript`, `summary`, raw note text). Every query it can run returns
   only schema, counts, distributions, or coverage numbers. So "no note text reaches Claude's
   context" is guaranteed by the *tool's surface area*, not by inspecting each command.

This gives the operator exactly the three uses they named, with note text provably fenced out:

| Operator need | `selene-inspect` subcommand | Returns (never content) |
|---|---|---|
| "new columns added correctly" | `schema [table]` | `PRAGMA table_info` / `.schema` — column names, types, nullability |
| "aggregated status" | `counts` | row counts per table; processed vs. unprocessed; per-category counts |
| "check for completeness" | `coverage` | # notes missing category / essence / embedding; cluster + multi-membership stats; test_run leakage |

### Guard logic (still "deny by path", with an allowlist)
A PreToolUse **Bash** hook denies (`exit 2`) any command that references a prod-data path
**unless** it matches the allowlist:
- `scripts/selene-inspect.ts` (the sanctioned read-only inspector)
- operational scripts: `deploy-prod.sh`, `rollback-prod.sh`, `install-prod.sh`,
  `deploy-watch.sh`, `install-launchd.sh`, `uninstall-launchd.sh`
- file-level snapshot ops that move bytes without surfacing them to Claude
  (`sqlite3 … ".backup …"`, `cp` of the DB file) — content never enters context
- the clustering rollout scripts (`backfill-categories.ts`, the one-shot synthesis rebuild)
- health/log: `curl …/health`, `tail`/`log show` on prod logs

**Substring trap (load-bearing):** the discriminator matches `selene-data/` (prod) and must
**exclude** `selene-data-dev/` (dev). `selene-data/` is *not* a substring of `selene-data-dev/`
(the char after `data` is `-`, not `/`) — anchor on that boundary.

**Override for incident recovery:** the hook respects an env escape hatch
(`SELENE_GUARD_OFF=1`) so the operator can deliberately lift it during a documented prod-down
procedure; absent that var, the guard is always on. Documented in the releases guide.

### Acceptance criteria (supersede/extend Workstream B's)
- [ ] `sqlite3 ~/selene-data/selene.db "SELECT content …"` → **denied**.
- [ ] `npx ts-node scripts/selene-inspect.ts coverage` → **allowed**, prints only counts/coverage.
- [ ] `selene-inspect` has no branch that selects a content column (asserted by a unit test).
- [ ] Dev DB (`~/selene-data-dev/…`) commands → **unaffected**.
- [ ] Operational + rollout + snapshot scripts → **allowed**; `SELENE_GUARD_OFF=1` lifts the guard.
- [ ] Permissive prod-read allow-rules removed from `settings.local.json`; `permissions.deny`
      added to `settings.json` for `Read`/`Edit`/`Write` on the prod DB + vault.
