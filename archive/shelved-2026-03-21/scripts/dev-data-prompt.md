# Dev Seed Data Generator Prompt

This file contains a prompt you can paste into any capable LLM (Claude, ChatGPT, Gemini, etc.) to generate ~500 fictional notes for seeding the Selene development database.

## Why a Prompt Instead of a Script?

- No dependencies to install or maintain
- Easy to regenerate with variations
- The LLM produces more natural, realistic data than any template-based generator
- Anyone can run it without project setup

## Usage

1. Copy the entire **Prompt** section below (between the `---` markers)
2. Paste it into an LLM chat (Claude or ChatGPT recommended — needs a large output window)
3. If the LLM truncates output, ask it to "continue from where you left off" — it should resume the JSON array
4. Save the complete JSON output to `fixtures/dev-seed-notes.json` in the project root
5. Run the verification steps below to confirm the output is valid

> **Tip:** Claude with a long output mode or ChatGPT-4 with canvas work well for this. You may need to ask the model to produce the data in batches (e.g., "generate notes 1-100", then "generate notes 101-200", etc.) and concatenate them yourself.

---

## Prompt

You are a test data generator. Your job is to produce a JSON fixture file of ~500 fictional notes for a personal knowledge management system designed for people with ADHD. Output ONLY valid JSON — no explanations, no markdown fences, no commentary before or after the array.

This is entirely FICTIONAL data for software testing. No real personal information.

### Schema

Produce a JSON array of objects. Each object has exactly these fields:

```json
{
  "title": "string — short descriptive title (3-10 words)",
  "content": "string — the note body, 1 sentence to 3 paragraphs",
  "created_at": "ISO 8601 datetime with timezone, e.g. 2025-12-03T14:22:00-08:00",
  "tags": ["#tag1", "#tag2"]
}
```

### The Fictional Persona

The notes belong to **Alex**, a 31-year-old software engineer with ADHD (combined type, diagnosed at 27) living in Los Angeles. Alex uses a quick-capture note app throughout the day to dump thoughts, track projects, and externalize working memory.

Alex's life domains and their approximate share of notes:

**Work (30% — ~150 notes):**
Alex is a mid-level engineer at a startup by day, but the real energy goes into a side project: a recipe app called "Mise" (mise en place). Notes cover:
- Sprint standup summaries and blockers at the day job
- Mise API design decisions (REST vs GraphQL, auth strategy, image handling)
- Code review feedback given and received
- Architecture sketches ("should Mise use SQLite or Postgres?")
- Freelance/contract feelers and career reflections
- Occasional frustration with meetings and context-switching

**Learning (20% — ~100 notes):**
Alex started a beginner ceramics class in November and is obsessed. Also reads widely. Notes cover:
- Ceramics: wheel throwing techniques, glaze chemistry, kiln schedules, studio etiquette
- Books being read: "Four Thousand Weeks" by Oliver Burkeman, "Thinking in Systems" by Donella Meadows, a sci-fi novel ("Project Hail Mary")
- Podcast takeaways (Huberman Lab, Lex Fridman, Acquired)
- An online course on Kubernetes that keeps getting abandoned and restarted

**Health (20% — ~100 notes):**
- ADHD medication tracking (Vyvanse 40mg, dose timing, effectiveness windows)
- Exercise: bouldering 2x/week, occasional runs, yoga attempts
- Sleep log entries ("woke up at 3am again, brain wouldn't stop")
- Therapy session reflections (CBT for ADHD)
- Productivity meta-observations ("I notice I do my best work between 10am-12pm")
- Nutrition experiments (protein targets, meal prep attempts)

**Personal (15% — ~75 notes):**
- Planning a February camping trip to Joshua Tree with friends
- Apartment renovation: kitchen backsplash tile project, paint colors for bedroom
- Social events: game nights, a friend's birthday, a concert
- Gift ideas for people
- Relationship reflections

**Random (15% — ~75 notes):**
- Shower thoughts and philosophical musings
- Quick captures: grocery lists, to-do items, "remind me to..." notes
- Movie/show reactions ("just watched Dune Part Two, the sound design...")
- Restaurant recommendations
- Random observations about LA life
- Fleeting ideas that go nowhere

### Temporal Distribution

The notes span exactly **November 15, 2025 through February 15, 2026** (3 months). All timestamps use Pacific Time (UTC-8).

Follow these patterns:

- **Weekdays** have more work notes during 9am-5pm, personal/learning notes cluster in evenings (6pm-11pm)
- **Weekends** have almost no work notes; ceramics class is Saturday mornings; personal projects fill the rest
- **Productive bursts:** Some days have 5-8 notes (hyperfocus days). The next day often has only 0-2 notes (recovery/avoidance). Create 8-10 of these burst clusters across the 3 months.
- **Late-night sessions:** ~15 notes should be between 11pm-3am (hyperfocus rabbit holes, insomnia captures)
- **Holiday patterns:** Fewer notes around Thanksgiving (Nov 27), Christmas (Dec 25), and New Year's. A reflective burst in early January.
- **Overall trend:** Note frequency increases slightly over time as Alex gets more comfortable with the capture habit (averaging ~4/day in Nov, ~6/day in Feb)

### Content Characteristics

**Length distribution:**
- ~15% (75 notes): One-sentence quick captures. Examples: "Need to buy more clay", "Mise: add pagination to /recipes endpoint", "Joshua Tree campsite reservation opens Dec 1"
- ~60% (300 notes): One paragraph (3-6 sentences). The typical daily note.
- ~25% (125 notes): Two to three paragraphs. Deeper reflections, architecture decisions, therapy takeaways.

**Cross-references (important for thread detection):**
Notes should naturally reference earlier thoughts WITHOUT using IDs or links — just natural language callbacks:
- "Following up on that Mise API auth decision from last week — went with JWT after all"
- "The ceramics glaze I mentioned mixing last Saturday turned out amazing in the kiln"
- "Still thinking about that systems thinking concept from the Meadows book"
- "Joshua Tree planning update: Sarah confirmed she's coming"
Include at least 30-40 of these cross-references scattered throughout.

**Emergent threads (8-12 should be detectable):**
The following topical threads should emerge naturally from the data. Do NOT label them — just make sure enough related notes exist:
1. Mise recipe app development (architecture, features, pivots) — ~25 notes
2. Ceramics journey (beginner to intermediate progression) — ~20 notes
3. ADHD medication optimization — ~15 notes
4. Joshua Tree trip planning — ~12 notes
5. Kitchen renovation project — ~10 notes
6. Sleep quality struggles — ~12 notes
7. The "should I leave my job?" career question — ~10 notes
8. Kubernetes learning attempts — ~8 notes
9. Reading/book reflections thread — ~10 notes
10. Bouldering progression — ~8 notes

**ADHD-specific patterns (critical for authenticity):**
- Hyperfocus entries: long, detailed, enthusiastic notes on a single topic followed by days of silence on it
- Task switching: notes that start on one topic and drift to another mid-paragraph
- Executive function observations: "I've been staring at this PR for 20 minutes and can't start reviewing it"
- Medication effects: "Vyvanse kicked in, suddenly the codebase makes sense again"
- Time blindness: "Wait, it's 2am? I've been reading about glaze chemistry for 4 hours"
- Guilt/shame spirals: "Haven't touched the Kubernetes course in 3 weeks, who am I kidding"
- Compensatory strategies: "Setting a 25-min timer for this code review. Just start."
- Emotional dysregulation moments: "Got unreasonably frustrated at the standup today, need to sit with that"
- Dopamine-seeking: "Opened 14 browser tabs about camping gear instead of doing actual trip planning"

**Tone and voice:**
- Informal, sometimes stream-of-consciousness
- Occasional typos or shorthand ("w/", "bc", "tbh", "ngl")
- Mix of lowercase-casual and properly formatted
- Some notes are clearly voice-transcribed (slightly rambly, no punctuation)
- Emotional range: excited, frustrated, reflective, anxious, proud, tired

**Tags:**
Each note should have 1-3 tags using `#hashtag` format. Use a consistent but organic set:
- Work: #work, #mise, #api, #code-review, #career, #meetings
- Learning: #ceramics, #reading, #podcast, #kubernetes, #learning
- Health: #adhd, #medication, #exercise, #sleep, #therapy, #bouldering
- Personal: #joshua-tree, #apartment, #social, #cooking
- Meta: #idea, #todo, #reflection, #hyperfocus, #wins

### Output Requirements

- Valid JSON array (parseable by `JSON.parse()` or `jq`)
- No trailing commas
- Sorted by `created_at` ascending (oldest first)
- Exactly between 480-520 note objects
- All string values properly escaped (especially quotes and newlines within content)
- Output ONLY the JSON array, nothing else

### Quality Check

Before outputting, verify:
1. Notes span Nov 15, 2025 to Feb 15, 2026
2. Domain distribution roughly matches the percentages
3. At least 8 distinct topical threads are traceable
4. At least 30 cross-references exist between notes
5. ADHD patterns appear throughout (not just in health notes)
6. Timestamp patterns feel realistic (not evenly distributed)
7. The JSON is valid

---

## Verification

After saving the output to `fixtures/dev-seed-notes.json`, run these checks:

```bash
# 1. Validate JSON and count notes
cat fixtures/dev-seed-notes.json | jq length
# Expected: 480-520

# 2. Check date range
cat fixtures/dev-seed-notes.json | jq -r '.[0].created_at, .[-1].created_at'
# Expected: first ~2025-11-15, last ~2026-02-15

# 3. Check schema completeness (every note has all 4 fields)
cat fixtures/dev-seed-notes.json | jq '[.[] | select(.title == null or .content == null or .created_at == null or .tags == null)] | length'
# Expected: 0

# 4. Tag distribution
cat fixtures/dev-seed-notes.json | jq '[.[].tags[]] | group_by(.) | map({tag: .[0], count: length}) | sort_by(-.count) | .[:15]'
# Should show a reasonable spread across domains

# 5. Notes per month
cat fixtures/dev-seed-notes.json | jq '[.[].created_at[:7]] | group_by(.) | map({month: .[0], count: length})'
# Should show increasing trend: Nov < Dec < Jan < Feb

# 6. Quick visual spot-check
cat fixtures/dev-seed-notes.json | jq '.[42]'
# Read a random note — does it feel like a real person wrote it?
```

If any check fails, paste the failing check back to the LLM and ask it to fix the output.

## Loading Into Dev Database

Once verified, use the existing seed script:

```bash
# Reset and seed the dev database
./scripts/dev-reset-db.sh
./scripts/dev-seed-data.sh --fixture fixtures/dev-seed-notes.json
```

Or load manually:

```bash
cat fixtures/dev-seed-notes.json | jq -c '.[]' | while read -r note; do
  curl -s -X POST http://localhost:5678/webhook/api/drafts \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $SELENE_API_TOKEN" \
    -d "$note"
done
```
