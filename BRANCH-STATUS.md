# Branch Status: feat/obsidian-feedback-loop

**Created:** 2026-06-10
**Design Doc:** docs/plans/2026-06-10-obsidian-feedback-loop-design.md
**Plan:** docs/plans/2026-06-10-obsidian-feedback-loop-plan.md
**Current Stage:** dev
**Last Rebased:** 2026-06-10 (branched from local main @ 1c5e535)

## Overview

Phase 1 of the Obsidian feedback loop: a `## ✍️ Your note` section in every exported
note where the user types free-text intent; a new `vault-feedback` workflow (15-min
launchd) ingests it into a precious `facts.note_feedback` table, re-pends the note so
process-llm re-derives its filing with the intent in-prompt, and the exporter renders
the feedback back as an applied-✓ block (preserve-on-render guard).

## Dependencies

- None (fact-store Ph1+Ph2 already LIVE; constellation Phase A already shipped)

---

## Stages

### Planning
- [x] Design doc exists and approved
- [x] Conflict check completed (no overlapping in-flight work; pkm-browse Track 3 touches export-obsidian.ts but is not active)
- [x] Dependencies identified and noted
- [x] Branch and worktree created
- [x] Implementation plan written (superpowers:writing-plans)

### Dev
- [ ] Tests written first (superpowers:test-driven-development)
- [ ] Core implementation complete
- [ ] All tests passing
- [ ] No linting/type errors
- [ ] Code follows project patterns

### Testing
- [ ] Unit tests pass
- [ ] Integration tests pass (if applicable)
- [ ] Manual testing completed (dev-sandbox e2e — plan Task 9)
- [ ] Edge cases verified
- [ ] Verified with superpowers:verification-before-completion

### Docs
- [ ] User guide created (docs/guides/features/obsidian-feedback.md) + hub link
- [ ] SYSTEM-MAP regenerated
- [ ] docs/plans/INDEX.md status updated

### Review
- [ ] Code review requested (superpowers:requesting-code-review)
- [ ] Review feedback addressed

### Ready
- [ ] Final verification gate green (tsc + jest + map-drift)
- [ ] Merge decision (superpowers:finishing-a-development-branch)
- [ ] Post-merge operator step recorded: `./scripts/install-prod.sh` to load the NEW com.selene.prod.vault-feedback agent (deploy-prod.sh only restarts existing agents)
