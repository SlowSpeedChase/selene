# Selene Intelligence Upgrade: Prosthetic Executive Function

**Created:** 2026-02-24
**Status:** Ready
**Goal:** Transform Selene from a note organizer into a prosthetic executive function that surfaces, reasons, and reflects — without ever deciding for the user.
**Supersedes:** `2026-02-15-thinking-partner-upgrade-design.md` (Phase 1 prompt rewrite absorbed here; Phase 2 cloud AI deferred to Layer 4)

---

## Problem Statement

Selene captures and organizes well. But when the user needs help *thinking through* something, the system falls short:

1. **Chat summarizes instead of engaging** — asks no questions, cites no evidence, offers no options
2. **No proactive surfacing** — user must initiate every interaction
3. **No behavioral pattern awareness** — can't say "you've tried this before" or "you always stall on people-tasks"
4. **No reflection loop** — no post-action closure, pattern recognition, or momentum transfer
5. **Context assembly is weak** — chat gets thread summary + recent notes, missing emotional history, decision history, task outcomes

**Desired behavior:** Selene reads the situation, asks before answering, cites specific evidence from past notes, presents options with tradeoffs, pushes back on unrealistic plans, and closes by asking what resonates. Voice is minimal and zen — every word earns its place.

---

## Design Principles

1. **Never decide. Make deciding easier.** Selene surfaces, reasons, reflects. The human always chooses.
2. **Dumb model, smart context.** Pre-compute patterns and hand them to the model. Don't ask a 7B to discover insights — ask it to communicate pre-analyzed insights.
3. **Local-first.** System works without internet. Cloud is an optional escape hatch with full PII sanitization.
4. **Quality over speed.** Processing time is not a concern. Let workflows take as long as they need.
5. **Every word earns its place.** Minimal, zen personality. No filler, no fluff, no summaries unless asked.

---

## Architecture: Four Layers

Implementation is layered and iterative. Each layer is evaluated before proceeding to the next.

### Layer 1: Enhanced Retrieval for Chat

**Problem:** Chat context is shallow. The model gets thread summary + recent notes but misses emotional history, past decisions, task outcomes, and behavioral patterns.

**Solution:** Contextual memory retrieval pipeline that assembles rich, labeled context blocks before the LLM sees the prompt.

#### New Retrieval Pipeline

When the user sends a chat message, before LLM generation:

1. **Semantic search** (exists) — find notes related to the query via vector similarity
2. **Emotional history search** (new) — find notes where user expressed strong emotion about this topic
3. **Decision history search** (new) — find notes where user made decisions, changed mind, or committed to action on this topic
4. **Task outcome search** (new) — find completed, abandoned, or overdue tasks related to this topic
5. **Behavioral pattern lookup** (new) — query pre-computed patterns (see Future: Behavioral Aggregation)

#### Structured Context Injection

Context is injected as labeled blocks so the model knows *what kind* of information each piece is:

```
[RELEVANT PAST NOTE - Oct 12]: "I keep saying I'll wake up early but I never stick with it past day 3"
[DECISION - Jan 5]: Decided to try 3x/week instead of daily
[TASK HISTORY]: morning-routine — 3 tasks created, 0 completed, avg lifespan 4 days
[EMOTIONAL TREND - this week]: frustration 4x (up from 1x last week), mostly in health + career threads
[THREAD STATE]: 'health' — 8 notes, momentum declining, last activity 6 days ago
```

#### Implementation

**New/Modified files:**
- `Sources/SeleneShared/Services/ContextualMemoryRetriever.swift` — orchestrates multi-signal retrieval
- `Sources/SeleneShared/Models/RetrievedContext.swift` — typed context block model
- Modify `ChatViewModel` / `ThreadWorkspaceChatViewModel` — use new retrieval before LLM call
- Modify `DatabaseService` — new queries for decision-notes, emotion-tagged notes, task outcomes

**Schema considerations:**
- `processed_notes` already has `sentiment`, `emotional_tone` — may need indexing or a view for efficient trend queries
- `extracted_tasks` has completion status — may need a query for per-topic task outcome aggregation
- No new tables likely needed — existing schema is rich enough

#### Acceptance Criteria

- [ ] Chat retrieval pulls emotionally significant past notes (not just semantically similar ones)
- [ ] Chat retrieval includes task completion/abandonment history for the topic
- [ ] Context blocks are labeled by type (past note, decision, task history, emotional trend, thread state)
- [ ] Retrieved context respects token budget (ContextBuilder integration)
- [ ] Chat responses reference specific past notes by date when relevant

---

### Layer 2: Prompt Architecture Rewrite

**Problem:** System prompts produce generic summaries. The model doesn't ask questions, cite evidence, or present options.

**Solution:** Rewrite all system prompts with Selene's personality and conversational rules. Build on the structured context from Layer 1.

#### Selene Personality: Voice Guide

- Short sentences. No filler.
- State the pattern. Present the options. Ask.
- Don't explain what the user already knows.
- Cite specific notes by content, not vague references.
- Silence is fine. Don't talk just to fill space.
- Never summarize the thread back unless explicitly asked.
- Compassionate but honest. Will push back on patterns. Kindly.

#### Conversational Rules (encoded in system prompts)

1. **Ask before answering.** When the user asks for help, respond with 1-2 clarifying questions first. Identify what they're stuck on.
2. **Always cite evidence.** "In your Oct note you said..." not "based on your notes..."
3. **Present options, not answers.** 2-3 paths with tradeoffs grounded in the user's actual situation and history.
4. **Push back on patterns.** If retrieved context shows repeated failed attempts, past abandoned tasks, or unrealistic commitments — say so. Directly.
5. **Close by asking what resonates.** Never end with a wall of text. Always invite the human to choose or respond.
6. **Match the nudge type to the situation:**
   - Circling without deciding → pattern alert (name the tension)
   - Threads stuck vs moving → momentum check (show contrast, ask to pick)
   - Emotional trend shifting → emotional awareness (present pattern, no pressure)
   - Task/thread completed → celebrate + connect (transfer momentum)

#### Prompt Templates

**General chat (replaces current):**
```
You are Selene, a thinking partner. Minimal, precise, kind.

Rules:
- Never summarize unless asked. Engage.
- If the user wants help: ask 1-2 questions first to understand what they're stuck on.
- Cite specific notes by date/content. Never say "based on your notes" generically.
- Present 2-3 options with tradeoffs when the user faces a decision.
- If past context shows repeated patterns or failed attempts: name them directly.
- End by asking what resonates. Never end with a monologue.

[CONTEXT BLOCKS — injected by Layer 1 retrieval]
```

**Planning mode (new, replaces "what's next"):**
```
The user is in planning mode. They want help breaking something down.

Rules:
- Ask what's the actual blocker before proposing steps.
- Reference past attempts if any exist in context.
- Break into 3-5 concrete steps. Each step: one action, estimated effort, what it unblocks.
- Flag if any step matches a pattern the user historically avoids (from task history).
- Ask: does this feel realistic? What would make you actually start?
```

**Thread workspace (modified):**
```
You're looking at the '{thread_name}' thread with the user.

Thread state: {momentum}, {note_count} notes, last activity {days} ago.
Open tasks: {task_summary}

Rules:
- Don't recap the thread. The user can see it.
- Focus on: what's changed, what's stuck, what needs attention.
- If tasks are stale: ask what's blocking, not whether to keep them.
- If the thread is heating up: acknowledge momentum, ask where to focus.
```

#### Implementation

**Modified files:**
- `Sources/SeleneShared/Services/ThreadWorkspacePromptBuilder.swift` — full rewrite
- `Sources/SeleneShared/Services/ChatPromptBuilder.swift` (or equivalent) — full rewrite
- `Sources/SeleneShared/Services/BriefingContextBuilder.swift` — voice alignment
- Backend `src/workflows/daily-summary.ts` — voice alignment for briefing output
- Backend `src/workflows/reconsolidate-threads.ts` — voice alignment for thread summaries

#### Acceptance Criteria

- [ ] When user asks "help me think about X" — Selene asks a clarifying question first (not a summary)
- [ ] When user faces a decision — Selene presents 2-3 options with tradeoffs citing specific past notes
- [ ] When user proposes something they've failed at before — Selene names the pattern with evidence
- [ ] No response has hardcoded word limits under 500 tokens
- [ ] Planning-intent detection covers 20+ query patterns
- [ ] All system prompts encode the voice guide (minimal, zen, cite evidence, ask don't tell)
- [ ] Thread workspace responses never recap the thread unless asked

---

### Layer 3: Local Model Upgrade (Evaluate After Layers 1+2)

**Problem:** Even with perfect retrieval and prompts, mistral:7b may hit a reasoning ceiling for complex synthesis, multi-step planning, and nuanced dialogue.

**Approach:** After Layers 1+2 are deployed, evaluate where the model still falls short. Then choose the best local model upgrade for M4 16GB hardware.

#### Candidate Models (16GB unified memory, ~10-11GB available for weights)

| Model | Size on Disk | Expected Speed | Reasoning Quality |
|---|---|---|---|
| phi-4:14b (Q4_K_M) | ~9GB | ~15-25 tok/s | Strong for size, good at structured output |
| deepseek-r1:14b (Q4_K_M) | ~9GB | ~12-20 tok/s | Chain-of-thought reasoning, thorough |
| qwen2.5:32b (IQ3_XS) | ~11GB | ~3-5 tok/s | Near-cloud reasoning, very slow |
| llama3.1:8b (Q6_K) | ~6GB | ~35-50 tok/s | Good instruction following, limited depth |

#### Two-Model Strategy (Candidate)

- **Fast worker** (always loaded): 7-8B model for high-frequency pipeline tasks (extraction, classification, embeddings)
- **Deep thinker** (loaded on demand): 14B+ model for chat, synthesis, planning, reflection

Ollama handles model swapping. Since processing time is not a concern, the 30-60 second model load time is acceptable.

#### Evaluation Criteria

After Layers 1+2 deployment, test these specific scenarios:
1. "Help me break down this project" — does the model produce concrete, realistic steps?
2. "Why do I keep avoiding this?" — does the model use behavioral context to give an honest answer?
3. "What patterns do you see across my threads?" — does the model synthesize cross-thread insights?
4. Thread workspace: is the model engaging or still summarizing?

If 2+ scenarios still feel inadequate, upgrade. If prompts + retrieval fixed it, stay on mistral:7b.

#### Acceptance Criteria

- [ ] Evaluation performed on all 4 test scenarios with current model + Layers 1+2
- [ ] If upgrading: new model benchmarked on same scenarios
- [ ] If two-model strategy: model swap latency acceptable for interactive chat
- [ ] Pipeline tasks (extraction, classification) remain fast and accurate on chosen model

---

### Layer 4: Cloud Escape Hatch (Deferred)

**Problem:** Some tasks may exceed any local model's capability — complex multi-step planning, tasks requiring world knowledge, research assistance.

**Approach:** Claude API integration with full PII sanitization. Always optional. System works without it.

#### Sanitization (Non-Negotiable)

All personal information stripped before any cloud request:
- Names, locations, health information, financial details
- Replaced with topic-level summaries
- Local LLM produces the sanitized version (same approach as Phase 7.3 design)

#### When to Route to Cloud

- User explicitly requests it (toggle in settings)
- Local model confidence is low (measurable via response quality heuristics)
- Task type known to exceed local capability (complex planning, research)

#### Implementation

Builds on existing designs:
- `2026-02-15-thinking-partner-upgrade-design.md` Phase 2 architecture
- `phase-7.3-cloud-ai-integration.md` sanitization framework
- `LLMRouter` already supports provider routing

Deferred until Layers 1-3 are evaluated. May not be needed if local model upgrade is sufficient.

---

## Future Work (From This Conversation, Not In Scope)

These emerged during brainstorming and should become separate design docs when ready:

### Behavioral Pattern Aggregation
- New scheduled workflow computing: task completion patterns by type, emotional trends over time windows, thread engagement patterns
- Feeds into Layer 1 retrieval and Layer 2 prompts
- Enables reflection like "you consistently finish research tasks but stall on people-tasks"

### Nudge Engine
- Rules-based service that evaluates "should Selene say something?" after reconsolidation
- Three nudge types: pattern alert (tension), momentum check (stuck vs moving), emotional awareness (trend)
- LLM only generates nudge text — decision to nudge is heuristic/rule-based
- Delivery: push notification (iOS), menu bar indicator (macOS), morning briefing inclusion

### Reflection Loop
- Post-action closure: "you finished 3 of 5 tasks, here's what's still open"
- Cross-thread momentum transfer: "the daily habit that worked for writing could apply to music"
- Monthly pattern reports: behavioral trends, thread lifecycle, completion rates

---

## ADHD Check

- **Reduces friction?** Yes — retrieval does the memory work so the user doesn't have to remember context
- **Makes things visible?** Yes — patterns, trends, and task outcomes surfaced proactively
- **Externalizes cognition?** Yes — the core purpose. System holds the context, user makes the decisions
- **Reduces overwhelm?** Yes — asking questions narrows scope, options have tradeoffs, model pushes back on overcommitting

---

## Scope Check

- **Layer 1 (retrieval):** ~3-4 days — new retrieval service, database queries, context integration
- **Layer 2 (prompts):** ~2-3 days — prompt rewrites, voice alignment, planning detection expansion
- **Layer 3 (model evaluation):** ~1 day — benchmark current vs candidates on test scenarios
- **Layer 4 (cloud):** Deferred — separate design doc when needed
- **Total Layers 1+2:** ~1 week, fits scope guideline

---

## Relationship to Existing Designs

| Design | Relationship |
|---|---|
| `2026-02-15-thinking-partner-upgrade-design.md` | Phase 1 (prompt rewrite) absorbed into Layer 2 here. Phase 2 (cloud) deferred to Layer 4. |
| `phase-7.3-cloud-ai-integration.md` | Sanitization architecture reused in Layer 4 when needed. |
| `2026-02-13-voice-conversation-design.md` | Voice in/out benefits from better chat quality — Layer 2 prompts apply to voice conversations too. |
| `2026-02-22-tiered-context-compression-design.md` | ContextBuilder and fidelity tiers are used by Layer 1 retrieval to fit context in token budgets. |

---

## Related

- `.claude/ADHD_Principles.md` — ADHD design framework
- `src/lib/context-builder.ts` — Existing tiered context assembly
- `SeleneChat/Sources/SeleneShared/Services/ThreadWorkspacePromptBuilder.swift` — Current prompt architecture
- `SeleneChat/Sources/SeleneShared/Services/LLMRouter.swift` — Existing provider routing
