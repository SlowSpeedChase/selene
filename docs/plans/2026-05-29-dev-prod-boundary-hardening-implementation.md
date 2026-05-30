# Dev/Prod Boundary Hardening — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Selene's already-live two-tier dev/prod split *trustworthy* by (A) turning the dev fixture into a designed showcase corpus that predicts prod behavior, and (B) enforcing the "Claude never reads real notes" boundary as a guardrail instead of a convention.

**Architecture:** Two **independent, non-gating** workstreams. Workstream A edits one Python generator (`scripts/generate-dev-fixture.py`) and its tests — no schema change, same `generate→seed→process` path. Workstream B adds a `permissions.deny` block + a PreToolUse **Bash** hook keyed on prod data paths, and neutralizes permissive allow-rules in `settings.local.json`. Either workstream can be done first.

**Tech Stack:** Python 3 (stdlib only, `unittest`), Bash hooks, Claude Code `settings.json`/`settings.local.json`, SQLite (verification queries only).

**Design doc:** [2026-05-29-dev-prod-boundary-hardening-design.md](2026-05-29-dev-prod-boundary-hardening-design.md)

**Execute in a worktree** (per GITOPS): `git worktree add -b feat/dev-prod-boundary-hardening .worktrees/dev-prod-boundary-hardening main` then `cp templates/BRANCH-STATUS.md .worktrees/dev-prod-boundary-hardening/`.

---

## Reference facts (verified 2026-05-29 — do not re-derive)

**The 8 controlled categories** (`src/lib/prompts.ts:1`, `CATEGORIES`):
`Personal Growth`, `Relationships & Social`, `Health & Body`, `Projects & Tech`, `Career & Work`, `Creativity & Expression`, `Politics & Society`, `Daily Systems`.
→ The generator cannot set these; the LLM assigns them in `process-llm.ts`. The corpus must **theme content** so the categorizer lands each one.

**Real prod data paths to guard** (`src/lib/config.ts`):
- DB: `~/selene-data/selene.db`
- Vectors: `~/selene-data/vectors.lance`
- E-ink (real OCR'd handwriting): `~/selene-data/eink/`
- Vault (real exported notes): `$SELENE_VAULT_PATH` → `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Selene/`

**The substring trap:** prod root is `~/selene-data/`; dev root is `~/selene-data-dev/`. The string `selene-data/` does **NOT** match inside `selene-data-dev/` (the char after `selene-data` is `-`, not `/`). The trailing slash is the load-bearing discriminator — **always require it**.

**Seed mechanics** (`scripts/seed-dev-data.ts`): runs `python3 generate-dev-fixture.py --count N`, inserts with `content_hash = sha256(title+content)` under `INSERT OR IGNORE`. **Consequence:** near-duplicate notes must be *similar but NOT byte-identical*, or the second silently drops as a hash collision.

**Offending allow-rules in `.claude/settings.local.json`** (grant Claude prod-read — to neutralize): lines **558** (`SELENE_ENV=production sqlite3 ~/selene-data/selene.db "SELECT … content …"`), **565–566** (`Read(~/selene-data/eink/**)`), **587–588, 595, 599** (`Read(~/selene-data/vault/**)`, `Read(~/selene-data/**)`), **597** (`rm -rf ~/selene-data/vault/`). Line numbers drift — match by content.

**Existing PreToolUse hook** (`.claude/settings.json:13-23`): matcher is `Edit|Write` only, greps `$CLAUDE_FILE_PATHS` for `.env`/`selene.db`. It does **not** cover Bash — that is the gap.

---

# Workstream A — The showcase corpus

Edits `scripts/generate-dev-fixture.py` to emit a **designed core** (project threads, a monster note, near-dup pairs, length extremes, one themed anchor per category) ahead of the existing random background volume. Deterministic, PII-free. New test file `scripts/test_generate_dev_fixture.py` (stdlib `unittest`, runs the script as a subprocess and asserts on the JSON contract — avoids the hyphenated-filename import problem).

### Task A1: Failing test for the designed-core contract

**Files:**
- Create: `scripts/test_generate_dev_fixture.py`

**Step 1: Write the failing test**

```python
"""Tests for the designed showcase corpus produced by generate-dev-fixture.py.

Runs the generator as a subprocess (the script's filename has hyphens and is not
importable) and asserts structural properties of the JSON contract. All checks are
structural, not exact-content, so they survive future vocabulary tweaks.
"""
import json
import subprocess
import unittest
from collections import Counter
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "generate-dev-fixture.py"

# The 8 controlled categories, each with a distinctive theme keyword the generator
# is required to seed at least one note around (mirrors src/lib/prompts.ts CATEGORIES).
CATEGORY_KEYWORDS = {
    "Personal Growth": "growth",
    "Relationships & Social": "friend",
    "Health & Body": "sleep",
    "Projects & Tech": "deploy",
    "Career & Work": "manager",
    "Creativity & Expression": "sketch",
    "Politics & Society": "community",
    "Daily Systems": "routine",
}


def run(count=500, seed=42):
    out = subprocess.run(
        ["python3", str(SCRIPT), "--count", str(count), "--seed", str(seed)],
        capture_output=True, text=True, check=True,
    )
    return json.loads(out.stdout)


class DesignedCorpusTest(unittest.TestCase):
    def setUp(self):
        self.notes = run()

    def test_shape_and_determinism(self):
        self.assertEqual(self.notes, run(), "generator must be deterministic")
        for n in self.notes:
            self.assertEqual(set(n), {"title", "content", "created_at"})

    def test_project_threads_present(self):
        # At least 2 distinct project names that each recur across >=8 notes => clusterable threads.
        tokens = Counter()
        for n in self.notes:
            for marker in ("Project Lighthouse", "Mossbank", "Quiet Garden"):
                if marker in n["content"]:
                    tokens[marker] += 1
        big = [m for m, c in tokens.items() if c >= 8]
        self.assertGreaterEqual(len(big), 2, f"need >=2 recurring threads, got {tokens}")

    def test_monster_note_present(self):
        # >=1 long note that name-drops >=3 distinct project/topic anchors (multi-topic).
        anchors = ("Project Lighthouse", "Mossbank", "Quiet Garden", "sleep", "manager")
        monsters = [n for n in self.notes
                    if len(n["content"].split()) >= 120
                    and sum(a in n["content"] for a in anchors) >= 3]
        self.assertGreaterEqual(len(monsters), 1, "need >=1 multi-topic monster note")

    def test_near_duplicate_pair_present(self):
        # >=1 pair with high word-overlap but NON-identical content (distinct hash).
        contents = [n["content"] for n in self.notes]
        found = False
        for i in range(len(contents)):
            for j in range(i + 1, len(contents)):
                a, b = contents[i], contents[j]
                if a == b:
                    continue
                wa, wb = set(a.lower().split()), set(b.lower().split())
                jac = len(wa & wb) / max(1, len(wa | wb))
                if jac >= 0.6:
                    found = True
                    break
            if found:
                break
        self.assertTrue(found, "need >=1 near-duplicate (similar, not identical) pair")

    def test_length_extremes(self):
        lengths = [len(n["content"].split()) for n in self.notes]
        self.assertLessEqual(min(lengths), 4, "need a very short capture")
        self.assertGreaterEqual(max(lengths), 200, "need a long brain-dump")

    def test_category_theme_coverage(self):
        blob = " ".join(n["content"].lower() for n in self.notes)
        missing = [c for c, kw in CATEGORY_KEYWORDS.items() if kw.lower() not in blob]
        self.assertEqual(missing, [], f"every category needs a themed anchor; missing {missing}")


if __name__ == "__main__":
    unittest.main()
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/chaseeasterling/selene && python3 -m unittest scripts.test_generate_dev_fixture -v 2>&1 || python3 scripts/test_generate_dev_fixture.py -v`
Expected: FAIL — current generator has no threads/monster/near-dups/extremes/coverage, and rejects `--seed`? (it accepts `--seed`). Failures: `test_project_threads_present`, `test_monster_note_present`, `test_near_duplicate_pair_present`, `test_length_extremes`, `test_category_theme_coverage`.

**Step 3: Commit the failing test**

```bash
git add scripts/test_generate_dev_fixture.py
git commit -m "test(fixture): failing contract for designed showcase corpus"
```

---

### Task A2: Add the designed-core data tables to the generator

**Files:**
- Modify: `scripts/generate-dev-fixture.py` (add constants near the other vocabulary blocks, ~line 68)

**Step 1: Add designed-scenario vocabulary** — append after the `FEELINGS` list:

```python
# ---------------------------------------------------------------------------
# DESIGNED CORE — deliberate scenarios layered on top of the random background.
# Each thread uses a distinctive vocabulary so its notes cluster TOGETHER but
# SEPARATELY from the other threads (avoids the homogeneous-collapse failure).
# All invented; zero real PII.
# ---------------------------------------------------------------------------

# Three coherent project threads. (name, themed lines pool). ~12 notes each.
THREADS = {
    "Project Lighthouse": [  # creative writing app -> Creativity / Projects & Tech
        "Project Lighthouse: outlined the chapter-board feature so a scene never gets lost.",
        "Sketched the Project Lighthouse welcome screen — a calm lighthouse beam, nothing else.",
        "Project Lighthouse bug: the draft autosave dropped a paragraph. Fixed the debounce.",
        "Wrote the Project Lighthouse tagline: 'a quiet place to finish the story.'",
        "Project Lighthouse: shipped the ugly first export-to-markdown. Perfect is the enemy of started.",
    ],
    "the Mossbank rewrite": [  # backend refactor -> Projects & Tech / Career & Work
        "The Mossbank rewrite: split the monolith ingest into three small deploy-able services.",
        "Mossbank rewrite stand-up: my manager unblocked the schema migration. Owner is me.",
        "The Mossbank rewrite finally deploys green. Two weeks of flaky tests, gone.",
        "Mossbank rewrite: wrote the rollback runbook so a bad deploy never takes prod down.",
        "Mossbank rewrite retro: shorter loops, fewer status updates, more shipping.",
    ],
    "Operation Quiet Garden": [  # wellness habit -> Health & Body / Daily Systems
        "Operation Quiet Garden: a morning routine that protects sleep — no screens till coffee.",
        "Quiet Garden day 4: the wind-down routine actually helped my sleep last night.",
        "Operation Quiet Garden: stacked a short walk onto the after-lunch slump. Habit stacking works.",
        "Quiet Garden: skipped the routine, slept badly. The system only works when I run it.",
        "Operation Quiet Garden review: energy is steadier when the daily routine survives the week.",
    ],
}

# One themed anchor note per category so the LLM categorizer lands all 8.
# Keyword in each line matches CATEGORY_KEYWORDS in the test.
CATEGORY_ANCHORS = {
    "Personal Growth": "Slow personal growth note: I keep learning that rest is part of the work, not a reward for it.",
    "Relationships & Social": "Reached out to an old friend today. Friendship needs maintenance like anything else.",
    "Health & Body": "Body check-in: better sleep, fewer headaches when I stop doom-scrolling before bed.",
    "Projects & Tech": "Tinkered with a home-lab side project; got the nightly backup to deploy cleanly.",
    "Career & Work": "Career thought: asked my manager for a clearer scope instead of guessing. Less anxiety.",
    "Creativity & Expression": "Did a loose sketch of the harbor at dusk — no goal, just expression.",
    "Politics & Society": "Went to a local community meeting about the library budget. Showing up is a small civic muscle.",
    "Daily Systems": "Tuned my weekly-review routine: three columns, now/next/not-yet, keep not-yet out of sight.",
}
```

**Step 2: Commit**

```bash
git add scripts/generate-dev-fixture.py
git commit -m "feat(fixture): add designed-core vocabulary (threads, anchors)"
```

(No test run — pure data addition; behavior wired in A3.)

---

### Task A3: Wire the designed core into `generate()`

**Files:**
- Modify: `scripts/generate-dev-fixture.py` — `generate()` (~lines 157-173) and add helpers above it.

**Step 1: Add builder helpers** above `def generate(`:

```python
def _spread_dates(rng, start, span_seconds, n):
    """n chronological timestamps inside the window."""
    offs = sorted(rng.randint(0, span_seconds) for _ in range(n))
    return [start + timedelta(seconds=o) for o in offs]


def _designed_notes(rng, start, span_seconds):
    """The deliberate core: threads, a monster note, near-dup pairs, extremes,
    and one themed anchor per category. Returns a list of note dicts."""
    notes = []

    # 1) Project threads — ~10-12 notes each so they form coherent clusters.
    for name, lines in THREADS.items():
        dates = _spread_dates(rng, start, span_seconds, 11)
        for k, when in enumerate(dates):
            body = rng.choice(lines)
            # light variation so the 11 notes aren't identical (distinct hashes)
            tail = rng.choice(["", " Logged for continuity.", " Small next step noted.",
                               " Parking this so I stop holding it in my head."])
            notes.append({"title": f"{name} — log {k + 1}",
                          "content": body + tail,
                          "created_at": when.isoformat()})

    # 2) Monster note — one long brain-dump mixing >=3 threads/topics (eink-mega-bucket case).
    monster = (
        "Brain dump, everything at once: the Mossbank rewrite deploy is green but I'm "
        "anxious about my manager's review on Thursday and I keep rehearsing it instead of "
        "preparing it. Meanwhile Project Lighthouse needs the export feature and I keep "
        "avoiding it because starting feels heavier than the work actually is. Body's tired "
        "— bad sleep again three nights running, and Operation Quiet Garden routine slipped "
        "twice this week so the evenings turned into screens and snacks. Also the local "
        "community library budget meeting is tomorrow and I said I'd show up. Too many tabs "
        "open in my head right now; I'm writing them all down so they stop circling at 2am. "
        "If I only do three things today: ship the ugly Lighthouse export, protect tonight's "
        "sleep routine no matter what, and prep two honest manager talking points. "
        "Everything else is genuinely not-yet, and pretending otherwise is how I end up "
        "doing none of it. Smallest next step for each, then stop."
    )  # ~140 words; multi-topic on purpose (the eink-mega-bucket pathology).
    notes.append({"title": "Everything at once (brain dump)",
                  "content": monster,
                  "created_at": (start + timedelta(seconds=span_seconds // 2)).isoformat()})

    # 3) Near-duplicate pair — same realization, two-word swap. Designed for Jaccard ~0.85
    #    (>= the test's 0.6) so the test validates THIS pair, not an accidental thread
    #    collision. NOT byte-identical (distinct words + titles -> distinct content_hash).
    notes.append({"title": "Realization about starting",
                  "content": "Starting a task always feels far heavier than the task actually "
                             "is. The dread is the cost, not the work itself.",
                  "created_at": (start + timedelta(days=3)).isoformat()})
    notes.append({"title": "Same lesson, said again",
                  "content": "Starting a task always feels far heavier than the task really "
                             "is. The dread is the cost, not the doing itself.",
                  "created_at": (start + timedelta(days=9)).isoformat()})

    # 4) Length extremes.
    notes.append({"title": "Quick capture",
                  "content": "call dentist",
                  "created_at": (start + timedelta(days=1)).isoformat()})
    long_dump = " ".join([rng.choice(sum(_sentence_pool(rng).values(), []))
                          for _ in range(40)])  # ~200+ words of varied fictional sentences
    notes.append({"title": "Long evening brain-dump",
                  "content": long_dump,
                  "created_at": (start + timedelta(days=20)).isoformat()})

    # 5) One themed anchor per category (guarantees 8-way coverage for the categorizer).
    for k, (cat, line) in enumerate(CATEGORY_ANCHORS.items()):
        notes.append({"title": f"Anchor: {cat}",
                      "content": line,
                      "created_at": (start + timedelta(days=25 + k)).isoformat()})

    return notes
```

**Step 2: Modify `generate()`** to prepend the designed core, then pad with background to `count`:

```python
def generate(count, days, seed):
    rng = random.Random(seed)
    end = datetime(2026, 5, 28, 9, 0, 0, tzinfo=timezone.utc)
    start = end - timedelta(days=days)
    span_seconds = int((end - start).total_seconds())

    designed = _designed_notes(rng, start, span_seconds)

    # Background volume fills the remainder (designed core always included first).
    remaining = max(0, count - len(designed))
    background = []
    for i in range(remaining):
        offset = rng.randint(0, span_seconds)
        created_at = start + timedelta(seconds=offset)
        background.append(_make_note(rng, created_at, i))

    notes = designed + background
    notes.sort(key=lambda n: n["created_at"])
    return notes
```

**Step 3: Run the full test suite**

Run: `cd /Users/chaseeasterling/selene && python3 scripts/test_generate_dev_fixture.py -v`
Expected: PASS (all 6 tests). If `test_length_extremes` fails on the long-dump, bump the `range(40)` until `max words >= 200`; if `test_monster_note_present` fails, the monster word-count threshold (120) vs actual (~110) — extend the monster text by one sentence rather than lowering the threshold.

**Step 4: Verify determinism + uniqueness by hand**

Run: `python3 scripts/generate-dev-fixture.py --count 500 | python3 -c "import sys,json,hashlib; n=json.load(sys.stdin); h=[hashlib.sha256((x['title']+x['content']).encode()).hexdigest() for x in n]; print('notes',len(n),'unique_hashes',len(set(h)))"`
Expected: `unique_hashes == notes` (no `INSERT OR IGNORE` drops). If fewer, two designed notes collided — vary a title.

**Step 5: Commit**

```bash
git add scripts/generate-dev-fixture.py
git commit -m "feat(fixture): designed showcase corpus (threads, monster, near-dups, extremes, category anchors)"
```

---

### Task A4: Update the generator docstring + scripts/CLAUDE.md

**Files:**
- Modify: `scripts/generate-dev-fixture.py` (module docstring, lines 2-21)
- Modify: `scripts/CLAUDE.md` (the `generate-dev-fixture.py` section)

**Step 1:** Reword the docstring/description from "realistic-looking volume" to describe the **designed core** (threads + monster + near-dups + extremes + category anchors) plus background padding, still deterministic + PII-free.

**Step 2: Commit**

```bash
git add scripts/generate-dev-fixture.py scripts/CLAUDE.md
git commit -m "docs(fixture): document the designed showcase corpus"
```

---

### Task A5: End-to-end dev-pipeline validation (manual, eyeball gate)

> This is the acceptance gate from the design (the assertion harness was deferred). It RUNS the real pipeline on the dev DB and you inspect the output. Requires Ollama running. Touches ONLY `~/selene-data-dev/`.

**Step 1: Rebuild the dev sandbox**

Run: `cd /Users/chaseeasterling/selene && ./scripts/reset-dev-data.sh`
Expected: wipes `~/selene-data-dev/`, recreates schema, seeds (Inserted ≈ 500, Skipped 0).

**Step 2: Process through the pipeline**

Run: `SELENE_ENV=development ./scripts/dev-process-batch.sh 60`
(Repeat until `./scripts/dev-process-batch.sh --status` shows pending ≈ 0. Slow — LLM per note.)

**Step 3: Verify category coverage (the indirect-categorization check)**

Run: `sqlite3 ~/selene-data-dev/selene.db "SELECT category, COUNT(*) FROM processed_notes GROUP BY category ORDER BY 2 DESC;"`
Expected: **≥6 of the 8** categories represented (temp 0.8 → not always all 8; <6 means anchors are too weak — strengthen anchor wording, not the threshold).

**Step 4: Verify the threads clustered + monster is multi-membership**

Run: `sqlite3 ~/selene-data-dev/selene.db "SELECT tc.name, COUNT(*) FROM topic_clusters tc JOIN topic_note_links tnl ON tnl.cluster_id=tc.id GROUP BY tc.id ORDER BY 2 DESC LIMIT 12;"`
Expected: clusters that visibly correspond to the three threads; the monster note appears under multiple categories (multi-membership).

**Step 5: Eyeball the showcase output**

Open `~/selene-data-dev/vault/` (or the dev vault path) and confirm it reads like a legible knowledge base a person could be shown. Note any pathology that didn't surface as a follow-up.

**Step 6:** No commit (validation only). Record results in `BRANCH-STATUS.md` testing stage.

---

# Workstream B — The Claude-out-of-prod guard

Adds a `permissions.deny` block + a PreToolUse **Bash** hook that blocks any Bash command referencing prod **data** paths, while allowlisting prod **operations**. Neutralizes the permissive allow-rules. **Independent of Workstream A.**

### Task B1: Confirm the PreToolUse Bash hook input contract (spike — no assumptions)

> We must not assume how the command text reaches the hook. Verify empirically first.

**Files:**
- Create (temporary): `.claude/hooks/_probe.sh`

**Step 1:** Write a probe that dumps everything it receives:

```bash
#!/bin/bash
# TEMPORARY probe — logs how PreToolUse passes a Bash command to the hook.
{
  echo "=== $(date) ==="
  echo "ARGV: $*"
  echo "CLAUDE_FILE_PATHS=$CLAUDE_FILE_PATHS"
  echo "CLAUDE_TOOL_INPUT=$CLAUDE_TOOL_INPUT"
  echo "--- stdin ---"
  cat
  echo ""
} >> /tmp/selene-hook-probe.log 2>&1
exit 0
```

**Step 2:** Temporarily register it as a PreToolUse `Bash` matcher in `.claude/settings.json`, then run any throwaway Bash command (e.g. `echo hi`).

**Step 3:** Inspect `/tmp/selene-hook-probe.log`. Determine whether the command text arrives via **stdin JSON** (expected: `{"tool_input":{"command":"echo hi"}}`) or an env var. **Record the answer** — it dictates how B2 reads the command.

**Step 4:** Remove the probe + its registration. Do NOT commit the probe.

```bash
rm .claude/hooks/_probe.sh
```

---

### Task B2: Write the guard hook + its test

**Files:**
- Create: `.claude/hooks/prod-data-guard.sh`
- Create: `.claude/hooks/test-prod-data-guard.sh`

**Step 1: Write the failing test** (`test-prod-data-guard.sh`) — feeds the hook representative commands and asserts exit codes. Adjust the "feed" mechanism to match the B1 finding (shown here for stdin-JSON):

```bash
#!/bin/bash
# Tests prod-data-guard.sh: exit 2 = blocked, exit 0 = allowed.
set -u
HOOK="$(dirname "$0")/prod-data-guard.sh"
fail=0

check() {  # check <expected_code> <description> <command-string>
  local want="$1" desc="$2" cmd="$3" got
  printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | bash "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" != "$want" ]; then echo "FAIL [$desc] want=$want got=$got"; fail=1
  else echo "ok   [$desc]"; fi
}

# BLOCK: reading real note content
check 2 "prod sqlite SELECT content" 'SELENE_ENV=production sqlite3 ~/selene-data/selene.db "SELECT content FROM raw_notes"'
check 2 "read prod vault file"       'cat "$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Selene/Daily/x.md"'
check 2 "read prod eink"             'ls ~/selene-data/eink/'
check 2 "absolute prod db path"      'sqlite3 /Users/chaseeasterling/selene-data/selene.db ".tables"'

# ALLOW: dev paths (substring trap)
check 0 "dev db query"               'sqlite3 ~/selene-data-dev/selene.db "SELECT COUNT(*) FROM raw_notes"'
check 0 "dev reset"                  './scripts/reset-dev-data.sh'

# ALLOW: prod OPERATIONS (reference path but do not read notes)
check 0 "deploy-prod"                './scripts/deploy-prod.sh --ref origin/main'
check 0 "rollback-prod"              './scripts/rollback-prod.sh'
check 0 "install-prod bakes db path" './scripts/install-prod.sh --prod-dir ~/selene-prod'
check 0 "health check"               'curl http://localhost:5678/health'

# ALLOW: explicit override for incident recovery
check 0 "override flag"              'SELENE_PROD_OVERRIDE=1 sqlite3 ~/selene-data/selene.db ".tables"'

# ALLOW: unrelated command
check 0 "harmless"                   'echo hello'

exit $fail
```

**Step 2: Run it — expect failure** (hook doesn't exist yet):

Run: `bash .claude/hooks/test-prod-data-guard.sh`
Expected: FAIL / error (no hook).

**Step 3: Write the hook** (`prod-data-guard.sh`) — allowlist-ops-first, then deny-on-path:

```bash
#!/bin/bash
# prod-data-guard.sh — PreToolUse(Bash) guard.
# Blocks (exit 2) any Bash command that touches REAL prod DATA paths, while
# allowing prod OPERATIONS (deploy/rollback/install/log/health) and all dev work.
# Block by PATH, not by parsing SQL. See design 2026-05-29-dev-prod-boundary-hardening.

# Read the command text. (Confirm the source via Task B1; stdin-JSON shown here.)
CMD="$(cat)"
CMD="$(printf '%s' "$CMD" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception:
    pass')"

# 0) Deliberate override for incident recovery (documented escape hatch).
if printf '%s' "$CMD" | grep -q 'SELENE_PROD_OVERRIDE=1'; then exit 0; fi

# 1) Allowlist prod OPERATIONS — these legitimately name prod paths without reading notes.
if printf '%s' "$CMD" | grep -qE '(deploy-prod\.sh|rollback-prod\.sh|install-prod\.sh|deploy-watch\.sh|uninstall-launchd\.sh)'; then exit 0; fi
if printf '%s' "$CMD" | grep -qE 'curl[^|]*localhost:5678/health'; then exit 0; fi
if printf '%s' "$CMD" | grep -qE 'tail [^|]*logs/'; then exit 0; fi

# 2) DENY real-data paths. Trailing slash is load-bearing: selene-data/ != selene-data-dev/.
PROD_PATHS='(~|\$HOME|/Users/[^/ ]+)/selene-data/|iCloud~md~obsidian/Documents/Selene/'
if printf '%s' "$CMD" | grep -qE "$PROD_PATHS"; then
  echo 'BLOCKED: command references real production data (~/selene-data/ or the iCloud vault).' >&2
  echo 'Dev work uses ~/selene-data-dev/. For genuine prod recovery, prefix: SELENE_PROD_OVERRIDE=1' >&2
  exit 2
fi

exit 0
```

**Step 4: Run the test — expect PASS:**

Run: `bash .claude/hooks/test-prod-data-guard.sh`
Expected: all `ok`. If "dev db query" fails (blocked), the substring regex is wrong — verify `selene-data-dev/` is NOT matched by `selene-data/`.

**Step 5: Commit**

```bash
chmod +x .claude/hooks/prod-data-guard.sh .claude/hooks/test-prod-data-guard.sh
git add .claude/hooks/prod-data-guard.sh .claude/hooks/test-prod-data-guard.sh
git commit -m "feat(guard): PreToolUse Bash hook blocking real-prod-data access (ops allowlisted)"
```

---

### Task B3: Register the hook + add `permissions.deny`

**Files:**
- Modify: `.claude/settings.json` (add a `Bash` matcher under `PreToolUse`; add a `permissions.deny` block)

**Step 1:** Add a second `PreToolUse` entry with `"matcher": "Bash"` invoking `bash .claude/hooks/prod-data-guard.sh` (alongside the existing `Edit|Write` entry).

**Step 2:** Add a top-level `permissions.deny` array (deny wins over allow — defense in depth for the tool-level Read/Edit/Write paths the Bash hook doesn't cover):

```json
"permissions": {
  "deny": [
    "Read(//Users/chaseeasterling/selene-data/**)",
    "Edit(//Users/chaseeasterling/selene-data/**)",
    "Write(//Users/chaseeasterling/selene-data/**)",
    "Read(//Users/chaseeasterling/Library/Mobile Documents/iCloud~md~obsidian/Documents/Selene/**)",
    "Edit(//Users/chaseeasterling/Library/Mobile Documents/iCloud~md~obsidian/Documents/Selene/**)",
    "Write(//Users/chaseeasterling/Library/Mobile Documents/iCloud~md~obsidian/Documents/Selene/**)"
  ]
}
```

> Note: `selene-data/**` does NOT match `selene-data-dev/**` (different path segment) — dev reads stay allowed.

**Step 3: Validate settings JSON parses**

Run: `python3 -c "import json; json.load(open('.claude/settings.json')); print('settings.json OK')"`
Expected: `settings.json OK`.

**Step 4: Re-run the guard test** (registration shouldn't change behavior):

Run: `bash .claude/hooks/test-prod-data-guard.sh`
Expected: all `ok`.

**Step 5: Commit**

```bash
git add .claude/settings.json
git commit -m "feat(guard): register prod-data Bash hook + permissions.deny for real-data paths"
```

---

### Task B4: Neutralize the prod-read allow-rules in `settings.local.json`

**Files:**
- Modify: `.claude/settings.local.json` (remove the prod-read grants — match by content, not line number)

**Step 1: Back up + list the offending rules**

Run: `cp .claude/settings.local.json /tmp/settings.local.bak.json && grep -nE 'selene-data/(selene\.db|vault|eink|\*\*)|production sqlite3' .claude/settings.local.json`

**Step 2:** Delete the array entries that grant real-data access:
- `Bash(SELENE_ENV=production sqlite3 …/selene-data/selene.db "SELECT … content …")`
- `Read(//Users/chaseeasterling/selene-data/**)` and all `…/selene-data/vault/**`, `…/selene-data/eink/**` Read rules
- `Bash(rm -rf ~/selene-data/vault/)`
- any `SELENE_DB_PATH=…/selene-data/selene.db …` allow that reads content

Leave dev (`selene-data-dev`) and operational (`deploy-prod`, `install-prod`, `rollback-prod`) rules intact.

**Step 3: Validate JSON parses**

Run: `python3 -c "import json; json.load(open('.claude/settings.local.json')); print('OK')"`
Expected: `OK`. (If broken, restore from `/tmp/settings.local.bak.json`.)

**Step 4: Confirm no prod-read grants remain**

Run: `grep -nE 'selene-data/(selene\.db|vault|eink|\*\*)' .claude/settings.local.json | grep -v 'selene-data-dev' || echo "clean"`
Expected: `clean`.

**Step 5: Commit**

```bash
git add .claude/settings.local.json
git commit -m "chore(guard): remove permissive real-prod-data allow-rules"
```

> NOTE: `settings.local.json` is typically gitignored. If `git add` refuses, that's fine — the edit still applies locally; record in BRANCH-STATUS that it was hand-edited.

---

### Task B5: Document the boundary + override

**Files:**
- Modify: `docs/guides/features/releases.md` (add a "Claude & real data" subsection) OR `.claude/OPERATIONS.md`

**Step 1:** Document: Claude is walled off from `~/selene-data/` and the iCloud vault (real notes); dev work uses `~/selene-data-dev/`; prod operations (deploy/rollback/install/health/logs) remain allowed; and the deliberate override `SELENE_PROD_OVERRIDE=1 <cmd>` for genuine incident recovery (cross-reference the prod-down recovery procedure).

**Step 2: Commit**

```bash
git add docs/guides/features/releases.md
git commit -m "docs(guard): document Claude/real-data boundary + recovery override"
```

---

## Wrap-up (both workstreams)

1. Update `BRANCH-STATUS.md` stages (dev/testing/docs).
2. Per CLAUDE.md: user-facing change? The corpus/guard are dev-workflow/safety — note "no end-user-facing change" unless the releases guide edit (B5) counts; if so its link is already in the hub.
3. Move the design doc toward **Done** in `docs/plans/INDEX.md` after merge.
4. Run `./scripts/cleanup-tests.sh --list` — the dev seed uses `test_run='dev-seed'` in the DEV db only; nothing should leak to prod.

## Acceptance recap (from the design)
- **A:** corpus has ≥2 threads, ≥1 monster, ≥1 near-dup pair, length extremes, 8-category themes; deterministic; no schema change; ≥6/8 categories surface after the pipeline.
- **B:** real-note Bash reads blocked; dev workflows unaffected (substring trap); ops allowlisted + override documented; permissive allow-rules removed.
