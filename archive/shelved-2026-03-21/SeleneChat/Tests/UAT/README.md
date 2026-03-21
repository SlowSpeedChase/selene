# SeleneChat UAT (User Acceptance Testing)

Interactive UI testing with Claude guiding you through structured checklists.

## How It Works

1. Complete a feature
2. Say: "UAT PlanningView" (or whichever view you changed)
3. Claude walks you through each check one at a time
4. You verify manually and report pass/fail
5. Claude generates a sign-off document

## Directory Structure

```
UAT/
├── README.md           # This file
├── checklists/         # YAML checklists per view
│   ├── PlanningView.yaml
│   ├── ChatView.yaml
│   ├── SearchView.yaml
│   └── _template.yaml  # Template for new views
└── sessions/           # Completed sign-off records
    └── 2026-01-02-planning-view.md
```

## Checklist Categories

Each view is tested across four categories:

### 1. States
- Empty state (no data)
- Loading state (fetching)
- Error state (failure)
- Populated state (normal use)
- Edge cases (long text, many items)

### 2. Interactions
- Primary actions (send, create, etc.)
- Secondary actions (edit, delete, cancel)
- Keyboard shortcuts
- Focus behavior

### 3. Bindings
- Add item → appears in UI
- Update item → UI reflects change
- Delete item → removed from UI
- External data change → UI refreshes

### 4. Visual
- Layout correct
- Text readable (not clipped)
- Indicators show right state
- Responsive to window resize

## Running a UAT Session

### Start
```
You: "UAT PlanningView"
Claude: "Starting UAT for PlanningView. First check:
         Empty State - Open Planning tab with no threads.
         Do you see 'No planning threads yet' message?"
```

### During
```
You: "yes"
Claude: "✓ Empty state passed.
         Next: Loading state - Refresh the view.
         Do you see a loading indicator briefly?"
```

### Issues Found
```
You: "no, it shows old data"
Claude: "✗ Loading state failed: shows old data instead of indicator.
         Next: ..."
```

### Complete
```
Claude: "UAT complete. Results: 11/12 passed.

         Failed:
         - Loading state: shows old data instead of indicator

         Sign-off document saved to sessions/2026-01-02-planning-view.md"
```

## Adding a New View Checklist

1. Copy `checklists/_template.yaml`
2. Rename to `ViewName.yaml`
3. Fill in view-specific checks
4. Test by running: "UAT ViewName"

## Sign-off Document Format

Each completed session generates a markdown file:

```markdown
# UAT Session: PlanningView

**Date:** 2026-01-02
**Tester:** Chase Easterling
**Feature/PR:** Phase 7.2d - AI Provider Toggle
**Result:** ✅ PASSED (12/12 checks)

## States
| Check | Result | Notes |
|-------|--------|-------|
| Empty state | ✅ Pass | |
...
```

## When to Run UAT

Per GITOPS.md, UAT is part of the **testing** stage checklist for SeleneChat features:

```markdown
### Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing completed
- [ ] Edge cases verified
- [ ] Verified with superpowers:verification-before-completion
- [ ] UAT sign-off (SeleneChat only)  ← THIS
```
