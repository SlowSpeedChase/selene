# Selene as Executive Assistant — Coalescing Fragments into Wants

**Status:** Vision
**Created:** 2026-06-07
**Updated:** 2026-06-07
**Topic:** executive-function, wants, intentions, coalescence, habit, note-relationships, eventkit

---

## Problem

Today Selene is an excellent **librarian**: you dump a fractured note ("I want to host a
dinner party for improv people") and it files it well — category, sub-category, cluster,
Obsidian library, synthesis. But it has no idea that note was a *want* rather than a musing,
it can't gather the scattered fragments of that want as they arrive over days and channels,
and it never helps you *act* on it. The intention dimension was even designed for once — the
`actionability` field exists in `lancedb.ts:44` (`actionable | someday | reference | done`)
but `process-llm.ts:172` always writes `null`. Every note is treated as inert reference
material; a want and a passing thought are indistinguishable to the system.

The deeper problem is **habit before features**. None of this matters if the daily habit of
using Selene doesn't exist first. A perfect want-engine you never open is worthless; a small
daily touchpoint you actually use is the foundation everything else needs.

---

## Solution

Frame Selene as three roles over one note graph, and build the executive-function piece in
**two acts** — the near-term habit-builder first, the dream second.

### The three roles (the organizing spine)

The same fragment is **shelved** by one role, **preserved** by another, **acted on** by a third:

| Role | Job | Status today |
|------|-----|--------------|
| **Librarian** | Organize so you can find it | ~Done (categories, sub-categories, clusters, Obsidian, synthesis) |
| **Archivist** | Preserve the durable record; never lose anything; bring it back | Half-built (`facts.db` is the vault; it doesn't yet *notice intention* or *resurface*) |
| **Executive Assistant** | Act: detect, plan, hand off, follow up | The gap — essentially absent |

### Two acts

- **Act 0 — "Selene learns what's on your mind"** (near-term, build & live in first). A tiny
  daily *gift* grafted onto the worksheet you already use. Delight-first rediscovery + a
  capture box + guilt-free taps. Every tap silently logs an attention signal. No wants, no
  graph maturity, no handoff. Value on day one; the habit and the attention data accrue.
- **Act 1 — the dream** (later). Fragments coalesce into named **wants** via the note
  relationship graph; the assistant proposes a forming want and you bless it; a cloud LLM
  drafts a plan on anonymized input; settled steps hand off to Apple Reminders/Calendar via
  EventKit; completion reads back by ID; wants resurface organically and rest without nagging.

The decisive property: **Act 0 produces exactly what Act 1 needs** — a daily habit and an
engagement/attention dataset — and every Act 1 capability slots into the *same* worksheet
ritual. The UI evolves; the ritual never changes. No throwaway work, no cliff.

---

## Design

### Act 0 — the daily gift (the buildable near-term slice)

**Framing is load-bearing: never "your review queue," always "things I noticed for you."**
Same items, opposite habit outcome. The morning's job is **delight, not duty** — give before
it asks. Because rediscovery and connections are pure *archivist/librarian* acts, Act 0 needs
no want-tracking, no planning, no handoff, and no graph maturity to feel magical — making it
both the most delightful and the cheapest/safest thing to build.

A good morning, on the worksheet you already open:

- **Lead with a gift** — a *buried-treasure* rediscovery ("you wrote this 3 weeks ago — still
  you?") or a *connection* ("these two thoughts you had weeks apart link"). Value even if you
  tap nothing.
- **One orientation item** (secondary) — something heating up lately.
- **Capture box** — "anything on your mind?" — the brain-dump relief.
- **Guilt-free taps** — **important / keep / not now / let go**. No wrong answers.
- **≤3 items, ~30 seconds, then done** — a win every morning.

**The reaction verbs do double duty** (design them once): in Act 0 they are attention signals;
in Act 1 the *same* verbs become the want-lifecycle controls — `important` on a forming knot =
"bless this want," `let go` = graceful death, `not now` = dormancy.

**Surfacing — slot roles, leaning gift/discovery.** Each daily slot has a role so variety is
*structural* (one fresh, one old, one surprising) rather than "top-N by score" (which converges
on monotony and has no cold-start answer):

- **Buried treasure** — older, unresolved, gone-quiet note (rediscovery; high delight)
- **Connection** — two notes that just linked in the graph (off until `note_connections` is
  alive; falls back to recency)
- **Heating up** (secondary) — recent capture activity

Cold-start is trivial: with no attention data, "heating up" = most recent, "buried treasure" =
random old unreviewed note, "connection" = off. As the attention log fills, each slot gets
salience-weighted *without changing the ritual you see*. Each slot also **probes a different
kind of attention** — reacting to buried treasure tells Selene something a heating-up reaction
never could.

**The one genuinely new component:** an **attention-log table** recording every tap + capture.
Over weeks it becomes your **"top X"** via `salience = recent engagement + recency, decayed`
(use an off-the-shelf time-decay formula — e.g. the Hacker News/Reddit score; ~5 lines, not
invented). Everything else reuses shipped infra (`generate-worksheet.ts`, the iPad app, the
answer-routing).

**Chat is deferred.** A conversational interface is the heaviest thing in the whole vision
(your archived SeleneChat was exactly this and got shelved for weight). Act 0 is taps-only;
chat arrives in a later act once the habit is solid and there are wants to refine.

### Act 1 — the dream (storied end-to-end)

The improv-dinner arc, with the acting role tagged at each beat:

1. **Capture** ("want to host a dinner party for improv people") → Drafts, one line.
   *(Librarian files; Archivist preserves; Assistant flags it as a likely **want**, silent.)*
2. **Days later, different channel** (voice memo: "...maybe potluck"). *(The relationship layer
   links it to the first note — the same knot thickens.)*
3. **Worksheet** ("an 'improv dinner' seems to be forming — make it real?"). *(Assistant
   proposes; you **bless**. The knot crystallizes into a named, tracked want.)*
4. **Plan, inside Selene** — anonymized → **cloud LLM** drafts a real plan; you edit it
   (fluid, private workspace).
5. **Handoff** — you mark steps **settled**; only those flow through the EventKit bridge into
   **Apple Reminders**, each stamped with the want's ID. *(Apple owns the committed action.)*
6. **Loop** — you complete a step in Reminders; Selene reads it back **by ID**, advances the
   want. Quiet weeks → it goes **dormant** (salience decays, silent, **no nag**).
7. **Resurface** — *only on a positive signal:* a new fragment lands (it reheats) **or**
   external context makes it ripe (free weekend + plan mostly done). *(Archivist brings it
   back; Assistant judges ripeness.)*

### Key architectural decisions (captured)

- **Coalescence is the spine** — the core value is gathering scattered fragments into one
  evolving want, not one-note-one-want. This is "threads, reborn" but better-scoped: only the
  ~few % of notes carrying intention coalesce (threads tried to cluster *everything* — noisy,
  low-signal — and were archived).
- **Coalescence is actually TWO mechanisms — keep them separate.** This is the crux, and only
  one of the two is de-risked:
  - **(A) Attach a fragment to an *already-named* want** — "does this new note extend any of my
    open, blessed wants?" This is **1-to-few closed-set classification against labeled anchors**
    (the same pattern sub-categories use). It genuinely *sidesteps* the embedding-clustering
    pitfall, because the anchors already exist. **De-risked.**
  - **(B) Propose a *new* want from an *unnamed* knot** — detecting that a cluster of fragments
    is forming *before it has a name*. This **is** emergent/unsupervised clustering over the note
    graph (community detection on `note_connections`), and it may inherit the **exact homogeneity
    failure** that killed embedding clustering on the e-ink mega-bucket. **NOT de-risked — see
    Open Questions.** The "assistant proposes a forming want" beat depends entirely on B working.
- **Related ≠ same-want.** The graph *gathers candidates*; a crystallization step (assistant
  proposes → you bless) names a knot into a want with a finish line. The crystallization (the
  LLM/human judgment that "this knot is a want named X") is what bridges B's fuzzy output into
  A's labeled anchors.
- **Detection is hybrid, markerless.** LLM auto-flags candidate wants; you confirm in the
  worksheet/digest. Markerless is *required* — two of three capture channels (handwritten
  e-ink, voice) can't carry a tag/prefix, and a marker scheme at capture violates the
  zero-friction principle. Hybrid makes false negatives recoverable (silent misclassification
  is the worst failure for a "never lose it" system).
- **Per-stage model split.** *Detection* ("is this a want?") → **local** LLM (`mistral:7b`):
  high-frequency, low-stakes, private, free. *Decomposition* ("turn a want into a good plan")
  → **cloud** LLM (Claude API) on **anonymized** input: low-frequency, high-value, worth the
  round-trip. Privacy surface stays tiny — only the handful of wants you actively plan ever
  leave the machine, anonymized. **Reconciles with "everything Apple-native / Lumen-portable":**
  the cloud call is the *one* non-Apple piece, and it's deliberately isolated behind the
  anonymization boundary — in Lumen it lives in the notarized Node companion backend (outside the
  store), not the on-device app, so the device stays local-only.
- **Source of truth: Selene owns wants + fluid plans; Apple apps own committed actions.**
  Selene is the brain (hold, decompose, prioritize); Apple Reminders/Calendar are the hands.
  *Settled* steps push out; everything fluid stays in Selene.
- **The bridge is native EventKit, ID-keyed and bidirectional.** The archived Things loop was
  brittle because of **AppleScript** screen-scraping + **fuzzy concept matching** + a messy
  3-table schema — *not* because it read from an app. EventKit is one framework for Calendar
  *and* Reminders (`EKReminder`, `EKEntityType.reminder`), every item carries a stable
  `calendarItemIdentifier`, and the precedent already exists: `calendar.ts` shells out to a
  compiled Swift EventKit CLI (`selene-calendar`, `import EventKit` / `EKEventStore`). We'd
  build a fresh, properly-homed `selene-reminders` CLI on the same pattern. Matching is
  **ID-keyed, never fuzzy** (store the EventKit id on the want; stamp the want's `source_uuid`
  into the reminder notes/URL as a backref). **Maximally Lumen-portable** — a Swift EventKit
  bridge *is* Lumen-native code, nothing to rewrite when porting.
- **Fact-store placement falls out cleanly.** Human decisions (want confirmation, lifecycle,
  settled-ness, the attention taps) are *precious* → `facts.db` (survive `rebuild`, like
  `category_overrides`/`review_state`). LLM-derived guesses (actionability, fragment links,
  proposed decompositions) are *disposable* → `selene.db`. The detection/confirmation split is
  the durability split already designed for — this feature is architecturally native.
- **No nagging.** A want resurfaces only on a *positive* signal (new fragment, or external
  ripeness). A want that goes quiet just rests — out of sight, not out of existence
  (`salience` decays). "Never lose it" and "don't nag me" stop conflicting: the archivist keeps
  everything; the assistant only *speaks* about what's currently alive. (The "gone quiet → gentle
  check-in" option was explicitly rejected.)
- **Prioritization = attention, learned from usage.** "Tell me what's next" is grounded in the
  attention log built in Act 0 — what you keep capturing, opening, marking important, lately.
  Engagement is simultaneously the goal and the training data; no separate priority chore.

### Build principle: maximal reuse (hard constraint)

Prefer existing open-source software, libraries, and proven algorithms; write minimal new code
(fits a non-engineer, AI-dependent workflow). The scary pieces are mostly solved:

| Hard piece | Reuse |
|------------|-------|
| Find "knots" in the graph | Community detection (Louvain/Leiden) — e.g. `graphology`. Don't write clustering. |
| Prioritization ranking | Known time-decay score (HN/Reddit). Off the shelf. |
| Planning / decomposition | Claude API does the thinking. No planning engine. |
| Tasks / calendar | Apple EventKit. No task store. |
| Embeddings / vectors | Already running LanceDB + `nomic-embed`. |

The genuinely new code is **glue + the fact-store schema + the daily UI** — exactly where
custom effort belongs.

---

## Implementation Notes

### Parallel tracks (not blockers)

- **Diagnose `note_connections` FIRST (not "just revive it")** — the load-bearing wall for Act
  1's coalescence-mechanism B. The table is currently **empty**; connection-detection code runs
  in `process-llm.ts` but nothing lands, and this is the *same* dark spike blocking Constellation
  Phase B (`friend::` edges). **The cause is undiagnosed and it decides the whole viability of
  graph-coalescence:** if it's empty for a mechanical reason (a bug, a never-called path), reviving
  it unblocks two visions. But if it's empty *because* embedding similarity on homogeneous
  ADHD-journaling either connects everything or nothing (the e-ink lesson), then "reviving" it
  just reproduces the mega-bucket *as a graph* — and emergent-want-proposal (B) must lean on a
  different signal. So: **diagnostic spike during Act 0**, and let the cause — not the plan —
  decide whether B is viable.
- **The collaborator-scout agent** — a periodic agent (on the existing agent layer:
  `agent_jobs` / `agent-manager.ts`) that web-searches the PKM / executive-function space
  (Tana, Reflect, Mem, Logseq, Amplenote, Saga…), notes what each solved and what libraries
  they used, and files a digest. Serves the reuse principle directly ("find-me-prior-art").
  "Competitors" reframed as *collaborators* on a probably-universal dream. Separable; could
  even start now.

### Supersedes

This vision absorbs and supersedes two stale Vision docs:
- `2026-03-21-close-the-loop-design.md` (executive-function; references archived
  threads/extract-tasks/discussion_threads — a redesign waiting to happen).
- `2026-05-26-interactive-worksheets-design.md` Phase 2+ (generators) — folded into Act 0/Act 1.

### Affected / referenced code

- `src/workflows/generate-worksheet.ts` — Act 0 grafts onto this.
- `src/workflows/process-llm.ts` (`actionability` wiring; `note_connections` revival).
- `src/lib/calendar.ts` + the Swift `selene-calendar` CLI — precedent for `selene-reminders`.
- `facts.db` schema — attention log, want lifecycle (precious layer).

---

## Open Questions (Act 1 — deferred, do not block the vision)

- **⚠️ THE crux: can emergent want-knots be detected in homogeneous data? (mechanism B)**
  Proposing a *new, unnamed* want requires unsupervised clustering over the note graph — the same
  shape that *collapsed* on homogeneous e-ink journaling. If B doesn't work, the assistant can't
  *propose* forming wants; it could only match fragments to wants you've already named by hand
  (mechanism A), which is a weaker product. Resolving this is gated on the `note_connections`
  diagnostic (below). Discriminating question: **does "assistant proposes a forming want" need B,
  or can a cheaper signal (e.g. repeated capture on a topic, LLM "is a want forming?" over recent
  notes) stand in for it?**
- **Ripeness** — what exactly makes a want "ripe"? (calendar free time + plan-completeness +
  …). How smart vs. how simple?
- **Prioritization at scale** — when several wants are live/ripe at once, how does "what's
  next" pick? (attention is the basis; the selection function is open.)
- **Anonymization** — how to scrub a want before the cloud-LLM planning call. Personal-context,
  not standard PII — a genuine design challenge. (Prior art: archived phase-7.3 anonymization
  layer.)

---

## Ready for Implementation Checklist

This is a **Vision** doc (the dream is not a < 1-week scope). **Act 0** is the slice intended
to graduate to a real implementation plan first.

- [ ] Acceptance criteria defined — *Act 0 draft below; refine before promoting to Ready*
- [ ] ADHD check passed — see below (Act 0 passes strongly)
- [ ] Scope check — Act 0 only; the full vision is multi-act
- [ ] No blockers — Act 0 has none; Act 1 depends on the `note_connections` revival

### Act 0 acceptance criteria (draft)

- [ ] The daily worksheet surfaces ≤3 items via slot roles (buried-treasure-led), framed as
      "things I noticed for you," with a capture box.
- [ ] Four guilt-free reaction taps (important / keep / not now / let go) are available per item.
- [ ] Every tap and capture writes to a new attention-log table (precious / `facts.db`).
- [ ] A `salience = engagement + recency, decayed` score ranks items into a "top X."
- [ ] Cold-start works with zero attention data (slots fall back to recency / random-old).
- [ ] No new surface introduced — it extends the existing worksheet/iPad ritual.

### ADHD Design Check

- [x] **Reduces friction?** ≤3 items, ~30s, taps-only, zero-friction capture preserved.
- [x] **Visible?** Daily gift you actually open; resurfacing makes buried intentions visible.
- [x] **Externalizes cognition?** The system holds intentions, learns attention, brings things
      back — you don't track any of it mentally. Explicitly *no nagging* / no shame pile.

---

## Links

- **Branch:** (added when implementation starts)
- **PR:** (added when complete)
- **Supersedes:** `2026-03-21-close-the-loop-design.md`,
  `2026-05-26-interactive-worksheets-design.md` (Phase 2+)
- **Related:** `2026-05-29-knowledge-constellation-design.md` (shares the `note_connections`
  revival), `2026-05-31-fact-store-design.md` (precious/disposable split),
  `2026-05-26-synthesis-retrieval-agent-design.md` (the synthesis Act 0 surfaces from),
  Lumen design (EventKit bridge is Lumen-native).
