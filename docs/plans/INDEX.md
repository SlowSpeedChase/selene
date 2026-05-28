# Design Documents Index

**Last Updated:** 2026-05-26

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

**Before moving a design to "Done":** Did this add or change something you interact with?
- **Yes** → create or update the matching guide in `docs/guides/features/` and add/update its link in the hub (`docs/USER-EXPERIENCE.md`).
- **No** (invisible refactor/infra) → note "no user-facing change" and move on.

---

## Vision (Needs Refinement)

Ideas captured but not yet ready for implementation.

| Date | Document | Topic | Notes |
|------|----------|-------|-------|
| 2026-05-28 | [2026-05-28-competitive-landscape-research.md](2026-05-28-competitive-landscape-research.md) | strategy, competitive-landscape, adhd, synthesis | Research, not a build doc. What Selene can leverage from adjacent tools (Saner.ai, Mem, Khoj, Reor, Reflect, NotebookLM, Goblin Tools). 8 prioritized lessons mapped to existing code/roadmap + anti-patterns to avoid. Selene's white space = ADHD-first + fully local + auto clustering→narrative synthesis + proactive digest + multimodal capture (no single rival occupies it). |
| 2026-05-26 | [2026-05-26-synthesis-retrieval-agent-design.md](2026-05-26-synthesis-retrieval-agent-design.md) | pkm, synthesis, retrieval-agent, ollama, lancedb | Embedding-based topic clustering + local retrieval agent that routes questions to the right strategy (synthesis, RAG, recency, cross-topic). Web browse + chat UI on iPad (/pkm/synthesis), "Topics circling" section in daily digest. Supersedes 2026-05-24 synthesis-layer design. |
| 2026-05-26 | [2026-05-26-folio-kindle-agent-design.md](2026-05-26-folio-kindle-agent-design.md) | folio, kindle, mcp, agent, digest | Folio MCP server (4 tools) + scheduled Claude agent. Delta delivery: executive summary + ToC + changed docs → Kindle. Delivery log in folio/logs/kindle-deliveries.json. Track A: folio/src/mcp.ts. Track B: MCP registration + cron agent. |
| 2026-05-26 | [2026-05-26-selene-mobile-companion-design.md](2026-05-26-selene-mobile-companion-design.md) | ios, ipad, swiftui, pencilkit, widgetkit, annotation | iPhone/iPad companion app: Explore Obsidian vault notes + annotate with Apple Pencil (PencilKit) + on-device Vision OCR feeds annotations back to the librarian. Plus home screen widget (WidgetKit) showing today's summary. 3 phases. Server needs 4 new endpoints + note_annotations table. |
| 2026-05-26 | [2026-05-26-interactive-worksheets-design.md](2026-05-26-interactive-worksheets-design.md) | ipad, pencilkit, ocr, review-ritual | Handwritten iPad worksheets Selene generates from your notes; each answer routes back as an action (archive / follow-up / new note). v1 = daily review ritual. On-device OCR, M-series iPadOS 17+ (1st-gen Pro out). Builds on folio's unbuilt markup app; app talks directly to Selene. Phased: Ph0 freeform warm-up → Ph1 structured review → Ph2+ generators. |
| 2026-04-12 | [2026-04-12-model-audit-design.md](2026-04-12-model-audit-design.md) | llm, benchmarking, ollama | Per-stage model audit (curiosity-driven). Approach B locked; paused mid-design on fixture strategy. |
| 2026-04-12 | [2026-04-12-pkm-browse-layer-design.md](2026-04-12-pkm-browse-layer-design.md) | pkm, browse, ipad | LAN web dashboard (`/pkm/*`) + review state + slim exporter upgrade. 4 tracks, ~1 week. Needs category backfill first. |
| 2026-03-21 | [2026-03-21-close-the-loop-design.md](2026-03-21-close-the-loop-design.md) | executive-function, things | Thread/task completion feedback ideas still valid; implementation references archived systems (threads, extract-tasks, BriefingViewModel). Needs redesign against agent-layer architecture. |
| 2026-02-13 | 2026-02-13-database-architecture-evaluation.md | architecture, infra | Decision record: keep LanceDB + SQLite, skip graph DB. Resolved — kept for reference. |

---

## Ready (Implementation-Ready)

These have acceptance criteria, ADHD check, and scope check. Ready to create a branch.

| Date | Document | Topic | Notes |
|------|----------|-------|-------|

---

## In Progress

Branch exists, actively being worked on.

| Date | Document | Branch | Notes |
|------|----------|--------|-------|

---

## Done (Implemented)

| Date | Document | Completed | Notes |
|------|----------|-----------|-------|
| 2026-05-27 | [2026-05-26-phase1-worksheets-related-notes-design.md](2026-05-26-phase1-worksheets-related-notes-design.md) | 2026-05-27 | Multi-field worksheets (free_capture + note_review) + "Selene remembers" panel. OCR review-before-submit step added. Track A (TypeScript) + Track B (Swift/iPad). User guide at docs/guides/features/interactive-worksheets.md. |
| 2026-05-25 | [2026-05-25-user-guides-design.md](2026-05-25-user-guides-design.md) | 2026-05-25 | Consolidated hub (USER-EXPERIENCE.md) + 5 per-capability feature guides in docs/guides/features/ from shared template. Wrap-up trigger via Done criteria + GitOps docs-stage checkbox. |
| 2026-05-25 | [2026-05-25-folio-ipad-delivery-design.md](2026-05-25-folio-ipad-delivery-design.md) | 2026-05-25 | send-ipad.ts: qrcode-terminal QR code → iPad opens folio LAN reader → Apple Pencil annotation → feedback back to Selene. |
| 2026-05-25 | [2026-03-21-eink-notebook-ingestion-design.md](2026-03-21-eink-notebook-ingestion-design.md) | 2026-05-25 | minicpm-v OCR, pdftoppm conversion, manifest tracking, WatchPaths launchd agent. Fixed npx path bug (exit 126). Direct ingest (no Drafts step). |
| 2026-05-24 | [2026-05-23-agent-layer-design.md](2026-05-23-agent-layer-design.md) | 2026-05-24 | Agent layer v1: 4 SQLite tables, BaseAgent + Things enricher, ActionExecutor, dashboard (4 views), Apple Notes + Obsidian delivery, launchd schedule at 9am/6pm |
| 2026-02-22 | 2026-02-22-claude-code-automations-design.md | 2026-05-24 | context7 + sqlite-dev MCP servers, TypeScript type-check hook, .env block hook, run-workflow + launchd-check skills. All implemented, plus extras (playwright MCP, db-query, workflow-health). |
| 2026-03-21 | 2026-03-21-codebase-simplification-design.md | 2026-03-21 | Strip to clean core — 20K→3.5K lines. SeleneChat, SeleneMobile, threads, 11 workflows archived. |
| 2026-03-21 | 2026-03-21-obsidian-librarian-design.md | 2026-03-21 | LLM-curated notes + topic indexes implemented in export-obsidian.ts |
| 2026-03-21 | 2026-03-21-obsidian-moc-design.md | 2026-03-21 | 8-category MOCs + code-generated Dashboard.md implemented in export-obsidian.ts |
| 2026-03-21 | 2026-02-22-voice-memo-llm-title-design.md | 2026-03-21 | Already implemented in transcribe-voice-memos.ts, moved from Ready |
| 2026-03-21 | 2026-02-19-calendar-context-linking-design.md | 2026-03-21 | Full chain: Swift CLI + ingestion + SeleneChat/Mobile UI + AI context, moved from Ready |
| 2026-02-14 | 2026-02-13-selene-mobile-ios-design.md | 2026-02-14 | Full parity iOS app, Tailscale networking, push + live activities, moved from Ready |
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
| 2026-05-17 | 2026-02-13-trmnl-daily-digest-design.md | 2026-05-17 | Push morning digest to TRMNL e-ink display at 6am |
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
<summary>View Archived (50+)</summary>

| Date | Document | Reason |
|------|----------|--------|
| 2026-05-24 | 2026-05-24-synthesis-layer-design.md | Superseded by 2026-05-26-synthesis-retrieval-agent-design.md — original used string-frequency clustering and Obsidian-only output; new design uses embedding clustering + retrieval agent + web UI. |
| 2026-02-15 | 2026-02-15-thinking-partner-upgrade-design.md | SeleneChat archived 2026-03-21. Core idea (proactive AI briefing) re-emerges in agent-layer. |
| 2026-02-13 | 2026-02-13-kitchenos-selene-integration-design.md | SeleneChat archived 2026-03-21. Conversational meal planning was the shell. |
| 2026-02-13 | 2026-02-13-voice-conversation-design.md | SeleneChat (Voice Phase 2 TTS) archived 2026-03-21. |
| 2026-02-04 | 2026-02-04-conversation-memory-design.md | SeleneChat archived 2026-03-21. mem0-style memory extraction idea preserved in design doc. |
| 2026-01-26 | selenechat-contextual-evolution.md | SeleneChat archived 2026-03-21. |
| 2026-01-26 | phase-7.3-cloud-ai-integration.md | Assumed SeleneChat shell. Anonymization layer concept absorbed into agent-layer design. |
| 2026-01-26 | phase-7.3-implementation-plan.md | Superseded — depends on archived SeleneChat architecture. |
| 2026-01-11 | things-checklist-integration-design.md | Required SeleneChat + cloud AI. Things integration now handled by agent-layer. |
| 2026-01-11 | selenechat-remote-access-design.md | Superseded by SeleneMobile (also archived). |
| 2026-01-05 | weekly-review-react-flow-design.md | "Present → React → File" paradigm. Depended on archived thread + task systems. |
| 2026-01-05 | selenechat-interface-inspiration-design.md | SeleneChat design reference. Design philosophy (Forest Study palette) could inspire web dashboard. |
| 2026-01-05 | selenechat-redesign-design.md | SeleneChat Forest Study design system. App archived. |
| 2026-01-01 | n8n-upgrade-design.md | Superseded by TypeScript replacement (2026-01-09). |
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
