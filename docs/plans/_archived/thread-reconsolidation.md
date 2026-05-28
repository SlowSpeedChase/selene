# Thread Reconsolidation

> **ARCHIVED — 2026-03-21**
> The workflows this document describes (`reconsolidate-threads.ts`, `detect-threads.ts`,
> `compute-embeddings.ts`, `compute-relationships.ts`) were removed during the
> codebase simplification. The thread system lives in `archive/shelved-2026-03-21/`.
>
> **Still relevant:** The design patterns here — delta-only updates, momentum scoring,
> and LLM-regenerated summaries per cluster — are closely related to the synthesis
> layer being built in `docs/plans/2026-05-24-synthesis-layer-design.md`. The synthesis
> layer uses concept-frequency clustering instead of embedding similarity, but the
> reconsolidation loop (detect change → fetch notes → LLM → update → export) is
> the same shape.

---

**Purpose:** Keep semantic threads alive and accurate as new notes flow into the system.

---

## What is Reconsolidation?

Reconsolidation is the process of updating thread summaries, motivations, and momentum scores as new notes are added. It transforms threads from static snapshots into living representations of your thinking.

**Without reconsolidation:** Threads become stale. Their summaries reflect old thinking. You lose track of which threads are active.

**With reconsolidation:** Threads evolve. Summaries update to reflect new insights. Momentum scores tell you which threads are hot.

---

## The Problem It Solves

When you capture notes over time, your understanding shifts:

1. **Initial note:** "Thinking about event-driven architecture"
2. **Later note:** "Tested webhooks, they work but need error handling"
3. **Even later:** "Implemented retry logic, system is solid now"

A static thread summary from note #1 would say "Thinking about event-driven architecture" forever. But your actual thinking has progressed to "system is solid now."

Reconsolidation asks the LLM: "Given all these notes, what is this thread really about now?"

---

## How It Works

### Phase 1: Detect Threads Needing Update

```sql
SELECT threads WHERE
  EXISTS (new notes added since last update)
  AND status = 'active'
```

Only threads with new activity get resynthesized. Quiet threads are left alone.

### Phase 2: Resynthesize Each Thread

For each thread needing update:

1. Fetch the thread's linked notes (newest first, up to 15)
2. Build a prompt with the current summary, "why", and notes
3. Ask the LLM:
   - Has the direction shifted?
   - What's the updated summary?
   - Has the underlying motivation changed?
4. Update the thread with the new synthesis

**Example LLM prompt:**
```
Thread: Event-Driven Architecture Testing
Previous summary: Testing webhooks for automation
Previous "why": To verify the system works

Notes in this thread (newest first):
--- Note 1 (2026-01-10) ---
Retry logic implemented, system handles failures gracefully

--- Note 2 (2026-01-08) ---
Webhooks work but timeout on slow responses

Questions:
1. Has the direction of this thread shifted?
2. What is the updated summary?
3. Has the underlying motivation become clearer or changed?
```

### Phase 3: Calculate Momentum

Momentum tells you which threads are "hot" - actively being worked on.

**Formula:**
```
momentum = (notes_7_days * 2) + (notes_30_days * 1) + 0.25
```

- Notes from the last 7 days are weighted 2x
- Notes from the last 30 days are weighted 1x
- Small baseline to avoid zero scores

**High momentum (30+):** Thread is on fire, you're actively working on it
**Medium momentum (10-30):** Active but not dominant
**Low momentum (<10):** Quiet, possibly dormant

### Phase 4: Export to Obsidian

After updating summaries and momentum, threads are exported to Obsidian:

```
vault/Selene/Threads/
├── event-driven-architecture-testing.md
├── project-journey.md
└── ...
```

Each file includes:
- YAML frontmatter (status, momentum, note count)
- Why section (underlying motivation)
- Summary section (current understanding)
- Status with emoji and momentum score
- Wiki-links to related notes

---

## Schedule

Reconsolidation ran **hourly** via launchd.

**Why hourly?**
- Frequent enough to keep threads current
- Not so frequent it burns LLM tokens
- Aligns with natural work rhythms (check threads at top of hour)

---

## Thread Lifecycle

```
┌─────────────────────────────────────────────────────────┐
│                    THREAD LIFECYCLE                      │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  [Detection]  →  [Active]  →  [Paused]  →  [Completed]  │
│       ↑            │  ↑          │             │         │
│       │            │  │          │             │         │
│   New notes    Reconsolidation   Manual      Manual      │
│   cluster      updates summary   pause       complete    │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

1. **Detection:** 3+ related notes cluster together, LLM names the thread
2. **Active:** Thread receives new notes, reconsolidation keeps it fresh
3. **Paused:** You manually pause threads you want to revisit later
4. **Completed:** Thread reached its goal, archived for reference

---

## ADHD Design Principles

Reconsolidation embodies key ADHD principles:

**1. Externalize Working Memory**
- You don't have to remember what each thread is about
- The system tracks and summarizes for you

**2. Make Progress Visible**
- Momentum scores show where your energy is going
- Updated summaries reflect actual progress, not stale intentions

**3. Reduce Cognitive Load**
- Don't re-read all notes to understand a thread
- Summary gives you context in seconds

**4. Combat "Out of Sight, Out of Mind"**
- Obsidian export puts threads in your daily view
- High momentum threads surface automatically

---

## Related Workflows (all archived)

| Workflow | Frequency | Relationship |
|----------|-----------|--------------|
| `compute-embeddings` | 5 min | Generates embeddings for similarity |
| `compute-associations` | 5 min | Finds related notes |
| `detect-threads` | 30 min | Creates new threads from clusters |
| `reconsolidate-threads` | 1 hour | Updates existing threads |

**Data flow:**
```
Notes → Embeddings → Associations → Thread Detection → Reconsolidation
                                                            ↓
                                                    Obsidian Export
```

---

## Why "Reconsolidation"?

The term comes from memory science. In the brain, memories aren't fixed - they're reconsolidated each time you recall them, integrating new information.

Selene threads work the same way. Each reconsolidation integrates new notes into the thread's understanding, keeping it alive and accurate.

Your threads aren't static files. They're living representations of your thinking.
