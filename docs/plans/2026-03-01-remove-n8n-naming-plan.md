# Remove n8n from Project Naming — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove all "selene" references from the codebase, renaming to "selene".

**Architecture:** Global find-and-replace of path references in code, config, and docs — done while still in the `~/selene/` directory (valid git state). Directory and GitHub rename happen as final manual steps after merge.

**Tech Stack:** sed (batch replace), Swift (verify build), launchd (reinstall agents), gh CLI (repo rename)

**Design doc:** `docs/plans/2026-03-01-remove-n8n-naming-design.md`

---

## Task 1: Swift Source Files — Replace Paths

**Files:**
- Modify: `SeleneChat/Sources/SeleneChat/Services/ObsidianService.swift` (line 10)
- Modify: `SeleneChat/Sources/SeleneChat/Services/ThingsURLService.swift` (lines 21, 22, 251)
- Modify: `SeleneChat/Sources/SeleneChat/Services/WorkflowRunner.swift` (lines 23, 28)
- Modify: `SeleneChat/Sources/SeleneChat/Services/SubprojectSuggestionService.swift` (lines 209, 253)
- Modify: `SeleneChat/Sources/SeleneChat/Services/ThingsStatusService.swift` (lines 18, 19, 21)
- Modify: `SeleneChat/Sources/SeleneShared/Models/ScheduledWorkflow.swift` (lines 65, 67, 75)
- Modify: `SeleneChat/Tests/ManualIntegrationTest.swift` (line 45)
- Modify: `SeleneChat/Tests/SeleneChatTests/Models/ScheduledWorkflowTests.swift` (line 559)

**Step 1: Replace all occurrences in each Swift file**

In each file listed above, replace every occurrence of `selene` with `selene`. This covers:
- Hardcoded paths like `/Users/chaseeasterling/selene/...`
- Comments referencing the project name
- Test assertions checking the project root path

Use `replace_all` on each file with:
- old: `selene`
- new: `selene`

**Step 2: Verify Swift build compiles**

```bash
cd SeleneChat && swift build 2>&1 | tail -20
```

Expected: Build succeeds with no errors.

**Step 3: Run Swift tests**

```bash
cd SeleneChat && swift test 2>&1 | tail -30
```

Expected: All tests pass. The `ScheduledWorkflowTests` test at line 559 now asserts `selene` instead of `selene`.

**Step 4: Commit**

```bash
git add SeleneChat/
git commit -m "refactor: update Swift source paths from selene to selene"
```

---

## Task 2: launchd Plists — Replace Paths

**Files:**
- Modify: All 16 files in `launchd/` directory (47 total references)
- Modify: `scripts/things-bridge/com.selene.things-bridge.plist` (4 references)
- Modify: `scripts/things-bridge/com.selene.projects-bridge.plist` (4 references)

**Step 1: Replace in all launchd plist files**

In every `.plist` file under `launchd/` and `scripts/things-bridge/`, replace all occurrences of `selene` with `selene`.

These are XML files with paths like:
```xml
<string>/Users/chaseeasterling/selene</string>
<string>/Users/chaseeasterling/selene/logs/process-llm.log</string>
```

Becomes:
```xml
<string>/Users/chaseeasterling/selene</string>
<string>/Users/chaseeasterling/selene/logs/process-llm.log</string>
```

**Step 2: Verify plist XML is valid**

```bash
for f in launchd/*.plist scripts/things-bridge/*.plist; do plutil -lint "$f"; done
```

Expected: All files report "OK".

**Step 3: Commit**

```bash
git add launchd/ scripts/things-bridge/*.plist
git commit -m "refactor: update launchd plist paths from selene to selene"
```

---

## Task 3: package.json — Update Name and Description

**Files:**
- Modify: `package.json` (lines 2, 3, keywords array)

**Step 1: Update package.json fields**

Change:
```json
"name": "selene",
"description": "ADHD-focused knowledge management system using n8n workflows",
```

To:
```json
"name": "selene",
"description": "ADHD-focused knowledge management system",
```

Also remove `"n8n"` from the `keywords` array.

**Step 2: Verify package.json is valid JSON**

```bash
node -e "JSON.parse(require('fs').readFileSync('package.json','utf8')); console.log('Valid JSON')"
```

Expected: "Valid JSON"

**Step 3: Commit**

```bash
git add package.json
git commit -m "refactor: update package.json name from selene to selene"
```

---

## Task 4: .claude/ Config Files — Replace Paths

**Files:**
- Modify: `.claude/settings.json` (line 20 — hook command path)
- Modify: `.claude/skills/run-workflow/SKILL.md` (line 48)
- Modify: `.claude/skills/launchd-check/SKILL.md` (lines 46, 51, 78)
- Modify: `.claude/agents/documentation-agent.md` (line 53 — directory tree)
- Modify: `.claude/agents/doc-maintainer.md` (line 19 — directory tree)
- Modify: `.claude/CURRENT-ENV.md` (lines 16, 17)
- Modify: `.claude/PROJECT-STATUS.md` (line 15)

**Step 1: Replace all occurrences in each file**

In each file listed above, replace every occurrence of `selene` with `selene`.

Key changes:
- `.claude/settings.json`: Hook command `cd /Users/chaseeasterling/selene &&` → `cd /Users/chaseeasterling/selene &&`
- `.claude/skills/run-workflow/SKILL.md`: Same path pattern
- `.claude/skills/launchd-check/SKILL.md`: Log file paths
- `.claude/agents/*.md`: Directory tree diagrams
- `.claude/CURRENT-ENV.md`: Container name column (historical but should reflect current state)
- `.claude/PROJECT-STATUS.md`: Location line

**Step 2: Commit**

```bash
git add .claude/
git commit -m "refactor: update .claude/ config paths from selene to selene"
```

---

## Task 5: Scripts — Replace Paths

**Files:**
- Modify: `scripts/verify-production-clean.sh` (line 5)
- Modify: `scripts/clean-production-database.sh` (lines 7, 8)
- Modify: `scripts/setup-git-hooks.sh` (line 8)
- Modify: `scripts/setup-hooks.sh` (comment referencing project name)
- Modify: `scripts/CLAUDE.md` (lines 379, 432, 439 — historical Docker references)

**Step 1: Replace path references in script files**

In `.sh` files, replace `/Users/chaseeasterling/selene` with `/Users/chaseeasterling/selene`.

For `scripts/CLAUDE.md`, the Docker container references (`CONTAINER_NAME="selene"`, `docker exec selene`, `docker ps | grep -q selene`) are historical documentation of the old n8n Docker setup. Replace `selene` with `selene` in directory path references only. The Docker references can be left as-is since they describe the old system — OR update them all for consistency since the old Docker system is completely gone. **Decision: update all for consistency** — the scripts CLAUDE.md should reflect current reality.

**Step 2: Commit**

```bash
git add scripts/
git commit -m "refactor: update script paths from selene to selene"
```

---

## Task 6: CLAUDE.md — Update Project Entry Point

**Files:**
- Modify: `CLAUDE.md` (line 336 — directory diagram)

**Step 1: Replace directory name in tree diagram**

Change:
```
selene/
```

To:
```
selene/
```

Note: The version history entry at line 420 ("2026-01-09: Replaced n8n with TypeScript backend") is a historical fact and should NOT be changed — it describes *what happened*, not a path.

**Step 2: Add a version history entry**

Add to the Version History section:
```
- **2026-03-01**: Renamed project from selene to selene (removed legacy n8n naming)
```

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "refactor: update CLAUDE.md directory name from selene to selene"
```

---

## Task 7: Documentation — Batch Replace Path References

**Files:**
- Modify: 62 files in `docs/` directory that reference `selene`

**Step 1: Batch replace path references across all docs**

Replace `/Users/chaseeasterling/selene` with `/Users/chaseeasterling/selene` across all files in `docs/`.

Also replace standalone `selene/` (directory tree references) with `selene/` in these files.

These are historical plan documents, implementation guides, and roadmap docs. Even though many are "done", their path references should reflect the current directory name to avoid confusion if someone reads them.

**Note on Docker references:** Files like `docs/guides/recovery.md`, `docs/guides/packages.md`, `docs/guides/setup.md` contain `docker exec selene` commands. These describe the old Docker-based system. Replace `selene` here too for consistency — the entire Docker setup is archived and these docs should match the `archive/` references.

**Step 2: Verify no broken markdown**

Spot-check a few files to ensure the replacements didn't break any markdown formatting.

**Step 3: Commit**

```bash
git add docs/
git commit -m "docs: update selene references to selene across documentation"
```

---

## Task 8: Cleanup — Delete .n8n-local/ Directory

**Files:**
- Delete: `.n8n-local/` directory (old Docker artifacts — 10 log files)

**Step 1: Verify contents are just old logs**

```bash
ls -la .n8n-local/
```

Expected: Old n8n Docker log files, no active data.

**Step 2: Remove and commit**

```bash
rm -rf .n8n-local/
git add -A .n8n-local/
git commit -m "chore: delete .n8n-local/ directory (dead Docker artifacts)"
```

---

## Task 9: Clean Up Worktrees

**Step 1: List active worktrees**

```bash
git worktree list
```

**Step 2: Remove any stale worktrees**

If there are worktrees (e.g., `thread-context-isolation`), remove them before the directory rename:

```bash
git worktree remove .claude/worktrees/thread-context-isolation --force
# Repeat for any other worktrees
```

The worktree copies have their own copies of all files. After the directory rename, they'd have stale paths. Clean them up now.

**Step 3: Commit any .claude/worktrees changes if needed**

```bash
git add .claude/worktrees/ 2>/dev/null
git status
# Only commit if there are changes
```

---

## Task 10: Final Verification

**Step 1: Search for any remaining `selene` references in tracked files**

```bash
git grep 'selene' -- ':!archive/'
```

Expected: **Zero matches** outside of `archive/` directory. If any remain, fix them.

**Step 2: Verify Swift build**

```bash
cd SeleneChat && swift build 2>&1 | tail -20
```

Expected: Build succeeds.

**Step 3: Verify Swift tests**

```bash
cd SeleneChat && swift test 2>&1 | tail -30
```

Expected: All tests pass.

**Step 4: Verify plist validity**

```bash
for f in launchd/*.plist scripts/things-bridge/*.plist; do plutil -lint "$f"; done
```

Expected: All OK.

---

## Task 11: Merge to Main

**Step 1: Review all commits**

```bash
git log --oneline main..HEAD
```

Expected: 6-8 commits covering Swift, launchd, package.json, .claude/, scripts, CLAUDE.md, docs, cleanup.

**Step 2: Merge**

If working on a branch:
```bash
git checkout main
git merge rename/remove-n8n
```

Or create a PR:
```bash
gh pr create --title "Remove legacy n8n from project naming" --body "Renames selene to selene across all code, config, and docs"
```

---

## Task 12: Post-Merge Infrastructure (Manual Steps)

These steps happen AFTER merge and OUTSIDE of git. They require manual execution.

**Step 1: Rename GitHub repository**

```bash
gh repo rename selene
```

GitHub auto-redirects the old URL, so existing links won't break.

**Step 2: Rename local directory**

```bash
cd ~
mv selene selene
cd selene
```

**Step 3: Update git remote**

```bash
git remote set-url origin https://github.com/SlowSpeedChase/selene.git
git push  # Verify remote works
```

**Step 4: Reinstall launchd agents**

```bash
./scripts/install-launchd.sh
```

Verify agents are running:
```bash
launchctl list | grep selene
```

**Step 5: Restart server and verify**

```bash
launchctl kickstart -k gui/$(id -u)/com.selene.server
sleep 2
curl http://localhost:5678/health
```

Expected: Server responds with health check.

**Step 6: Rebuild and install SeleneChat**

```bash
cd SeleneChat && ./build-app.sh && cp -R .build/release/SeleneChat.app /Applications/
```

Launch SeleneChat and verify it works.

**Step 7: Update Claude Code project path**

The Claude Code project config at `~/.claude/projects/-Users-chaseeasterling-selene/` needs to be moved/recreated for the new path. This may require:

```bash
# Check what exists
ls ~/.claude/projects/ | grep selene

# The project path is auto-generated from the directory path
# Opening Claude Code in ~/selene will create a new project config
# Copy any custom settings from the old path to the new one
```

**Step 8: Update auto-memory path**

The memory file at `~/.claude/projects/-Users-chaseeasterling-selene/memory/MEMORY.md` needs to be accessible from the new project path. Copy it:

```bash
# After Claude Code creates the new project config in ~/selene:
cp -r ~/.claude/projects/-Users-chaseeasterling-selene/memory/ \
      ~/.claude/projects/-Users-chaseeasterling-selene/memory/
```

**Step 9: Verify everything end-to-end**

- [ ] `curl http://localhost:5678/health` returns OK
- [ ] `launchctl list | grep selene` shows all agents
- [ ] SeleneChat opens and responds to queries
- [ ] `git push` works
- [ ] `git grep 'selene' -- ':!archive/'` returns zero matches
