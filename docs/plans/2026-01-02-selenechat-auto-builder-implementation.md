# SeleneChat Auto-Builder Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a git post-merge hook that automatically builds and installs SeleneChat to /Applications when SeleneChat files change.

**Architecture:** Shell script triggered by git post-merge hook. Detects if SeleneChat/ files changed, runs existing build-app.sh, copies result to /Applications, sends macOS notification.

**Tech Stack:** Bash, git hooks, osascript (macOS notifications)

---

## Task 1: Create the Post-Merge Hook Script

**Files:**
- Create: `scripts/hooks/post-merge`

**Step 1: Create the hook script with change detection**

```bash
#!/bin/bash
# Post-merge hook: Auto-build SeleneChat when its files change

set -e

# Only proceed if SeleneChat files changed in the merge
if ! git diff-tree -r --name-only ORIG_HEAD HEAD 2>/dev/null | grep -q "^SeleneChat/"; then
    exit 0
fi

echo "SeleneChat files changed - triggering auto-build..."

# Get repo root and set paths
REPO_ROOT="$(git rev-parse --show-toplevel)"
LOG_FILE="$HOME/.selenechat-build.log"
APP_SOURCE="$REPO_ROOT/SeleneChat/.build/release/SeleneChat.app"
APP_DEST="/Applications/SeleneChat.app"

# Build SeleneChat
cd "$REPO_ROOT/SeleneChat"

if ./build-app.sh > "$LOG_FILE" 2>&1; then
    # Success: install to Applications
    rm -rf "$APP_DEST"
    cp -R "$APP_SOURCE" "$APP_DEST"
    osascript -e 'display notification "Build complete" with title "SeleneChat Updated ✓"'
    echo "SeleneChat installed to $APP_DEST"
else
    # Failure: keep old app, notify with error
    osascript -e 'display notification "Check ~/.selenechat-build.log" with title "SeleneChat Build Failed ✗"'
    echo "Build failed - see $LOG_FILE for details"
    exit 1
fi
```

**Step 2: Make the script executable**

Run: `chmod +x scripts/hooks/post-merge`

**Step 3: Verify script syntax**

Run: `bash -n scripts/hooks/post-merge`
Expected: No output (syntax OK)

**Step 4: Commit**

```bash
git add scripts/hooks/post-merge
git commit -m "feat(scripts): add post-merge hook for SeleneChat auto-build

Automatically builds and installs SeleneChat to /Applications when
SeleneChat/ files change during a merge:
- Change detection via git diff-tree
- Builds using existing build-app.sh
- macOS notifications for success/failure
- Logs to ~/.selenechat-build.log on failure

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Create the Setup Script

**Files:**
- Create: `scripts/setup-hooks.sh`

**Step 1: Create the setup script**

```bash
#!/bin/bash
# Setup script: Install git hooks for selene

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_SOURCE="$REPO_ROOT/scripts/hooks"
HOOKS_TARGET="$REPO_ROOT/.git/hooks"

echo "Installing git hooks..."

# Install post-merge hook
if [ -f "$HOOKS_SOURCE/post-merge" ]; then
    if [ -L "$HOOKS_TARGET/post-merge" ] || [ -f "$HOOKS_TARGET/post-merge" ]; then
        echo "  post-merge: already exists (skipping)"
    else
        ln -s "$HOOKS_SOURCE/post-merge" "$HOOKS_TARGET/post-merge"
        echo "  post-merge: installed ✓"
    fi
else
    echo "  post-merge: source not found (skipping)"
fi

echo ""
echo "Hook setup complete!"
echo "The post-merge hook will auto-build SeleneChat when its files change."
```

**Step 2: Make the script executable**

Run: `chmod +x scripts/setup-hooks.sh`

**Step 3: Verify script syntax**

Run: `bash -n scripts/setup-hooks.sh`
Expected: No output (syntax OK)

**Step 4: Commit**

```bash
git add scripts/setup-hooks.sh
git commit -m "feat(scripts): add setup-hooks.sh for one-time hook installation

Creates symlink from .git/hooks/post-merge to scripts/hooks/post-merge.
Run once after cloning to enable auto-build functionality.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Test the Setup Script

**Step 1: Run setup script**

Run: `./scripts/setup-hooks.sh`
Expected output:
```
Installing git hooks...
  post-merge: installed ✓

Hook setup complete!
The post-merge hook will auto-build SeleneChat when its files change.
```

**Step 2: Verify symlink created**

Run: `ls -la .git/hooks/post-merge`
Expected: Symlink pointing to `../../scripts/hooks/post-merge`

**Step 3: Run setup again (idempotent check)**

Run: `./scripts/setup-hooks.sh`
Expected output includes: `post-merge: already exists (skipping)`

---

## Task 4: Test the Hook (Manual Simulation)

**Step 1: Simulate ORIG_HEAD for testing**

Run:
```bash
# Save current HEAD as ORIG_HEAD (simulates post-merge state)
git rev-parse HEAD > .git/ORIG_HEAD
```

**Step 2: Test change detection (no SeleneChat changes)**

Run:
```bash
# Create a dummy commit with non-SeleneChat file
echo "test" > /tmp/test-hook.txt
ORIG_HEAD=$(cat .git/ORIG_HEAD)

# Simulate the check (should find no SeleneChat changes)
git diff-tree -r --name-only $ORIG_HEAD HEAD | grep -q "^SeleneChat/" && echo "Would build" || echo "Would skip"
```
Expected: `Would skip`

**Step 3: Test the hook directly (will trigger real build)**

Run:
```bash
# Force a test by temporarily modifying detection
# This will actually build and install
.git/hooks/post-merge
```
Expected: Either "SeleneChat files changed..." message OR silent exit (depending on recent changes)

**Step 4: Verify /Applications/SeleneChat.app exists (if build ran)**

Run: `ls -la /Applications/SeleneChat.app`
Expected: App bundle exists with recent timestamp

---

## Task 5: Update BRANCH-STATUS.md

**Files:**
- Modify: `BRANCH-STATUS.md`

**Step 1: Update planning stage to complete**

Change:
```markdown
### Planning
- [x] Design doc exists and approved
- [x] Conflict check completed (no overlapping work)
- [x] Dependencies identified and noted
- [x] Branch and worktree created
- [x] Implementation plan written (superpowers:writing-plans)
```

**Step 2: Update dev stage**

Change:
```markdown
### Dev
- [x] Tests written first (superpowers:test-driven-development)
- [x] Core implementation complete
- [x] All tests passing
- [x] No linting/type errors
- [x] Code follows project patterns
```

**Step 3: Update current stage**

Change: `**Current Stage:** testing`

**Step 4: Commit**

```bash
git add BRANCH-STATUS.md
git commit -m "checkpoint: dev stage complete

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Manual Integration Test

**Step 1: Make a trivial SeleneChat change**

Run:
```bash
# Add a comment to a Swift file
echo "// Auto-builder test $(date)" >> SeleneChat/Sources/App/SeleneChatApp.swift
git add SeleneChat/Sources/App/SeleneChatApp.swift
git commit -m "test: trigger auto-builder"
```

**Step 2: Create test branch and merge**

Run:
```bash
# Create a test branch from one commit back
git checkout -b test-auto-builder HEAD~1
git checkout -  # back to infra/auto-builder
git merge test-auto-builder
```

**Step 3: Observe hook execution**

Expected:
- Terminal shows "SeleneChat files changed - triggering auto-build..."
- Build runs (~17 seconds)
- macOS notification: "SeleneChat Updated ✓"
- `/Applications/SeleneChat.app` updated

**Step 4: Clean up test**

Run:
```bash
git branch -d test-auto-builder
git reset --soft HEAD~1  # undo the test commit
git checkout SeleneChat/Sources/App/SeleneChatApp.swift  # restore file
```

**Step 5: Update testing stage in BRANCH-STATUS.md**

Mark testing items complete and update stage to `docs`.

---

## Task 7: Documentation

**Files:**
- Modify: `scripts/CLAUDE.md` (if exists) OR create note in commit

**Step 1: Document in commit message (minimal approach)**

The setup-hooks.sh script is self-documenting. No additional docs needed beyond:
- Design doc: `docs/plans/2026-01-02-selenechat-auto-builder-design.md`
- Script comments

**Step 2: Update BRANCH-STATUS.md docs stage**

Mark docs items as complete (N/A for most - no workflow, no interface change).

**Step 3: Commit checkpoint**

```bash
git add BRANCH-STATUS.md
git commit -m "checkpoint: docs stage complete

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Success Criteria

After completing all tasks:
- [ ] `scripts/hooks/post-merge` exists and is executable
- [ ] `scripts/setup-hooks.sh` exists and is executable
- [ ] Running `./scripts/setup-hooks.sh` creates symlink
- [ ] Merging SeleneChat changes triggers build
- [ ] macOS notification appears on success
- [ ] Failed builds show notification with log path
- [ ] `/Applications/SeleneChat.app` contains latest build
