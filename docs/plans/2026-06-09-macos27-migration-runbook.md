# macOS 27 Wipe + Rebuild Runbook — Selene Dev Machine

**Date:** 2026-06-09
**Status:** Active runbook (one-time migration)
**Companion to:** `2026-06-09-macos27-apple-native-reevaluation-design.md` (the *why*; this is the *how*)
**Machine:** Mac mini (Apple Silicon), becoming a dedicated **dev-first** machine on macOS 27 beta.

---

## ⚠️ Read this first — survives-the-wipe rule

After you erase the boot drive, **everything on `Macintosh HD` is gone**, including this file's local copy. This runbook lives in two places you can still reach from a wiped machine:

1. **GitHub** — branch `docs/macos27-reevaluation`, file `docs/plans/2026-06-09-macos27-migration-runbook.md`. Readable from your phone or any browser.
2. **The Extended drive** — `/Volumes/Extended/selene-backup-2026-06-09/RUNBOOK.md`.

**Keep your phone handy** to read this while the machine reinstalls.

---

## The three copies (your safety net — already verified 2026-06-09)

| What | Where | Status |
|------|-------|--------|
| All code (selene, Lumen, SeleneMarkup) | GitHub | ✅ pushed, 0 unpushed |
| Notes + secrets (`selene-data`, `selene-data-dev`, `.env*`) | `/Volumes/Extended/selene-backup-2026-06-09/` | ✅ verified — facts.db `ok` / 310 notes |
| Obsidian vault | iCloud | ✅ auto-syncs |

If any row above is not ✅ when you start, **stop and fix it first.**

---

## Phase 0 — Final pre-wipe (do these RIGHT before erasing)

- [ ] **Re-verify the backup is current.** Prod has likely written new notes since 2026-06-09. If it's now a later date, refresh the backup:
  ```bash
  SELENE_GUARD_OFF=1 sh -c '
    DEST=/Volumes/Extended/selene-backup-$(date +%Y-%m-%d) &&
    mkdir -p "$DEST" &&
    cp -Rp ~/selene-data ~/selene-data-dev "$DEST"/ &&
    cp -p ~/selene/.env ~/selene/.env.development "$DEST"/ &&
    echo "BACKED UP TO $DEST"'
  ```
  Then verify: `SELENE_GUARD_OFF=1 sqlite3 "$DEST/selene-data/facts.db" "PRAGMA integrity_check; SELECT COUNT(*) FROM captured_notes;"`
- [ ] **Copy this runbook to Extended** so it's readable post-wipe:
  ```bash
  cp ~/selene/docs/plans/2026-06-09-macos27-migration-runbook.md /Volumes/Extended/selene-backup-2026-06-09/RUNBOOK.md
  ```
- [ ] **(Optional, saves ~30 GB of re-downloads) Copy your Ollama models to Extended:**
  ```bash
  cp -Rp ~/.ollama /Volumes/Extended/selene-backup-2026-06-09/ollama-models
  ```
  Selene only strictly needs `mistral:7b` + `nomic-embed-text`; the rest (qwen2.5vl, olmocr2, minicpm-v, granite-vision) are the eink/OCR pipeline. Copying the whole `~/.ollama` folder preserves all of them.
- [ ] **Write down the accounts you'll need to re-auth** (see Phase 2 inventory below). The big ones: Apple ID, GitHub, Tailscale, Apple Developer (for the beta + Xcode signing).
- [ ] **Eject and physically note your drives.** `Extended` = your backup. `Elements` = Time Machine. You will NOT erase either.

---

## Phase 1 — Wipe + install macOS 27 beta

- [ ] **Enroll in the beta:** sign in at developer.apple.com with your Apple Developer account → download the macOS 27 beta access (or the beta installer / "Upgrade Now" via Settings after enrolling).
- [ ] **Erase ONLY the internal disk.** In Disk Utility (Recovery mode: hold power → Options), select **`Macintosh HD`** and erase as **APFS**.
  - 🚨 **Do NOT select `Elements` or `Extended`.** Your entire backup is on `Extended`. Erasing the wrong disk is the one unrecoverable mistake here. When in doubt, physically unplug the external drives before erasing, and re-plug after.
- [ ] **Install macOS 27 beta** onto the freshly-erased internal disk.
- [ ] **First-boot setup:** sign into your **Apple ID** (this starts the iCloud → Obsidian vault re-sync in the background). FileVault is optional for a dev machine; your call.

---

## Phase 2 — Reinstall the toolchain

Accounts/tools to re-auth as you go (the inventory that bites non-engineers):

| Tool | Re-auth command / action |
|------|--------------------------|
| Apple ID / iCloud | System Settings → sign in (done in Phase 1) |
| Xcode | App Store or developer.apple.com (beta Xcode for macOS 27) |
| Homebrew | reinstall (below) |
| GitHub | `gh auth login` |
| Tailscale | install app → sign in (mesh: mini is `100.111.6.10`) |
| Ollama | reinstall + re-pull or restore models |

Steps:

- [ ] **Xcode + Command Line Tools** (needed for Swift/Lumen, signing, and native module compiles):
  ```bash
  xcode-select --install        # CLT; install full Xcode from the App Store / developer portal too
  ```
- [ ] **Homebrew** (Apple Silicon, installs to `/opt/homebrew`):
  ```bash
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```
- [ ] **Node v22** (match what you ran before — v22.18.0):
  ```bash
  brew install node@22      # or: brew install nvm && nvm install 22
  node --version            # expect v22.x
  ```
- [ ] **gh + git auth:**
  ```bash
  brew install gh && gh auth login
  ```
- [ ] **Tailscale:** install the app, sign in, confirm the mini comes up on the mesh.
- [ ] **Ollama + models:**
  ```bash
  brew install ollama && brew services start ollama
  # EITHER restore from Extended (fast):
  cp -Rp /Volumes/Extended/selene-backup-2026-06-09/ollama-models/* ~/.ollama/
  # OR re-pull the Selene-critical pair fresh:
  ollama pull mistral:7b && ollama pull nomic-embed-text
  ollama list   # confirm models present
  ```

---

## Phase 3 — Restore Selene (dev-first)

- [ ] **Clone the repos:**
  ```bash
  cd ~ && gh repo clone SlowSpeedChase/selene
  gh repo clone SlowSpeedChase/Lumen
  gh repo clone SlowSpeedChase/SeleneMarkup
  ```
- [ ] **Restore data + secrets from Extended:**
  ```bash
  BK=/Volumes/Extended/selene-backup-2026-06-09
  cp -Rp "$BK/selene-data" ~/selene-data
  cp -Rp "$BK/selene-data-dev" ~/selene-data-dev
  cp -p "$BK/.env" "$BK/.env.development" ~/selene/
  ```
  (`~/selene-data/facts.db` is the precious append-only note store; `selene.db` is regenerable.)
- [ ] **Install deps — this recompiles `better-sqlite3` against macOS 27 + new Node.** This is the **#1 likely breakage**. If it fails, it's almost always a native-build issue (Xcode CLT not installed, or Node version mismatch):
  ```bash
  cd ~/selene && npm install
  # if better-sqlite3 errors: confirm `xcode-select -p` resolves, Node is v22, then:
  npm rebuild better-sqlite3
  ```
- [ ] **Get the design doc + this runbook into your working tree.** They're on a branch, not `main`:
  ```bash
  cd ~/selene && git fetch origin && git checkout docs/macos27-reevaluation
  ```
- [ ] **Decide: do you bring PROD back online now?** Per the design, **prod can stay offline during the transition** — you're a dev-first machine proving out macOS 27. Recommended: **do NOT reinstall the prod launchd agents yet.** Develop against the **dev** sandbox first. Only later, when you deliberately want prod scheduling back:
  ```bash
  # ONLY when you intend to run prod again:
  # cd ~/selene-prod && ... (rebuild dist/) ; ./scripts/install-launchd.sh
  ```
  ⚠️ Reminder: **pushing `main` to origin IS a prod deploy** (the watcher reacts within ~5 min). Stay on branches while experimenting.

---

## Phase 4 — Verify you're back to developing

- [ ] **Gates pass:** `cd ~/selene && npx tsc --noEmit && npm test`
- [ ] **Dev DB reads cleanly:**
  ```bash
  sqlite3 ~/selene-data-dev/selene.db "SELECT COUNT(*) FROM raw_notes;"
  ```
- [ ] **Run one dev batch** (manual, dev-first — no prod agents):
  ```bash
  SELENE_ENV=development ./scripts/dev-process-batch.sh --status
  SELENE_ENV=development ./scripts/dev-process-batch.sh
  ```
- [ ] **Obsidian vault re-synced** from iCloud (check `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Selene`).
- [ ] **Lumen builds:** `cd ~/Lumen && swift build` (confirms Swift toolchain + signing are alive).

When all of the above pass, **you're back to developing.**

---

## Phase 5 — The point of all this: the macOS 27 validation spike

This is *why* you wiped — to test whether Apple-native inference is good enough to be Lumen's engine. Run it against the **dev showcase corpus only** (`test_run='dev-seed'`), never prod notes.

- [ ] **`fm` CLI quality test vs `mistral:7b`** — same concept-extraction prompt on the same dev notes through both; compare output quality (the keystone "on-device good enough?" measurement).
- [ ] **`NLContextualEmbedding` clustering-parity** — does Apple's on-device 512-dim embedding cluster the dev corpus as coherently as `nomic-embed`? (Swift spike.)
- [ ] **Feed results into Lumen's design** and promote the spike section of the design doc from Vision → Ready (then `writing-plans`).

See the design doc's "Near-term spike" section for the full framing.

---

## If something breaks — quick triage

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `npm install` fails on better-sqlite3 | Xcode CLT missing or Node ≠ v22 | `xcode-select --install`; reinstall Node v22; `npm rebuild better-sqlite3` |
| `ollama` commands hang / model not found | service not started or models not restored | `brew services start ollama`; `ollama list`; re-pull |
| Obsidian vault empty | iCloud still syncing | wait; confirm Apple ID signed in; check iCloud Drive status |
| `git push` triggered a prod deploy unexpectedly | you pushed `main` | stay on branches; prod watcher only reacts to `origin/main` |
| Can't read this runbook | it's on a branch | GitHub web → branch `docs/macos27-reevaluation`, or `/Volumes/Extended/.../RUNBOOK.md` |

---

## Related

- `2026-06-09-macos27-apple-native-reevaluation-design.md` — the strategy (Path B, guardrails, availability gap)
- `CLAUDE.md` — prod/dev split, deploy-watcher, the data guard
- Memory: `project_macos27_apple_native`, `feedback_db_path`, `project_prod_dev_split`
