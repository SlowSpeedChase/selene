# Design Documents Index

**Last Updated:** 2026-03-01

Design docs are the planning unit for Selene development. Each doc captures an idea, architecture, and implementation plan.

---

## Status Definitions

| Status | Meaning | Next Step |
|--------|---------|-----------|
| **Vision** | Idea captured, needs refinement | Add acceptance criteria, ADHD check, scope check |
| **Ready** | Implementation-ready | Create branch, start GitOps workflow |
| **In Progress** | Branch exists, being built | Complete GitOps stages |
| **Done** | Implemented and merged | Archive if old |

**A design is "Ready" when it has:**
- [ ] Acceptance criteria defined
- [ ] ADHD check passed (reduces friction? visible? externalizes cognition?)
- [ ] Scope check passed (< 1 week of focused work)
- [ ] No blockers

---

## Vision (Needs Refinement)

Ideas captured but not yet ready for implementation.

| Date | Document | Topic | Notes |
|------|----------|-------|-------|
| 2026-02-13 | 2026-02-13-database-architecture-evaluation.md | architecture, infra | Vector/graph DB evaluation — keep LanceDB + SQLite, skip graph DB |
| 2026-02-04 | 2026-02-04-conversation-memory-design.md | selenechat | Persistent conversation memory with mem0-inspired patterns |
| 2026-01-26 | selenechat-contextual-evolution.md | selenechat | Project-scoped chats, connected info, lab notes - needs breakdown |
| 2026-01-11 | selenechat-remote-access-design.md | selenechat | Superseded by 2026-02-13-selene-mobile-ios-design.md |
| 2026-01-05 | weekly-review-react-flow-design.md | ux-core | "Present -> React -> File" paradigm |
| 2026-01-05 | selenechat-interface-inspiration-design.md | selenechat | Design patterns research - reference doc |
| 2026-01-05 | selenechat-redesign-design.md | selenechat | Forest Study design system |
| 2026-01-01 | n8n-upgrade-design.md | infra | Superseded by TypeScript replacement |

---

## Ready (Implementation-Ready)

These have acceptance criteria, ADHD check, and scope check. Ready to create a branch.

| Date | Document | Topic | Notes |
|------|----------|-------|-------|
| 2026-02-15 | 2026-02-15-thinking-partner-upgrade-design.md | selenechat, cloud-ai | Partially superseded by intelligence-upgrade (Phase 1). Phase 2 (cloud + file workspace) deferred. |
| 2026-02-13 | 2026-02-13-kitchenos-selene-integration-design.md | integrations, meal-planning | KitchenOS recipe indexing + conversational meal planning in SeleneChat |
| 2026-02-13 | 2026-02-13-trmnl-daily-digest-design.md | integrations | Push morning digest to TRMNL e-ink display |
| 2026-02-13 | 2026-02-13-voice-conversation-design.md | selenechat | Voice Phase 2: TTS responses, voice-in = voice-out conversation mode |
| 2026-02-13 | 2026-02-13-selene-mobile-ios-design.md | selenechat, mobile | Native iOS app with full parity, Tailscale networking, push + live activities |
| 2026-02-19 | 2026-02-19-calendar-context-linking-design.md | ingestion, calendar | Auto-link notes to Apple Calendar events via Swift CLI + EventKit |
| 2026-02-22 | 2026-02-22-voice-memo-llm-title-design.md | voice, llm | LLM-generated titles for voice memos instead of timestamp titles |
| 2026-02-22 | 2026-02-22-claude-code-automations-design.md | dev-experience, tooling | MCP servers, Claude Code hooks, and custom skills for dev velocity + safety |

---

## Deprioritized

Designs that are ready but not currently a priority. These are bundled together for future implementation.

| Date | Document | Topic | Notes |
|------|----------|-------|-------|
| 2026-01-26 | phase-7.3-cloud-ai-integration.md | cloud-ai | Privacy-preserving cloud AI with sanitization |
| 2026-01-26 | phase-7.3-implementation-plan.md | cloud-ai | 21 tasks, implementation ready |
| 2026-01-11 | things-checklist-integration-design.md | things | Checklist generation - benefits from Cloud AI |

**Bundle rationale:** Things checklist generation uses LLM for task breakdown. Local Ollama produces adequate results, but Cloud AI would significantly improve quality. Implement together when Cloud AI is prioritized.

---

## In Progress

Branch exists, actively being worked on.

| Date | Document | Branch | Notes |
|------|----------|--------|-------|

---

## Done (Implemented)

| Date | Document | Completed | Notes |
|------|----------|-----------|-------|
| 2026-03-18 | 2026-03-18-physical-digital-bridge-design.md | 2026-03-18 | Claude Vision whiteboard capture, daily planning sheet PDF, annotation closed loop |
| 2026-03-01 | 2026-03-01-remove-n8n-naming-design.md | 2026-03-01 | Rename selene-n8n to selene across 108 files, 665 tests passing |
| 2026-02-28 | 2026-02-28-thread-context-isolation-design.md | 2026-03-01 | Remove global fallback, thread-scoped memories, active project default, golden walkthrough (665 tests) |
| 2026-02-24 | 2026-02-24-selene-intelligence-upgrade-design.md | 2026-02-27 | Layers 1+2: ContextualRetriever, zen prompt rewrite, 53 planning patterns, 743 tests |
| 2026-02-21 | 2026-02-21-tiered-context-compression-design.md | 2026-02-22 | ContextBuilder, 3 new workflows, tier evaluation, essence backfill, health endpoint |
| 2026-02-21 | 2026-02-21-dev-environment-isolation-design.md | 2026-02-22 | Overmind + Procfile.dev, 536 seed notes, vault export fix, all 9 acceptance criteria pass |
| 2026-02-14 | 2026-02-14-context-blocks-apple-intelligence-design.md | 2026-02-14 | Chunk-based retrieval, Apple Intelligence LLM, LLM Router, background chunking pipeline |
| 2026-02-12 | 2026-02-12-menu-bar-orchestrator-design.md | 2026-02-13 | Menu bar app with Silver Crystal icon + workflow orchestration |
| 2026-02-12 | 2026-02-12-voice-memo-transcription-design.md | 2026-02-13 | Whisper.cpp transcription + Selene pipeline integration |
| 2026-02-12 | 2026-02-12-apple-notes-daily-digest-design.md | 2026-02-13 | Replace iMessage digest with pinned Apple Notes daily note |
| 2026-02-06 | 2026-02-06-thread-workspace-design.md | 2026-02-13 | Thread workspace: all 3 phases complete (context, actions, feedback loop) |
| 2026-02-13 | 2026-02-13-thread-workspace-phase3-design.md | 2026-02-13 | Feedback loop: on-demand Things sync, momentum boost, LLM "what's next" |
| 2026-02-13 | 2026-02-13-morning-briefing-redesign.md | 2026-02-13 | Structured cards, deep context chat, cross-thread connections |
| 2026-02-13 | 2026-02-13-thread-lifecycle-design.md | 2026-02-13 | Auto archive, split, merge threads — full lifecycle |
| 2026-02-06 | 2026-02-06-test-environment-isolation-design.md | 2026-02-06 | Complete test isolation with anonymized data |
| 2026-02-06 | 2026-02-06-memory-embedding-retrieval-design.md | 2026-02-06 | Embedding-based memory retrieval and consolidation |
| 2026-01-26 | today-view-design.md | 2026-01-26 | ADHD landing page with new captures and heating threads |
| 2026-02-05 | 2026-02-05-voice-input-design.md | 2026-02-05 | Voice input Phase 1: Apple Speech, push-to-talk, URL scheme |
| 2026-02-05 | 2026-02-05-selene-thinking-partner-design.md | 2026-02-05 | Proactive briefing, cross-thread synthesis, deep-dive dialogue |
| 2026-02-02 | 2026-02-02-imessage-daily-digest-design.md | 2026-02-02 | iMessage daily digest at 6am via AppleScript |
| 2026-01-27 | 2026-01-27-selenechat-vector-search-design.md | 2026-01-27 | SeleneChat vector search integration |
| 2026-01-26 | 2026-01-26-lancedb-transition.md | 2026-01-27 | LanceDB vector DB, typed relationships |
| 2026-01-11 | selenechat-thread-queries-design.md | 2026-01-11 | Thread queries in SeleneChat |
| 2026-01-11 | obsidian-thread-export-design.md | 2026-01-11 | Thread export to Obsidian |
| 2026-01-10 | phase-3-living-system-design.md | 2026-01-11 | Thread reconsolidation |
| 2026-01-09 | n8n-replacement-design.md | 2026-01-10 | TypeScript backend |
| 2026-01-06 | test-isolation-design.md | 2026-01-06 | Test data isolation |
| 2026-01-05 | batch-embed-notes-design.md | 2026-01-05 | Batch embedding |
| 2026-01-05 | association-computation-design.md | 2026-01-06 | Note associations |
| 2026-01-04 | selene-thread-system-design.md | 2026-01-11 | Core thread system |
| 2026-01-04 | embedding-workflow-implementation.md | 2026-01-05 | Embedding workflow |

---

## Archived

Superseded, abandoned, or very old designs. Kept for reference.

<details>
<summary>View Archived (40+)</summary>

| Date | Document | Reason |
|------|----------|--------|
| 2026-01-04 | user-story-system-design.md | Replaced by simplified two-layer system |
| 2026-01-02 | plan-archive-agent-design.md | Deprioritized |
| 2026-01-02 | selenechat-auto-builder-design.md | Deprioritized |
| 2026-01-02 | feedback-pipeline-design.md | Deprioritized |
| 2026-01-02 | selenechat-uat-system-design.md | Deprioritized |
| 2026-01-03 | process-gap-fixes-design.md | Deprioritized |
| 2025-12-31 | ai-provider-toggle-design.md | Implemented |
| 2025-12-30 | task-extraction-planning-design.md | Implemented |
| 2025-12-30 | daily-summary-design.md | Implemented |
| 2025-12-31 | phase-7.2-selenechat-planning-design.md | Implemented |
| 2025-12-31 | workflow-lifecycle-management-design.md | Superseded |
| 2025-12-31 | workflow-standardization-design.md | Superseded by TS replacement |
| 2026-01-01 | selenechat-debug-system-design.md | Implemented |
| 2025-11-14 | ollama-integration-design.md | Implemented |
| 2025-11-14 | selenechat-database-integration-design.md | Implemented |
| 2025-11-15 | selenechat-clickable-citations-design.md | Implemented |
| 2025-11-27 | modular-context-structure.md | Implemented |
| 2025-11-30 | dev-environment-design.md | Implemented |
| 2025-11-25 | phase-7-1-gatekeeping-design.md | Superseded |
| 2026-01-02 | bidirectional-things-flow-design.md | Implemented |
| 2026-01-01 | project-grouping-design.md | Implemented |

</details>

---

## Workflow

### Creating a Design Doc

1. Use brainstorming skill to explore the idea
2. Write to `docs/plans/YYYY-MM-DD-topic-design.md`
3. Add entry to this INDEX in "Vision" section
4. Status: **Vision**

### Making It Ready

1. Add acceptance criteria (testable)
2. Complete ADHD check
3. Verify scope (< 1 week)
4. Move to "Ready" section
5. Status: **Ready**

### Starting Implementation

1. Create branch: `git worktree add -b feature-name .worktrees/feature-name main`
2. Copy BRANCH-STATUS.md template
3. Move doc to "In Progress" section
4. Follow GitOps stages (see `.claude/GITOPS.md`)
5. Status: **In Progress**

### Completing

1. Merge to main
2. Move doc to "Done" section
3. Complete closure ritual
4. Status: **Done**

---

## Related

- `templates/DESIGN-DOC-TEMPLATE.md` - Template for new designs
- `.claude/GITOPS.md` - Implementation workflow
- `.claude/PROJECT-STATUS.md` - Current project state
