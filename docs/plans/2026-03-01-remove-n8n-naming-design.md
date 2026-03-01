# Remove n8n from Project Naming

**Date:** 2026-03-01
**Status:** Ready
**Topic:** infra, naming

---

## Problem

The project directory, GitHub repo, package.json, Swift source files, launchd plists, and documentation all reference "selene-n8n" — a name from when the project used n8n for workflow automation. n8n was replaced with a native TypeScript + Fastify backend in January 2026. The name is misleading and should be cleaned up.

## Decision

Rename everything from `selene-n8n` to `selene`.

## Approach

**Code-first, then directory rename.** All file content changes happen while still in `~/selene-n8n/` (valid git state), committed, then the directory and GitHub repo are renamed as final steps.

## Scope of Changes

### Phase 1: Code Updates (in `~/selene-n8n/`, on feature branch)

**Swift source files** — find-and-replace `/selene-n8n/` to `/selene/`:
- `SeleneChat/Sources/SeleneChat/Services/ObsidianService.swift`
- `SeleneChat/Sources/SeleneChat/Services/ThingsURLService.swift`
- `SeleneChat/Sources/SeleneChat/Services/WorkflowRunner.swift`
- `SeleneChat/Sources/SeleneChat/Services/SubprojectSuggestionService.swift`
- `SeleneChat/Sources/SeleneChat/Services/ThingsStatusService.swift`
- `SeleneChat/Sources/SeleneShared/Models/ScheduledWorkflow.swift`
- `SeleneChat/Tests/ManualIntegrationTest.swift`
- `SeleneChat/Tests/SeleneChatTests/Models/ScheduledWorkflowTests.swift`

**launchd plists** — find-and-replace `selene-n8n` to `selene` in all 16 plist files (47 references total).

**package.json** — update `name` to `selene`, update `description` to remove "n8n", remove `"n8n"` from keywords.

**.claude/ config files** — update `selene-n8n` to `selene` in:
- `.claude/settings.json` — hook command path
- `.claude/skills/run-workflow/SKILL.md` — workflow runner path
- `.claude/skills/launchd-check/SKILL.md` — log paths (3 references)
- `.claude/agents/documentation-agent.md` — directory tree
- `.claude/agents/doc-maintainer.md` — directory tree
- `.claude/CURRENT-ENV.md` — old container name references
- `.claude/PROJECT-STATUS.md` — location reference

**Scripts** — update `selene-n8n` to `selene` in:
- `scripts/verify-production-clean.sh` — database path
- `scripts/clean-production-database.sh` — database + backup paths
- `scripts/setup-git-hooks.sh` — project root path
- `scripts/setup-hooks.sh` — comment
- `scripts/CLAUDE.md` — Docker container references (historical, update for consistency)

**CLAUDE.md** — directory tree diagram + version history entry

**Documentation** — batch replace `selene-n8n` path references across 62 files in `docs/`

**Cleanup** — delete `.n8n-local/` directory (dead Docker artifacts). Remove stale worktrees.

### Phase 2: Merge

Merge feature branch to main.

### Phase 3: Infrastructure (post-merge, manual)

1. `gh repo rename selene` — rename GitHub repository
2. `cd ~ && mv selene-n8n selene` — rename local directory
3. `cd ~/selene && git remote set-url origin https://github.com/SlowSpeedChase/selene.git`
4. `git push` — verify remote works
5. `./scripts/install-launchd.sh` — reinstall launchd agents with corrected paths
6. `cd SeleneChat && ./build-app.sh && cp -R .build/release/SeleneChat.app /Applications/` — rebuild SeleneChat
7. `curl http://localhost:5678/health` — verify server
8. Update Claude Code project path reference

### Not Changing

- `archive/n8n-workflows/` — historical record, clearly marked as archived
- Historical design docs (`n8n-replacement-design.md`, etc.) — preserved as records
- `.claude/DECISIONS-LOG.md`, `.claude/DEVELOPMENT.md` — historical mentions of n8n technology stay (they describe why n8n was replaced, not file paths)

## Acceptance Criteria

- [ ] No file in active codebase references `/selene-n8n/` as a path
- [ ] `swift build` succeeds after path updates
- [ ] GitHub repo is named `selene`
- [ ] Local directory is `~/selene/`
- [ ] `git push` works with new remote URL
- [ ] All launchd agents start successfully
- [ ] Server responds at `http://localhost:5678/health`
- [ ] SeleneChat launches and functions correctly

## ADHD Check

- Reduces friction? Yes — no more confusing legacy naming
- Visible? N/A — infrastructure change
- Externalizes cognition? Yes — name matches reality

## Scope Check

Estimated: < 1 day. Mostly mechanical find-and-replace with a few manual infrastructure steps.

## Risks

- **Worktrees:** Any active `.worktrees/` directories will have stale paths after the directory rename. Should be cleaned up before Phase 3.
- **Claude Code:** The `.claude/projects/` path includes `selene-n8n` and needs updating.
- **Third-party references:** Any bookmarks, terminal aliases, or scripts outside this repo that reference `~/selene-n8n/` will need manual updates.
