# Selene User Guide

This is the practical guide and the hub for everything you do with Selene. Not what the system does internally — what *you* do, and when. Each feature also has its own focused guide (see **Feature Guides** below) covering how you use it, how it works, and how to fix it.

---

## What Selene Is For You

Selene externalizes your working memory. The problem it solves isn't capturing ideas (you already do that in Drafts, on paper, in voice memos) — it's that captured thoughts disappear into silos and never connect. Selene is the connective tissue: it ingests everything you capture, extracts the patterns, and resurfaces what matters so you don't have to hold it in your head.

The design philosophy is ADHD-first: zero friction to capture, automatic organization, and visible outputs you can actually see without searching.

---

## The Core Loop

```
You type a thought in Drafts
        ↓
Selene ingests it in seconds
        ↓
Every 5 minutes: LLM extracts concepts, category, tags
        ↓
Every hour: Obsidian vault updated
        ↓
Every morning 6am: Apple Notes digest delivered
        ↓
On demand: agent proposes enrichments to your Things tasks (you approve)
```

That's it. You capture, the system does the rest.

---

## Feature Guides

Each feature has its own guide — how you use it, how it works, and how to fix it when something breaks.

- [Capturing notes](guides/features/capturing-notes.md) — every way a thought gets into Selene (Drafts, iOS shortcut, e-ink notebook).
- [Obsidian library](guides/features/obsidian-library.md) — your curated, browsable vault: notes, Maps of Content, and the dashboard.
- [Daily digest](guides/features/daily-digest.md) — the 6am "Selene Daily" note in Apple Notes.
- [Folio delivery](guides/features/folio-delivery.md) — read and annotate Selene documents on your iPad.
- [Agent enrichments](guides/features/agent-enrichments.md) — propose tags and context notes for your Things tasks, with your approval.
- [Interactive worksheets](guides/features/interactive-worksheets.md) — daily review form on your iPad: write freehand, Selene OCRs and saves, then shows where you've mentioned the same things before.
- [Synthesis layer](guides/features/synthesis-layer.md) — topics you keep circling, when your understanding shifts, and unexpected connections between old and new notes — delivered in the morning digest automatically.

---

## Daily Touchpoints

### Morning — Your Digest (6am, ~5 minutes)

1. Open **Apple Notes** on your phone or Mac
2. Find the pinned note **"Selene Daily"**
3. Skim it — yesterday's captures, extracted themes, patterns

That's your entire morning Selene interaction. You're looking for surprises: things you noticed that you'd already forgotten, recurring themes, ideas that connected across different captures.

> **What if the note isn't there?** Run `npx ts-node src/workflows/send-digest.ts` to regenerate, or check logs: `tail -f logs/selene.log | npx pino-pretty`

---

### During the Day — Capturing (under 30 seconds)

The only thing you need to do actively is **capture**. Everything else is automatic.

**From any iPhone/iPad moment:**
- Open Drafts
- Type the thought (title is optional but helps with search later)
- Run the **"Send to Selene"** action
- Done

**Hashtags that help downstream:**
- `#idea` — raw concepts
- `#task` — things you want to do  
- `#question` — open loops
- `#insight` — connections you noticed

These aren't required. They make concept extraction sharper and your Obsidian categories cleaner.

**From paper (e-ink pipeline):**
- Your Kindle Scribe notebooks auto-export PDFs to a watched folder
- Selene OCRs them via Ollama vision (`qwen2.5vl`) and ingests them directly — no Drafts step
- See [Capturing notes](guides/features/capturing-notes.md) for the full pipeline and how to redo a file

---

### Browsing — Obsidian (5+ minutes, when you want to reflect)

Your Obsidian vault is the visual interface. Open it when you have time to think, not just capture.

**What's there:**
- One note per capture, with extracted concepts in frontmatter
- `Dashboard.md` — categories, recent notes, entry point
- Category MOCs (Maps of Content) — e.g., "Projects & Tech", "Health & Body"

**8 categories Selene uses:**
Personal Growth · Relationships & Social · Health & Body · Projects & Tech · Career & Work · Creativity & Expression · Politics & Society · Daily Systems

**Useful browsing habits:**
- Open a category MOC and scan essences (the one-sentence distillations) — you don't have to read full notes
- Look for notes you've forgotten about — that's the point
- Use Obsidian's search with a concept word you're thinking about

> **Vault location:** `~/selene/vault/` (the `vault/` folder in the project root). See [Obsidian library](guides/features/obsidian-library.md) for the full layout.

---

### Reading on iPad — Folio Delivery (available now)

To read and annotate a Selene document on your iPad today, use folio delivery: run one command on your Mac, scan the QR code, and the document opens in a clean reader over your home WiFi. See [Folio delivery](guides/features/folio-delivery.md).

### Browsing — iPad Dashboard (planned — PKM browse layer)

When the PKM browse layer ships, you'll be able to open Safari on your iPad to:

```
http://[your-mac-lan-ip]:5678/pkm/
```

No app install, no auth, works on your local network. Shows:
- Recent essences at a glance
- Category grid with note counts
- Concept frequency map
- "On this day" from prior years
- Review queue (notes you haven't seen in 7+ days)

This replaces needing Obsidian open for casual browsing.

---

### Agent Reports — Things Task Enrichment (available now)

The agent layer enriches your Things tasks with context from your note archive:

1. You run the enricher for a Things project (it doesn't run on its own yet)
2. For each task missing notes or tags, it queries your Selene note archive
3. It proposes: a one-sentence context note + up to 3 tags
4. You approve or reject each proposal in a web dashboard at:

```
http://localhost:5678/dashboard
```

5. Only approved proposals are written to Things

**The contract:** the agent *proposes*, you *decide*. Nothing executes without your approval. See [Agent enrichments](guides/features/agent-enrichments.md) for how to run it and what's automated vs. manual today.

---

## What Runs Automatically (Background)

You don't touch any of this. It's managed by launchd on your Mac.

| What | When | Output |
|------|------|--------|
| **Ingest** | Immediately on webhook | Note stored in database |
| **LLM Processing** | Every 5 minutes | Concepts, category, sentiment extracted |
| **Essence Distillation** | Every 5 minutes | 1-sentence distillation written |
| **Obsidian Export** | Every hour | Vault updated with new/changed notes |
| **Daily Summary** | Midnight | Day's insights aggregated |
| **Digest Delivery** | 6am | Pinned Apple Note updated |

**Verify everything is running:**
```bash
launchctl list | grep selene
curl http://localhost:5678/health
```

**View logs:**
```bash
tail -f logs/selene.log | npx pino-pretty
```

---

## When Something Seems Off

**No morning digest:** The server may have been asleep. Check `launchctl list | grep selene.send-digest` — if it shows `0` in the last column, it ran fine. If it shows a non-zero exit code:
```bash
tail -30 logs/selene.log | npx pino-pretty
```

**Notes not appearing in Obsidian:** Export runs hourly. Wait, or trigger manually:
```bash
npx ts-node src/workflows/export-obsidian.ts
```

**Process-llm stuck:** Check if Ollama is running:
```bash
curl http://localhost:11434/api/tags
```
If not: `ollama serve`

**Full restart of all agents:**
```bash
./scripts/install-launchd.sh
```

---

## What Was Built and Why It Was Simplified (2026-03-21)

From late 2025 through early 2026, Selene grew to include:
- **SeleneChat** — a macOS chat app with thread detection, task extraction, morning briefings, planning assistant
- **SeleneMobile** — a full iOS app with push notifications, live activities, Tailscale networking
- **Thread system** — semantic clustering of notes into "threads", momentum tracking, lifecycle management
- **30+ REST API endpoints**

**What worked:** The core ideas — threads surfacing patterns across notes, task extraction from captures, momentum tracking — were genuinely useful. The ADHD value was real.

**Why it was archived:** The complexity crossed a threshold where maintaining the system required more cognitive overhead than it saved. A 20,000-line codebase with two native apps, Docker-era debt, and fragile AppleScript bridges was hard to run and impossible to extend. Classic over-engineering spiral.

**What was kept:** The capture → LLM process → browse pipeline. Everything that works automatically with zero user maintenance.

**What's being rebuilt — correctly this time:**
- The agent layer rebuilds the "Selene acts on my behalf" idea, but scoped tightly: one agent, closed action vocabulary, human approval required. No autonomous execution.
- The PKM browse layer rebuilds the "browse your thinking" idea without a native app: just a LAN web page served from the existing Fastify server.

---

## Recently Shipped

### Agent Layer (shipped)

Enriches your Things tasks with context from your note archive. For a task like "Research standing desk options," the agent finds what you've written about ergonomics, health, or that topic, and proposes tags and a one-sentence "why this matters" note. You review and approve/reject in the web dashboard at `/dashboard`. This is the foundation for future agents (calendar preparation, email drafts, etc.). See [Agent enrichments](guides/features/agent-enrichments.md).

### E-Ink Notebook Ingestion (shipped)

Your Kindle Scribe handwritten notebooks auto-flow into Selene via Ollama vision OCR (`qwen2.5vl`) and ingest directly — no Drafts step. See [Capturing notes](guides/features/capturing-notes.md).

### Folio Delivery (shipped)

Read and annotate Selene documents on your iPad over your home WiFi. See [Folio delivery](guides/features/folio-delivery.md).

## Recently Shipped (continued)

### Interactive Worksheets (shipped)

A structured daily review on your iPad. Two handwriting fields where you write with Apple Pencil, plus a note-review section surfacing your backlog. On submit: Vision OCR converts ink to text, notes are saved, and Selene shows you past notes you've written on the same topics. See [Interactive worksheets](guides/features/interactive-worksheets.md).

---

## What's Being Built Now

### PKM Browse Layer (planned)

**Status:** Design complete, ready to implement.

A read-only LAN web dashboard at `/pkm/*` served from the existing Fastify server. Replaces Obsidian as the primary iPad browse surface. No new processes, no app installs.

---

## Quick Reference

```bash
# Is everything healthy?
launchctl list | grep selene
curl http://localhost:5678/health

# View live logs
tail -f logs/selene.log | npx pino-pretty

# How many notes do I have?
sqlite3 data/selene.db "SELECT COUNT(*) FROM raw_notes WHERE test_run IS NULL;"

# Trigger Obsidian export now
npx ts-node src/workflows/export-obsidian.ts

# Regenerate today's digest now
npx ts-node src/workflows/send-digest.ts

# Restart all background agents
./scripts/install-launchd.sh
```
