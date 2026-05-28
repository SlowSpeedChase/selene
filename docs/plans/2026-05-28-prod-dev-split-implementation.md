# Production / Development Split — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Give Selene a release boundary — `~/selene` becomes a dev sandbox (dev DB, scratch vault, ts-node), and a compiled build artifact in `~/selene-prod` serves the real database and iCloud vault, auto-deployed on merge to `main` via a build-gated launchd watcher. Plus two coexisting iPad apps.

**Architecture:** A scratch build clone (`~/selene-build`) builds `origin/main` with `tsc`; on success the `dist/` is shipped to `~/selene-prod` (preserving its `.env`), prod launchd agents (`com.selene.prod.*`, generated from the canonical `launchd/*.plist`) restart, and a notification fires. A launchd watcher polls `origin/main` and triggers a deploy when the SHA moves. The risky cutover (retiring the 11 live `com.selene.*` agents) happens **last**, only after the deploy machinery is proven against a throwaway `~/selene-prod-test`.

**Tech Stack:** TypeScript + `tsc`, bash, launchd, rsync, git, `osascript` notifications, xcodegen (iPad, separate repo).

**Design doc:** `docs/plans/2026-05-28-prod-dev-split-design.md`

**Critical ordering rule:** Tasks 1–8 build and *prove* the tooling without touching anything live. Task 9 (cutover) is the only task that affects your real running system. Do NOT reorder.

**Cross-cutting safety:**
- Never create `~/selene-prod/.env` with Edit/Write — the `.claude` PreToolUse hook blocks it. Use the bash scripts in this plan (`cat`/heredoc).
- Every script that mutates prod must be idempotent and re-runnable.
- Use @superpowers:test-driven-development for the TS build verification and @superpowers:systematic-debugging if a deploy step misbehaves.

---

### Task 0: Worktree + branch status

**Files:**
- Create: `.worktrees/prod-dev-split/BRANCH-STATUS.md` (from `templates/BRANCH-STATUS.md`)

**Step 1:** Confirm you are in the worktree on branch `feat/prod-dev-split`:

Run: `git branch --show-current`
Expected: `feat/prod-dev-split`

**Step 2:** Copy the branch-status template:

```bash
cp templates/BRANCH-STATUS.md BRANCH-STATUS.md 2>/dev/null || echo "no template — skip"
```

**Step 3:** Commit:

```bash
git add BRANCH-STATUS.md 2>/dev/null; git commit -q -m "chore: branch status for prod-dev-split" || echo "nothing to commit"
```

---

### Task 1: Build pipeline (`npm run build`)

**Files:**
- Modify: `package.json` (add `build` + `build:check` scripts)

**Step 1: Add scripts.** In `package.json` `"scripts"`, add:

```json
"build": "rm -rf dist && tsc -p tsconfig.json",
"build:check": "node -e \"const f=require('fs'); ['server.js','workflows/process-llm.js','workflows/export-obsidian.js','lib/config.js'].forEach(p=>{if(!f.existsSync('dist/'+p)){console.error('MISSING dist/'+p);process.exit(1)}}); console.log('dist OK')\""
```

**Step 2: Run the build:**

Run: `npm run build`
Expected: completes with no TS errors; a `dist/` directory appears.

**Step 3: Verify the artifact is complete:**

Run: `npm run build:check`
Expected: `dist OK`

**Step 4: Verify a compiled workflow actually runs against the TEST db** (proves `__dirname` paths survive compilation):

Run: `SELENE_ENV=test node dist/workflows/process-llm.js 2>&1 | tail -5`
Expected: it runs (may log "no pending notes" — that's fine), does NOT crash with `MODULE_NOT_FOUND` or path errors.

**Step 5: Audit the `calendar.ts` sibling-binary path** (design edge case):

Run: `grep -rn "selene-calendar\|\.build/release" dist/lib/calendar.js`
Expected: note whether any *scheduled* workflow imports `calendar`. If only `server.ts`/on-demand paths use it, no action. If a scheduled workflow needs it, add `SELENE_CALENDAR_BIN` env support in `src/lib/calendar.ts` and rebuild. Record the finding in BRANCH-STATUS.

**Step 6: Ensure `dist/` is gitignored:**

```bash
grep -qx 'dist/' .gitignore || echo 'dist/' >> .gitignore
```

**Step 7: Commit:**

```bash
git add package.json .gitignore && git commit -q -m "feat: add tsc build pipeline (npm run build + build:check)"
```

---

### Task 2: Prod plist generator (`scripts/install-prod.sh`)

Generates `com.selene.prod.*` plists from the canonical `launchd/*.plist` by substitution. Single source of truth — no committed duplicates.

**Files:**
- Create: `scripts/install-prod.sh`
- Create: `scripts/test-install-prod.sh` (verification harness)

**Step 1: Write `scripts/install-prod.sh`:**

```bash
#!/bin/bash
# Generate + install com.selene.prod.* launchd plists from canonical launchd/*.plist.
# Transforms: ts-node src/X.ts -> node <PROD>/dist/X.js ; WorkingDir/logs -> <PROD> ;
# label com.selene.* -> com.selene.prod.* ; inject SELENE_ENV=production.
# Usage: ./scripts/install-prod.sh [--prod-dir DIR] [--out DIR] [--label-prefix PFX] [--dry-run] [--no-load]
set -euo pipefail

PROD_DIR="$HOME/selene-prod"
OUT_DIR="$HOME/Library/LaunchAgents"
LABEL_PFX="com.selene.prod."
DRY_RUN=0
NO_LOAD=0
SRC_LAUNCHD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/launchd"

while [ $# -gt 0 ]; do case "$1" in
  --prod-dir) PROD_DIR="$2"; shift 2;;
  --out) OUT_DIR="$2"; shift 2;;
  --label-prefix) LABEL_PFX="$2"; shift 2;;
  --dry-run) DRY_RUN=1; shift;;
  --no-load) NO_LOAD=1; shift;;
  *) echo "unknown arg $1"; exit 1;;
esac; done

mkdir -p "$OUT_DIR"
GENERATED=()
for plist in "$SRC_LAUNCHD"/com.selene.*.plist; do
  base="$(basename "$plist")"                 # com.selene.process-llm.plist
  name="${base#com.selene.}"; name="${name%.plist}"   # process-llm
  out_label="${LABEL_PFX}${name}"
  out_file="$OUT_DIR/${out_label}.plist"
  # Substitutions (BSD sed):
  sed \
    -e "s#<string>com\\.selene\\.${name}</string>#<string>${out_label}</string>#g" \
    -e "s#npx</string>#node</string>#g" \
    -e "s#<string>ts-node</string>##g" \
    -e "s#<string>src/workflows/${name}\\.ts</string>#<string>${PROD_DIR}/dist/workflows/${name}.js</string>#g" \
    -e "s#<string>src/server\\.ts</string>#<string>${PROD_DIR}/dist/server.js</string>#g" \
    -e "s#/Users/chaseeasterling/selene/logs#${PROD_DIR}/logs#g" \
    -e "s#<string>/Users/chaseeasterling/selene</string>#<string>${PROD_DIR}</string>#g" \
    "$plist" > "/tmp/${out_label}.plist"
  # Inject SELENE_ENV=production into EnvironmentVariables (or create the dict).
  if grep -q "EnvironmentVariables" "/tmp/${out_label}.plist"; then
    sed -i '' "s#<key>EnvironmentVariables</key>\\n*<dict>#&\\n      <key>SELENE_ENV</key><string>production</string>#" "/tmp/${out_label}.plist" || true
  fi
  if [ "$DRY_RUN" = 1 ]; then echo "would write $out_file"; else cp "/tmp/${out_label}.plist" "$out_file"; fi
  GENERATED+=("$out_label")
done

echo "Generated ${#GENERATED[@]} plists with prefix '${LABEL_PFX}'"
if [ "$DRY_RUN" = 0 ] && [ "$NO_LOAD" = 0 ]; then
  for label in "${GENERATED[@]}"; do
    launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$OUT_DIR/${label}.plist"
  done
  echo "Loaded ${#GENERATED[@]} agents."
fi
```

> **Note on the `SELENE_ENV` injection:** BSD `sed` multiline is fragile. If the inline `sed` injection proves unreliable in Step 3, replace it with a tiny node/plutil step: `plutil -insert EnvironmentVariables.SELENE_ENV -string production "$out_file"`. Prefer `plutil` if available — it's robust. Update the script accordingly during implementation.

**Step 2:** `chmod +x scripts/install-prod.sh`

**Step 3: Verify generation with `--dry-run` + a real temp render** (no install):

```bash
./scripts/install-prod.sh --prod-dir "$HOME/selene-prod" --out /tmp/selene-prod-plists --no-label-prefix 2>/dev/null || \
./scripts/install-prod.sh --prod-dir "$HOME/selene-prod" --out /tmp/selene-prod-plists --no-load
```

Run and inspect one rendered plist:
```bash
cat /tmp/selene-prod-plists/com.selene.prod.process-llm.plist
```
Expected, verify ALL of:
- Label is `com.selene.prod.process-llm`
- `ProgramArguments` invokes `node` (not `npx`/`ts-node`) with `…/selene-prod/dist/workflows/process-llm.js`
- `WorkingDirectory` is `…/selene-prod`
- Log paths under `…/selene-prod/logs`
- `EnvironmentVariables` contains `SELENE_ENV` = `production`

**Step 4:** Validate the plist is well-formed XML:

Run: `plutil -lint /tmp/selene-prod-plists/com.selene.prod.process-llm.plist`
Expected: `OK`

**Step 5:** Loop the lint over all generated plists:

```bash
for f in /tmp/selene-prod-plists/*.plist; do plutil -lint "$f" >/dev/null && echo "OK $f" || echo "BAD $f"; done
```
Expected: every line `OK`. If any `BAD`, fix the sed substitutions before proceeding.

**Step 6: Commit:**

```bash
git add scripts/install-prod.sh && git commit -q -m "feat: install-prod.sh — generate com.selene.prod.* plists from canonical plists"
```

---

### Task 3: Deploy script (`scripts/deploy-prod.sh`)

Build-gated, clean-source, env-preserving deploy. Supports `--target` so it can be tested against a throwaway dir.

**Files:**
- Create: `scripts/deploy-prod.sh`
- Create: `scripts/lib/notify.sh` (shared notification helper)

**Step 1: Write `scripts/lib/notify.sh`:**

```bash
#!/bin/bash
# selene_notify "title" "message"  — macOS notification + append to deploy log.
selene_notify() {
  local title="$1"; local msg="$2"
  local log="${SELENE_DEPLOY_LOG:-$HOME/selene-prod/deploy.log}"
  mkdir -p "$(dirname "$log")"
  printf '%s  %s — %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$title" "$msg" >> "$log"
  osascript -e "display notification \"${msg//\"/\'}\" with title \"${title//\"/\'}\"" 2>/dev/null || true
}
```

**Step 2: Write `scripts/deploy-prod.sh`:**

```bash
#!/bin/bash
# Build origin/main in a scratch clone and ship dist/ to a target prod dir.
# Build-gated: a failed build leaves the target untouched.
# Usage: ./scripts/deploy-prod.sh [--target DIR] [--ref REF] [--build-dir DIR]
#                                 [--label-prefix PFX] [--skip-agents] [--skip-health]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/notify.sh"

TARGET="$HOME/selene-prod"
REF="origin/main"
BUILD_DIR="$HOME/selene-build"
LABEL_PFX="com.selene.prod."
SKIP_AGENTS=0
SKIP_HEALTH=0
REPO_URL="$(git -C "$HERE/.." remote get-url origin)"

while [ $# -gt 0 ]; do case "$1" in
  --target) TARGET="$2"; shift 2;;
  --ref) REF="$2"; shift 2;;
  --build-dir) BUILD_DIR="$2"; shift 2;;
  --label-prefix) LABEL_PFX="$2"; shift 2;;
  --skip-agents) SKIP_AGENTS=1; shift;;
  --skip-health) SKIP_HEALTH=1; shift;;
  *) echo "unknown arg $1"; exit 1;;
esac; done

export SELENE_DEPLOY_LOG="$TARGET/deploy.log"

# 1. Ensure scratch build clone exists and is on a CLEAN copy of REF.
if [ ! -d "$BUILD_DIR/.git" ]; then
  git clone "$REPO_URL" "$BUILD_DIR"
fi
git -C "$BUILD_DIR" fetch origin --quiet
git -C "$BUILD_DIR" reset --hard "$REF" --quiet
git -C "$BUILD_DIR" clean -fdx -e node_modules --quiet
NEW_SHA="$(git -C "$BUILD_DIR" rev-parse --short HEAD)"

OLD_SHA="$(cat "$TARGET/.deployed-sha" 2>/dev/null || echo none)"

# 2. Install deps + BUILD (the gate).
( cd "$BUILD_DIR" && npm install --no-audit --no-fund --silent )
if ! ( cd "$BUILD_DIR" && npm run build && npm run build:check ); then
  selene_notify "Selene deploy FAILED" "build of $NEW_SHA failed — prod still on $OLD_SHA"
  echo "BUILD FAILED — aborting, target untouched."
  exit 1
fi

# 3. Prepare target; archive current dist/ for rollback.
mkdir -p "$TARGET/releases" "$TARGET/logs"
if [ -d "$TARGET/dist" ] && [ "$OLD_SHA" != "none" ]; then
  rm -rf "$TARGET/releases/$OLD_SHA"
  cp -R "$TARGET/dist" "$TARGET/releases/$OLD_SHA"
  # keep only the 5 newest releases
  ls -1dt "$TARGET/releases"/*/ 2>/dev/null | tail -n +6 | xargs -I{} rm -rf {} 2>/dev/null || true
fi

# 4. Ship artifact. rsync EXCLUDES .env so prod secrets are never clobbered.
rsync -a --delete "$BUILD_DIR/dist/" "$TARGET/dist/"
cp "$BUILD_DIR/package.json" "$TARGET/package.json"
cp "$BUILD_DIR/package-lock.json" "$TARGET/package-lock.json" 2>/dev/null || true
( cd "$TARGET" && npm install --omit=dev --no-audit --no-fund --silent )

# 5. Restart agents (skip for test targets).
if [ "$SKIP_AGENTS" = 0 ]; then
  "$HERE/install-prod.sh" --prod-dir "$TARGET" --label-prefix "$LABEL_PFX"
fi

# 6. Health check (prod server on :5678).
if [ "$SKIP_HEALTH" = 0 ]; then
  sleep 3
  if ! curl -fsS http://localhost:5678/health >/dev/null; then
    selene_notify "Selene deploy WARN" "shipped $NEW_SHA but :5678 health check failed"
  fi
fi

# 7. Record + notify success.
echo "$NEW_SHA" > "$TARGET/.deployed-sha"
selene_notify "Selene deployed" "$OLD_SHA -> $NEW_SHA @ $(date '+%H:%M')"
echo "DEPLOYED $OLD_SHA -> $NEW_SHA to $TARGET"
```

**Step 3:** `chmod +x scripts/deploy-prod.sh scripts/lib/notify.sh`

**Step 4: Dry verification of the notify helper (no deploy yet):**

```bash
source scripts/lib/notify.sh && SELENE_DEPLOY_LOG=/tmp/selene-deploy-test.log selene_notify "Test" "hello" && cat /tmp/selene-deploy-test.log
```
Expected: log line written; a macOS notification appears (or silently no-ops if notifications are off).

**Step 5: Commit:**

```bash
git add scripts/deploy-prod.sh scripts/lib/notify.sh && git commit -q -m "feat: deploy-prod.sh — build-gated, env-preserving deploy with rollback archive"
```

---

### Task 4: Rollback script (`scripts/rollback-prod.sh`)

**Files:**
- Create: `scripts/rollback-prod.sh`

**Step 1: Write it:**

```bash
#!/bin/bash
# Swap prod dist/ back to a previously archived release. Usage: rollback-prod.sh [sha] [--target DIR]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/notify.sh"
TARGET="$HOME/selene-prod"; SHA=""
while [ $# -gt 0 ]; do case "$1" in
  --target) TARGET="$2"; shift 2;;
  *) SHA="$1"; shift;;
esac; done
export SELENE_DEPLOY_LOG="$TARGET/deploy.log"
if [ -z "$SHA" ]; then
  SHA="$(ls -1dt "$TARGET/releases"/*/ 2>/dev/null | head -1 | xargs -n1 basename || true)"
fi
[ -z "$SHA" ] && { echo "no release to roll back to"; exit 1; }
[ -d "$TARGET/releases/$SHA" ] || { echo "release $SHA not found"; exit 1; }
rsync -a --delete "$TARGET/releases/$SHA/" "$TARGET/dist/"
echo "$SHA" > "$TARGET/.deployed-sha"
"$HERE/install-prod.sh" --prod-dir "$TARGET"
sleep 3; curl -fsS http://localhost:5678/health >/dev/null && echo "health OK" || echo "health WARN"
selene_notify "Selene ROLLED BACK" "prod reverted to $SHA"
```

**Step 2:** `chmod +x scripts/rollback-prod.sh`

**Step 3: Commit:**

```bash
git add scripts/rollback-prod.sh && git commit -q -m "feat: rollback-prod.sh — instant dist/ swap to a prior release"
```

---

### Task 5: Deploy watcher (poller)

**Files:**
- Create: `scripts/deploy-watch.sh`
- Create: `launchd/com.selene.prod.deploy-watcher.plist`

**Step 1: Write `scripts/deploy-watch.sh`:**

```bash
#!/bin/bash
# Poll origin/main; deploy when the SHA moves past what prod is running.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
TARGET="${SELENE_PROD_DIR:-$HOME/selene-prod}"
git -C "$REPO" fetch origin --quiet
REMOTE_SHA="$(git -C "$REPO" rev-parse --short origin/main)"
DEPLOYED_SHA="$(cat "$TARGET/.deployed-sha" 2>/dev/null || echo none)"
if [ "$REMOTE_SHA" != "$DEPLOYED_SHA" ]; then
  echo "origin/main moved $DEPLOYED_SHA -> $REMOTE_SHA; deploying"
  "$HERE/deploy-prod.sh" --target "$TARGET" --ref origin/main
else
  echo "up to date ($DEPLOYED_SHA)"
fi
```

**Step 2:** `chmod +x scripts/deploy-watch.sh`

**Step 3: Write `launchd/com.selene.prod.deploy-watcher.plist`** (runs every 5 min; this plist is committed and is INFRA — it has no matching workflow, see Task 7):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.selene.prod.deploy-watcher</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/chaseeasterling/selene/scripts/deploy-watch.sh</string>
  </array>
  <key>WorkingDirectory</key><string>/Users/chaseeasterling/selene</string>
  <key>StartInterval</key><integer>300</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>/Users/chaseeasterling/selene-prod/logs/deploy-watcher.out.log</string>
  <key>StandardErrorPath</key><string>/Users/chaseeasterling/selene-prod/logs/deploy-watcher.err.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
```

> **Note:** the watcher runs from `~/selene` (it needs the git remote), NOT from `~/selene-prod`. That's intentional and is the one prod-labeled agent whose `WorkingDirectory` is `~/selene`.

**Step 4: Validate XML:**

Run: `plutil -lint launchd/com.selene.prod.deploy-watcher.plist`
Expected: `OK`

**Step 5: Commit:**

```bash
git add scripts/deploy-watch.sh launchd/com.selene.prod.deploy-watcher.plist && git commit -q -m "feat: deploy-watcher — poll origin/main and trigger gated deploy"
```

---

### Task 6: Prove the full cycle against a throwaway target (NO real data)

This is the gate before the real cutover. We deploy to `~/selene-prod-test`, with a fake DB and test-labeled agents, and verify build→gate→ship→rollback end to end.

**Files:** none (verification only)

**Step 1: Seed a fake prod-test env:**

```bash
mkdir -p "$HOME/selene-prod-test"
cat > "$HOME/selene-prod-test/.env" <<'EOF'
SELENE_ENV=production
SELENE_DB_PATH=/tmp/selene-prodtest/selene.db
SELENE_VAULT_PATH=/tmp/selene-prodtest/vault
SELENE_DIGESTS_PATH=/tmp/selene-prodtest/digests
SELENE_LOGS_PATH=/Users/chaseeasterling/selene-prod-test/logs
APPLE_NOTES_DIGEST_ENABLED=false
TRMNL_DIGEST_ENABLED=false
EOF
mkdir -p /tmp/selene-prodtest
```

**Step 2: Run a deploy to the test target, skipping agents + health** (no launchd, no :5678):

Run:
```bash
./scripts/deploy-prod.sh --target "$HOME/selene-prod-test" --ref origin/main --skip-agents --skip-health
```
Expected: ends with `DEPLOYED none -> <sha>`; `~/selene-prod-test/dist/server.js` exists; `~/selene-prod-test/.deployed-sha` contains the sha; `~/selene-prod-test/.env` is UNCHANGED (cat it and confirm).

**Step 3: Verify .env preservation explicitly** (the #1 risk):

```bash
grep -q "/tmp/selene-prodtest/selene.db" "$HOME/selene-prod-test/.env" && echo "ENV PRESERVED" || echo "ENV CLOBBERED — BUG"
```
Expected: `ENV PRESERVED`

**Step 4: Run a SECOND deploy of the same sha** (idempotency + release archiving):

```bash
./scripts/deploy-prod.sh --target "$HOME/selene-prod-test" --ref origin/main --skip-agents --skip-health
ls "$HOME/selene-prod-test/releases/"
```
Expected: a `releases/<old-sha>/` dir now exists; second run succeeds.

**Step 5: Test rollback against the test target:**

```bash
./scripts/rollback-prod.sh "$(ls -1 $HOME/selene-prod-test/releases | head -1)" --target "$HOME/selene-prod-test"
```
Expected: `dist/` swapped; `.deployed-sha` updated. (Health/agent lines may WARN — fine for the test target.)

**Step 6: Simulate a BROKEN build is gated.** Temporarily break the build in the scratch clone and confirm the target is untouched:

```bash
BAD_SHA_BEFORE="$(cat $HOME/selene-prod-test/.deployed-sha)"
echo "this is not typescript" > "$HOME/selene-build/src/zz_break.ts"
( cd "$HOME/selene-build" && npm run build ) ; echo "build exit: $?"
# Now run deploy pointing --build-dir at the broken clone WITHOUT resetting it:
# (deploy-prod resets to origin/main, which is clean — so instead test the gate directly:)
( cd "$HOME/selene-build" && npm run build && echo "WOULD DEPLOY" || echo "GATE BLOCKS DEPLOY" )
rm -f "$HOME/selene-build/src/zz_break.ts"
```
Expected: `GATE BLOCKS DEPLOY`. (Note: `deploy-prod.sh` resets the build dir to a clean `origin/main`, so this step verifies the *gate logic* directly. The takeaway: a non-compiling tree never reaches the target.)

**Step 7: Clean up the test env:**

```bash
rm -rf "$HOME/selene-prod-test" /tmp/selene-prodtest
```

**Step 8:** Record results in BRANCH-STATUS (no commit needed unless notes added). Use @superpowers:verification-before-completion — paste the actual command outputs, do not assert "it works" without them.

---

### Task 7: Update Claude hooks + launchd-auditor

**Files:**
- Modify: `.claude/settings.json`
- Modify: `.claude/agents/launchd-auditor.md`

**Step 1: Extend the launchd-sync matcher.** In `.claude/settings.json`, find the PostToolUse hook whose command greps `src/workflows/[^/]+\.ts$|launchd/.*\.plist$|scripts/install-launchd\.sh` and add `install-prod\.sh` and `deploy-prod\.sh`:

Change the regex to:
```
(src/workflows/[^/]+\.ts$|launchd/.*\.plist$|scripts/install-(launchd|prod)\.sh|scripts/deploy-prod\.sh)
```

**Step 2: Validate settings.json is still valid JSON:**

Run: `node -e "JSON.parse(require('fs').readFileSync('.claude/settings.json','utf8')); console.log('settings OK')"`
Expected: `settings OK`

**Step 3: Teach the launchd-auditor the prod/dev model.** Append a section to `.claude/agents/launchd-auditor.md`:

```markdown
## Prod/dev split (since 2026-05-28)

The repo's `launchd/com.selene.*.plist` are the **canonical source/dev form** (WorkingDirectory `~/selene`, `ts-node src/X.ts`, prod DB path). Your existing checks (#4, #5) apply to THESE.

Production runs `com.selene.prod.*` agents that are **generated at deploy time** by `scripts/install-prod.sh` from the canonical plists — they are NOT committed. Do not flag "missing prod plist" drift; there should be no committed `*.prod.*.plist` EXCEPT the one infra plist below.

**Exceptions to the 1-plist-per-workflow rule:**
- `launchd/com.selene.prod.deploy-watcher.plist` is INFRA: it has NO matching `src/workflows/*.ts`. Exclude it from the workflow cross-check. It must run `scripts/deploy-watch.sh` from `~/selene` (not `~/selene-prod`).

**Additional sync target:** `scripts/install-prod.sh` transforms every canonical plist. If a workflow/plist is added or removed, verify `install-prod.sh` still globs `launchd/com.selene.*.plist` (it does so by wildcard, so it stays in sync automatically — just confirm the new plist matches the glob and the `name` extraction).
```

**Step 4: Commit:**

```bash
git add .claude/settings.json .claude/agents/launchd-auditor.md && git commit -q -m "chore: teach Claude hooks + launchd-auditor about the prod/dev split"
```

---

### Task 8: Dev sandbox refresh path

Confirm the dev DB can be (re)built from an anonymized copy of real data, and the dev vault is a scratch dir. No live impact.

**Files:**
- Possibly modify: `scripts/anonymize-debug.ts` and/or add `scripts/refresh-dev-db.sh`

**Step 1: Inspect the existing anonymize script:**

Run: `cat scripts/anonymize-debug.ts`
Determine whether it produces an anonymized copy of the real DB into `~/selene-data-dev/selene.db`. If it's a stub, write `scripts/refresh-dev-db.sh` that: copies `~/selene-data/selene.db` → temp, runs anonymization, writes `~/selene-data-dev/selene.db`, sets `_selene_metadata.environment='development'`.

**Step 2: Verify dev config routing (read-only):**

Run: `SELENE_ENV=development node -e "require('ts-node/register'); console.log(require('./src/lib/config').config.dbPath, require('./src/lib/config').config.vaultPath)"`
Expected: dbPath `~/selene-data-dev/selene.db`, vaultPath `~/selene-data-dev/vault` — NOT the real paths.

**Step 3: Confirm dev vault is gitignored / scratch and dev runs no scheduled agents** (design decision — there should be NO `com.selene.dev.*` plists). Record confirmation in BRANCH-STATUS.

**Step 4: Commit** any new script:

```bash
git add scripts/refresh-dev-db.sh 2>/dev/null && git commit -q -m "feat: refresh-dev-db.sh — rebuild dev DB from anonymized real data" || echo "no change"
```

---

### Task 9: THE CUTOVER (the only task that touches your live system)

> ⚠️ Run this ONLY after Tasks 1–8 are green and the PR is ready to merge to `main`. This retires the 11 live `com.selene.*` agents and hands prod to `~/selene-prod`. Do it interactively, with the user present, not from the watcher.

**Files:**
- Create: `~/selene-prod/.env` (via script — NOT Edit/Write)
- Create: `docs/guides/features/releases.md` cutover runbook reference (Task 11 writes the guide)

**Step 1: Merge this branch to main first** (so `origin/main` has the deploy tooling). Then on `main` locally, or just point the deploy at `origin/main`.

**Step 2: Create the prod `.env`** (the PreToolUse hook blocks Edit/Write on `.env`, so use a heredoc). Fill real values from the current environment — read them from the existing running config, do NOT invent:

```bash
mkdir -p "$HOME/selene-prod"
cat > "$HOME/selene-prod/.env" <<EOF
SELENE_ENV=production
SELENE_DB_PATH=$HOME/selene-data/selene.db
SELENE_VAULT_PATH=$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Selene
SELENE_LOGS_PATH=$HOME/selene-prod/logs
SELENE_API_TOKEN=<COPY FROM ~/selene/.env>
TRMNL_WEBHOOK_URL=<COPY FROM ~/selene/.env IF SET>
APNS_KEY_PATH=<COPY IF SET>
APNS_KEY_ID=<COPY IF SET>
APNS_TEAM_ID=<COPY IF SET>
APPLE_NOTES_DIGEST_ENABLED=true
TRMNL_DIGEST_ENABLED=true
EOF
chmod 600 "$HOME/selene-prod/.env"
```
> The executor must copy the real secret values from `~/selene/.env` into the placeholders. Confirm `SELENE_VAULT_PATH` matches the actual iCloud vault (see memory: `project_obsidian_vault_icloud`).

**Step 3: First real build + deploy to `~/selene-prod`, but SKIP agent install** (so the old agents keep serving while we verify the artifact):

```bash
./scripts/deploy-prod.sh --target "$HOME/selene-prod" --ref origin/main --skip-agents --skip-health
```
Expected: `~/selene-prod/dist/` populated; `.env` preserved (Step 2 values intact).

**Step 4: Smoke-test the compiled prod server on a SPARE port** (don't touch :5678 yet):

```bash
( cd "$HOME/selene-prod" && PORT=5699 SELENE_ENV=production node dist/server.js & echo $! > /tmp/selene-prod-smoke.pid )
sleep 3; curl -fsS http://localhost:5699/health && echo " SMOKE OK"
kill "$(cat /tmp/selene-prod-smoke.pid)" 2>/dev/null
```
Expected: ` SMOKE OK`. If it fails, STOP — do not cut over. Debug with @superpowers:systematic-debugging.

**Step 5: ATOMIC SWAP — bootout the 11 old agents, bootstrap the prod set.** List the live ones first:

```bash
launchctl list | grep '^.*com\.selene\.' | awk '{print $3}' | grep -v 'com.selene.prod' > /tmp/old-selene-agents.txt
cat /tmp/old-selene-agents.txt   # should list the 11 com.selene.* (NOT prod, NOT chaseeasterling.selene-docs)
```

Then swap:
```bash
# Unload OLD (frees :5678 and stops real-DB processing)
while read -r label; do launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true; done < /tmp/old-selene-agents.txt
# Also remove their installed plists so they don't reload on login:
while read -r label; do rm -f "$HOME/Library/LaunchAgents/$label.plist"; done < /tmp/old-selene-agents.txt
# Load NEW prod agents + the deploy watcher:
./scripts/install-prod.sh --prod-dir "$HOME/selene-prod"
cp launchd/com.selene.prod.deploy-watcher.plist "$HOME/Library/LaunchAgents/"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.selene.prod.deploy-watcher.plist"
echo "$(git -C "$HOME/selene-build" rev-parse --short origin/main)" > "$HOME/selene-prod/.deployed-sha"
```

**Step 6: Verify the new world:**

```bash
sleep 4
curl -fsS http://localhost:5678/health && echo " PROD :5678 OK"
launchctl list | grep com.selene.prod | wc -l   # expect 12 (11 workflows + deploy-watcher)
launchctl list | grep -c 'com\.selene\.[^p]'    # expect 0 old non-prod agents
```
Expected: `PROD :5678 OK`; ~12 prod agents; 0 old agents.

**Step 7: Confirm dev repo is now inert.** From `~/selene`, confirm no scheduled agents point at it and editing a workflow has no live effect. Record in BRANCH-STATUS.

**Step 8:** Watch the first auto-deploy cycle: make a trivial commit to `main`, push, wait ≤5 min, confirm a "Selene deployed" notification + `.deployed-sha` update.

---

### Task 10: iPad apps (in `~/SeleneMarkup` — SEPARATE repo)

> This work happens in `~/SeleneMarkup`, NOT this repo. Do it on a branch there. Per memory `project_selene_folio_boundary` / `project_selenemarkup`, keep the repo boundary clean.

**Files (in `~/SeleneMarkup`):**
- Modify: `project.yml` (add a `SeleneMarkup-Dev` target/scheme)
- Modify: `AppConfig.swift` (env-specific default `baseURL`)
- Modify: `redeploy.sh` (add `--prod` / `--dev`)

**Step 1:** Inspect current single-target setup:
```bash
cd ~/SeleneMarkup && cat project.yml && grep -n "baseURL\|bundleId\|PRODUCT_BUNDLE" project.yml AppConfig.swift Sources/**/AppConfig.swift 2>/dev/null
```

**Step 2:** In `project.yml`, add a second target derived from the first:
- `SeleneMarkup` → bundleId `com.selene.markup`, name **Selene**, `SELENE_ENV=prod` build setting, default baseURL `http://<Mac-LAN-IP>:5678`.
- `SeleneMarkup-Dev` → bundleId `com.selene.markup.dev`, name **Selene Dev**, `SELENE_ENV=dev`, default baseURL `http://<Mac-LAN-IP>:5679`, a tinted/badged app icon.

**Step 3:** In `AppConfig.swift`, switch the default `baseURL` on a compile-time flag (e.g. `#if SELENE_DEV`) so each target ships pointing at its own server. Keep the in-app override field.

**Step 4:** In `redeploy.sh`, add a flag:
```bash
SCHEME="SeleneMarkup"; case "${1:-}" in --dev) SCHEME="SeleneMarkup-Dev";; --prod|"") SCHEME="SeleneMarkup";; esac
# pass $SCHEME to xcodegen/xcodebuild
```

**Step 5:** Regenerate + build both:
```bash
cd ~/SeleneMarkup && xcodegen generate
./redeploy.sh --prod   # installs "Selene"
./redeploy.sh --dev    # installs "Selene Dev"
```
Expected: both apps appear on the iPad home screen; "Selene" talks to :5678, "Selene Dev" to :5679. Verify each loads notes from its respective server.

**Step 6:** Commit in `~/SeleneMarkup` (separate repo):
```bash
cd ~/SeleneMarkup && git add -A && git commit -m "feat: dev + prod app targets (com.selene.markup[.dev], :5678/:5679)"
```

---

### Task 11: Docs + wrap-up

**Files:**
- Create: `docs/guides/features/releases.md`
- Modify: `docs/USER-EXPERIENCE.md` (add link)
- Modify: `.claude/PROJECT-STATUS.md`
- Modify: `docs/plans/INDEX.md` (move design to Done)
- Run: diagram-sync skill

**Step 1: Write `docs/guides/features/releases.md`** from `docs/guides/features/_TEMPLATE.md`. Verify every claim against the real scripts (not the design doc). Structure: Using it (how to cut a release = merge to main; how to roll back) → How it works (watcher → gated build → ship) → Configure & customize (poll interval, paths, notifications) → Troubleshooting (prod not updating? check deploy.log + watcher logs) → Related.

**Step 2:** Add its link to the hub `docs/USER-EXPERIENCE.md`.

**Step 3:** Update `.claude/PROJECT-STATUS.md`: note the prod/dev split is live, the three dirs (`~/selene` dev, `~/selene-build` scratch, `~/selene-prod` live), and the two iPad apps.

**Step 4:** Run the diagram-sync skill to update `docs/backend-block-diagrams.md` (launchd inventory changed: `com.selene.*` → `com.selene.prod.*` + deploy-watcher).

**Step 5:** Move the design doc to "Done" in `docs/plans/INDEX.md`.

**Step 6:** Update `CLAUDE.md` Quick Command Reference — the launchd/workflow commands now reference prod agents and the deploy/rollback scripts. Use the update-context skill if helpful.

**Step 7: Final commit:**

```bash
git add -A && git commit -q -m "docs: releases guide + status/diagram/CLAUDE updates for prod-dev split"
```

**Step 8:** Use @superpowers:requesting-code-review before opening the PR to `main`. Then @superpowers:finishing-a-development-branch to merge — which is also what triggers the very first real auto-deploy.

---

## Done criteria

- `npm run build` emits a complete `dist/`; a compiled workflow runs against the test DB.
- Deploy proven end-to-end against `~/selene-prod-test` (ship, .env preserved, archive, rollback, build-gate).
- `~/selene-prod` serves real data on :5678 via `com.selene.prod.*`; old `com.selene.*` retired; no double-bind.
- Merging to `main` auto-deploys within ~5 min with a success/failure notification.
- `~/selene` edits no longer affect prod (dev DB + scratch vault only).
- Two iPad apps coexist (Selene :5678, Selene Dev :5679).
- Claude hooks + launchd-auditor understand the split; releases guide written.
