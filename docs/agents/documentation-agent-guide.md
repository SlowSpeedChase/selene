# Documentation Agent Guide

**Version:** 1.0.0
**Created:** 2025-10-31
**Purpose:** Guide to using the autonomous documentation maintenance agent

---

## Overview

The **Documentation Agent** is a Claude Code agent that autonomously monitors your Selene project and keeps all documentation up to date as code changes occur. It runs in the background and ensures documentation never falls out of sync with the codebase.

### What It Does

- **Monitors changes** in workflow files, database schema, and configuration
- **Analyzes impact** of changes on documentation
- **Updates documentation** automatically (with approval)
- **Maintains consistency** across all docs
- **Reports changes** clearly and concisely

### What It Doesn't Do

- **Change code** - It only updates documentation
- **Make assumptions** - It asks when uncertain
- **Delete content** - It preserves user-written commentary
- **Break things** - It validates before changing

---

## Quick Start

### 1. Setup (One-Time)

```bash
# Navigate to project
cd /Users/chaseeasterling/selene

# Setup Git hooks (optional but recommended)
./scripts/setup-git-hooks.sh

# Make the agent runner executable
chmod +x ./scripts/run-doc-agent.sh
```

### 2. Running the Agent

**Option A: Manual Trigger**

```bash
# From project root
./scripts/run-doc-agent.sh
```

This will show you what changed and give you a prompt to paste into Claude Code.

**Option B: Direct Invocation in Claude Code**

In the Claude Code CLI, simply say:

```
Run the documentation agent
```

Or:

```
Check if documentation needs updating
```

**Option C: Automatic (via Git Hooks)**

After setting up Git hooks, the agent will automatically notify you after commits that change relevant files.

### 3. Review and Approve

The agent will:
1. Scan for changes
2. Propose updates
3. **Wait for your approval**
4. Execute approved changes
5. Report what was done

---

## How It Works

### Architecture

```
┌─────────────────┐
│  Code Changes   │  (workflows, database, config)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Change         │  (Git hooks, file watching, manual trigger)
│  Detection      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Documentation  │  (Claude Code agent)
│  Agent          │
└────────┬────────┘
         │
         ├──────────────┐
         ▼              ▼
┌──────────────┐  ┌──────────────┐
│   Analysis   │  │  Proposal    │
└──────┬───────┘  └──────┬───────┘
       │                 │
       └────────┬────────┘
                ▼
       ┌─────────────────┐
       │  User Approval  │
       └────────┬────────┘
                ▼
       ┌─────────────────┐
       │  Documentation  │
       │  Updates        │
       └────────┬────────┘
                ▼
       ┌─────────────────┐
       │  Report         │
       └─────────────────┘
```

### Change Detection

The system monitors these files for changes:

- `workflows/*/workflow.json` - n8n workflow definitions
- `database/schema.sql` - Database structure
- `docker-compose.yml` - Container configuration
- `Dockerfile` - Build configuration
- `.env.example` - Environment variables

### Documentation Targets

When changes are detected, the agent may update:

- `README.md` files (project and workflow level)
- `STATUS.md` files (testing status and results)
- `docs/**/*.md` (all documentation)
- Architecture diagrams and examples
- Configuration references
- Timestamps and version numbers

---

## Usage Scenarios

### Scenario 1: After Adding a Workflow Node

```bash
# You added a new node to a workflow
git add workflows/02-llm-processing/workflow.json
git commit -m "Add word count calculation node"

# Git hook notifies you
# 📝 Documentation update recommended
# Run: ./scripts/run-doc-agent.sh

./scripts/run-doc-agent.sh

# Agent scans changes and proposes:
# - Update node count in README
# - Add node to reference docs
# - Update architecture diagram
```

### Scenario 2: Database Schema Update

```bash
# You added a new column
git add database/schema.sql
git commit -m "Add word_count column to processed_notes"

# Run agent
./scripts/run-doc-agent.sh

# Agent proposes:
# - Update database documentation
# - Update workflow docs that use this table
# - Update SQL examples
```

### Scenario 3: Regular Maintenance

```bash
# Weekly documentation health check
./scripts/run-doc-agent.sh --force

# Agent performs full audit:
# - Checks all timestamps
# - Validates cross-references
# - Identifies gaps
# - Suggests improvements
```

### Scenario 4: Pre-Release Check

```bash
# Before tagging a new version
./scripts/run-doc-agent.sh --force

# In Claude Code, say:
# "Run the documentation agent and perform a comprehensive audit for version 2.0 release"

# Agent will ensure:
# - All features documented
# - Version numbers current
# - Examples working
# - No broken links
```

---

## Agent Capabilities

### What It Can Detect

✅ **Workflow Changes**
- New nodes added
- Nodes removed or modified
- Connection changes
- Trigger schedule changes
- Configuration updates

✅ **Database Changes**
- New tables or columns
- Index modifications
- Schema restructuring
- Foreign key changes

✅ **Configuration Changes**
- New environment variables
- Docker configuration updates
- Dependency changes

✅ **Documentation Issues**
- Outdated timestamps
- Broken cross-references
- Invalid examples
- Missing documentation

### What It Can Update

✅ **Factual Information**
- Version numbers
- Configuration examples
- File paths
- Command syntax
- Status badges

✅ **Structural References**
- Node counts
- Architecture diagrams
- Data flow descriptions
- Integration points

✅ **Metadata**
- Last updated dates
- Test results
- Known issues
- Change logs

❌ **What It Won't Change**
- User-written explanations
- Design decisions
- Philosophical content
- Future roadmap plans

---

## Configuration

### Customizing the Agent

The agent behavior is defined in `.claude/agents/documentation-agent.md`. You can customize:

**Update Frequency**
```bash
# Edit run-doc-agent.sh to change detection logic
# Or setup a cron job for scheduled runs
```

**Change Detection Sensitivity**
```bash
# Edit setup-git-hooks.sh to monitor more/fewer file types
RELEVANT_CHANGES=$(echo "$CHANGED_FILES" | grep -E 'your-pattern-here')
```

**Documentation Scope**
```bash
# Edit documentation-agent.md to add/remove doc targets
# See "Documentation Structure" section
```

### Scheduled Runs

To run the agent daily:

```bash
# Add to crontab
crontab -e

# Add this line (runs daily at 9am)
0 9 * * * /Users/chaseeasterling/selene/scripts/run-doc-agent.sh --force >> /Users/chaseeasterling/selene/.claude/doc-agent-cron.log 2>&1
```

---

## Best Practices

### When to Run the Agent

**Always Run:**
- After adding/removing workflow nodes
- After database schema changes
- After configuration updates
- Before committing large changes
- Before version releases

**Consider Running:**
- Weekly for maintenance
- After documentation updates (to check consistency)
- When onboarding new team members (ensure docs are current)

### How to Work with the Agent

1. **Trust but Verify**
   - Review the agent's proposals
   - Check a few updated files
   - Spot-check examples

2. **Provide Feedback**
   - If updates aren't quite right, tell the agent
   - It will learn your preferences over time

3. **Be Specific**
   - "Update docs for workflow 02" is better than "update docs"
   - "Check database schema docs" is better than "check docs"

4. **Iterate**
   - Run once for analysis
   - Approve subset of changes
   - Run again for remainder

### Working with Git

```bash
# Good workflow
git add workflows/02-llm-processing/workflow.json
git commit -m "Add sentiment scoring"
./scripts/run-doc-agent.sh

# Review agent's changes
git diff

# Commit doc updates separately
git add docs/ workflows/*/README.md
git commit -m "Update docs for sentiment scoring [doc-agent]"
```

Tag commits made by the agent with `[doc-agent]` to track automated updates.

---

## Troubleshooting

### Agent Not Detecting Changes

**Problem:** Run script but says "No changes detected"

**Solutions:**
```bash
# Use --force to run anyway
./scripts/run-doc-agent.sh --force

# Check file timestamps
ls -lt workflows/*/workflow.json

# Delete last-run marker to force full scan
rm .claude/.doc-agent-last-run
```

### Agent Making Wrong Updates

**Problem:** Agent updates something incorrectly

**Solutions:**
1. **Revert the change:** `git checkout -- docs/affected-file.md`
2. **Provide feedback:** Tell the agent what was wrong
3. **Update agent instructions:** Edit `.claude/agents/documentation-agent.md`

### Git Hooks Not Firing

**Problem:** Commits not triggering notifications

**Solutions:**
```bash
# Verify hooks are installed
ls -la .git/hooks/

# Reinstall hooks
./scripts/setup-git-hooks.sh

# Test manually
.git/hooks/post-commit
```

### Agent Too Aggressive

**Problem:** Agent proposes too many changes

**Solutions:**
- Run with specific focus: "Only update workflow 02 docs"
- Adjust change detection in `run-doc-agent.sh`
- Split updates across multiple runs

---

## Advanced Usage

### Custom Agent Tasks

In Claude Code, you can give the agent specific instructions:

```
Run the documentation agent with these specific tasks:
1. Update all workflow README files with current node counts
2. Verify all database schema references are accurate
3. Check that all setup guides reflect the current Docker configuration
```

### Integration with CI/CD

```yaml
# Example GitHub Actions workflow
name: Documentation Check

on: [pull_request]

jobs:
  docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Check documentation
        run: |
          ./scripts/run-doc-agent.sh
          # Could integrate Claude API here
```

### Batch Updates

```bash
# Update all workflow documentation
for workflow in workflows/*/; do
    echo "Checking $(basename $workflow)"
    # In Claude Code:
    # "Update documentation for $(basename $workflow)"
done
```

---

## Examples

### Example 1: Full Audit Output

```
Documentation Agent Scan Results
═══════════════════════════════════════

Changes Detected:
  ✓ workflows/02-llm-processing/workflow.json (modified 2 hours ago)
  ✓ database/schema.sql (modified today)

Affected Documentation:
  ⚠️ workflows/02-llm-processing/README.md (outdated: node count)
  ⚠️ docs/architecture/database.md (outdated: schema reference)
  ⚠️ workflows/README.md (outdated: status badge)

Proposed Updates:
  1. workflows/02-llm-processing/README.md
     - Update node count: 11 → 12
     - Add "Calculate Word Count" to features
     - Update timestamp

  2. docs/architecture/database.md
     - Add word_count column documentation
     - Update processed_notes table reference

  3. workflows/README.md
     - Update workflow 02 status to ✅

Proceed with these updates? (yes/no)
```

### Example 2: Minimal Change

```
Documentation Agent Scan Results
═══════════════════════════════════════

No structural changes detected.

Documentation Health Check:
  ✓ All node counts accurate
  ✓ Cross-references valid
  ✓ Examples up to date
  ⚠️ 3 files have timestamps >7 days old

Recommended:
  - Update timestamps in:
    - workflows/01-ingestion/STATUS.md
    - workflows/03-pattern-detection/README.md
    - docs/guides/setup.md

Update timestamps? (yes/no)
```

---

## FAQ

**Q: Will the agent change my code?**
A: No, it only updates documentation files (*.md).

**Q: Can it delete documentation?**
A: It will never delete without asking first. It's conservative by design.

**Q: How does it know what changed?**
A: It uses file modification times and Git history to detect changes.

**Q: What if I disagree with its updates?**
A: You review and approve all changes before they're made. You can reject any proposal.

**Q: Can I run it automatically?**
A: Yes, via Git hooks (after commits) or cron (scheduled). But it still requires approval.

**Q: How long does it take?**
A: Scanning: seconds. Analysis: 30-60 seconds. Updates: depends on scope.

**Q: Does it work offline?**
A: Yes, change detection works offline. Agent invocation requires Claude Code access.

**Q: Can I customize what it monitors?**
A: Yes, edit `.claude/agents/documentation-agent.md` and `scripts/run-doc-agent.sh`.

---

## Maintenance

### Updating the Agent

The agent definition is in `.claude/agents/documentation-agent.md`. To update:

1. Edit the file with new instructions
2. Test with: `./scripts/run-doc-agent.sh --force`
3. Verify behavior matches expectations
4. Document changes in this guide

### Monitoring Agent Performance

```bash
# View agent execution log
cat .claude/doc-agent.log

# See what files were checked
tail -20 .claude/doc-agent.log

# Clear log (if it gets too large)
> .claude/doc-agent.log
```

### Backing Up Documentation

```bash
# Before major agent runs
tar -czf docs-backup-$(date +%Y%m%d).tar.gz docs/ workflows/*/README.md workflows/*/docs/ ROADMAP.md

# Restore if needed
tar -xzf docs-backup-20251031.tar.gz
```

---

## Summary

The Documentation Agent is your **autopilot for documentation**. It:

- ✅ **Watches for changes** in code, workflows, and configuration
- ✅ **Proposes updates** to keep docs synchronized
- ✅ **Maintains consistency** across all documentation
- ✅ **Asks before changing** - you stay in control
- ✅ **Reports clearly** - you always know what changed

### Getting Started Checklist

- [ ] Agent definition exists at `.claude/agents/documentation-agent.md`
- [ ] Runner script is executable: `scripts/run-doc-agent.sh`
- [ ] Git hooks installed (optional): `./scripts/setup-git-hooks.sh`
- [ ] Test run completed: `./scripts/run-doc-agent.sh --force`
- [ ] Documentation guide reviewed (this file)

### Next Steps

1. **Make a small change** to a workflow
2. **Run the agent:** `./scripts/run-doc-agent.sh`
3. **Review proposals** - see what it suggests
4. **Approve and observe** - watch it update docs
5. **Verify results** - check the changes made

---

**Questions or Issues?**

The agent is designed to be helpful and safe. If something seems wrong:
1. Check this guide first
2. Review the agent definition
3. Test with `--force` flag
4. Provide feedback to improve the agent

Happy documenting! 🚀
