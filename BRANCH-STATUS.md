# Branch Status: phase-X.Y/feature-name

**Created:** YYYY-MM-DD
**Design Doc:** docs/plans/YYYY-MM-DD-design.md
**Current Stage:** planning
**Last Rebased:** YYYY-MM-DD

## Overview

Brief description of what this branch implements.

## Dependencies

- List any dependencies on other branches or external factors
- None | Waiting on phase-X.Y | Requires [external thing]

---

## Stages

### Planning
- [ ] Design doc exists and approved
- [ ] Conflict check completed (no overlapping work)
- [ ] Dependencies identified and noted
- [ ] Branch and worktree created
- [ ] Implementation plan written (superpowers:writing-plans)

### Dev
- [ ] Tests written first (superpowers:test-driven-development)
- [ ] Core implementation complete
- [ ] All tests passing
- [ ] No linting/type errors
- [ ] Code follows project patterns

### Testing
- [ ] Unit tests pass
- [ ] Integration tests pass (if applicable)
- [ ] Manual testing completed
- [ ] Edge cases verified
- [ ] Verified with superpowers:verification-before-completion

### Docs
- [ ] workflow STATUS.md updated (if workflow changed)
- [ ] README updated (if interface changed)
- [ ] Roadmap docs updated
- [ ] Code comments where needed
- [ ] User-facing change? If yes: feature guide created/updated in `docs/guides/features/` + hub link added

### Review
- [ ] Requested review (superpowers:requesting-code-review)
- [ ] Review feedback addressed
- [ ] Changes approved

### Ready
- [ ] Rebased on latest main
- [ ] Final test pass after rebase
- [ ] BRANCH-STATUS.md fully checked
- [ ] Ready for merge

---

## Notes

Running notes, decisions, questions, etc.

---

## Blocked Items

Move any blocked checklist items here with reason:

- [ ] BLOCKED: [Item] - [Reason]

## Findings during execution

- **Task 1 finding (pre-existing, not introduced here):** `SELENE_ENV=test` is unreachable from the CLI. `src/lib/config.ts:10-11` loads `.env.development` with `override:true` whenever `SELENE_ENV !== 'production'`, and `.env.development` sets `SELENE_ENV=development` — clobbering a CLI `SELENE_ENV=test`. Impact: the `test` tier is dead; `development` and `production` work. Our prod/dev split is unaffected (prod uses `production` which skips the override; dev uses `development`). Do NOT build verification that relies on `SELENE_ENV=test` selecting `data-test/`. Fix is out of scope for this branch.
