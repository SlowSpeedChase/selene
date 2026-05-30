#!/usr/bin/env python3
"""
generate-dev-fixture.py - Generate a designed showcase corpus for the Selene sandbox.

Emits a JSON array of {title, content, created_at} objects to stdout (or a file
with --out). Content is PURELY INVENTED — an ADHD knowledge-worker's note stream
with zero real PII (no real names, emails, addresses, phone numbers).

Two layers (see docs/plans/2026-05-29-dev-prod-boundary-hardening-design.md):
  - DESIGNED scenarios (always present, dated at the EARLY edge so a small
    oldest-first dev-process-batch hits them first): 3 coherent multi-note
    project/training threads that should cluster, a multi-topic "monster" note
    (the eink-mega-bucket pathology), a near-duplicate pair, length extremes,
    and one clearly-themed note per controlled category. This is what makes the
    dev corpus both *showcase* the pipeline and *gate* its behavior.
  - BACKGROUND volume (random recombination) fills the rest of --count so the
    pipeline has realistic noise around the designed shape.

The generator only controls {title, content, created_at}; categories/clusters are
assigned downstream by the LLM, so designed notes embed strong category vocabulary.
Validate by eyeballing dev output after reset+process (automated LLM assertion is
deferred by design); the generator's structural guarantees are unit-tested in
scripts/test_generate_dev_fixture.py.

The generator is deterministic: it seeds Python's `random` explicitly and dates
everything relative to a fixed epoch, so re-runs produce byte-identical output.
(This is a one-shot generator script, not workflow runtime, so stdlib `random` is fine.)

Usage:
    python3 scripts/generate-dev-fixture.py                 # 500 notes -> stdout
    python3 scripts/generate-dev-fixture.py --count 300     # custom count
    python3 scripts/generate-dev-fixture.py --days 120      # spread over N days
    python3 scripts/generate-dev-fixture.py --seed 7        # change the seed
    python3 scripts/generate-dev-fixture.py --out fixture.json
"""

import argparse
import json
import random
import sys
from datetime import datetime, timedelta, timezone

# ---------------------------------------------------------------------------
# Fictional vocabulary. All invented. No real people, companies, or places.
# ---------------------------------------------------------------------------

# Made-up project / initiative code names — deliberately whimsical so they read
# as obviously synthetic.
PROJECTS = [
    "Project Lighthouse", "the Tidepool refactor", "Operation Paper Lantern",
    "the Mossbank rewrite", "Project Clementine", "the Harbor dashboard",
    "Operation Slow Sunday", "the Willow notes app", "Project Driftwood",
    "the Copper Kettle side project", "Operation Quiet Garden", "the Saffron tool",
]

TOOLS = [
    "the kanban board", "my note-taking system", "the habit tracker",
    "a pomodoro timer", "the weekly review template", "my reading queue",
    "the inbox-zero ritual", "a body-doubling session", "the brain dump doc",
    "my someday/maybe list",
]

TOPICS = [
    "working memory", "context switching", "time blindness", "task initiation",
    "rejection sensitivity", "hyperfocus", "decision fatigue", "energy management",
    "executive function", "the planning fallacy", "spaced repetition",
    "deep work", "attention residue", "intrinsic motivation", "habit stacking",
]

# Fictional book / article titles — invented, not real publications.
READINGS = [
    '"The Quiet Engine" by a made-up author', '"Notes Toward a Calmer Desk"',
    'a fictional essay called "On Finishing Things"', '"The Tidy Mind" (invented)',
    'an imaginary paper on attention and rest', '"Small Loops, Big Loops"',
    'a fake blog post about analog planners', '"The Unhurried Week" (fictional)',
]

FEELINGS = [
    "scattered but hopeful", "weirdly calm", "overstimulated", "quietly proud",
    "restless", "focused for once", "behind but okay with it", "energized",
    "foggy", "grateful", "antsy", "settled",
]


def _sentence_pool(rng):
    """Build a fresh pool of fictional sentence fragments seeded by rng."""
    return {
        "project_idea": [
            f"Idea for {rng.choice(PROJECTS)}: break the first milestone into "
            f"tiny visible steps so {rng.choice(TOPICS)} stops eating the morning.",
            f"What if {rng.choice(PROJECTS)} just shipped the ugly version first? "
            f"Perfect is the enemy of started.",
            f"Sketched a rough plan for {rng.choice(PROJECTS)}. Three columns: "
            f"now, next, not-yet. Keep the not-yet column out of sight.",
            f"Maybe {rng.choice(PROJECTS)} doesn't need {rng.choice(TOOLS)} at all. "
            f"Reduce friction, not add it.",
        ],
        "reflection": [
            f"Felt {rng.choice(FEELINGS)} today. Noticed {rng.choice(TOPICS)} "
            f"showing up again around mid-afternoon.",
            f"Realized I keep avoiding {rng.choice(TOOLS)} because starting it "
            f"feels heavier than it actually is.",
            f"Good day. {rng.choice(TOOLS).capitalize()} actually helped me stay "
            f"with one thing instead of fifteen tabs of {rng.choice(TOPICS)}.",
            f"Note to self: when I feel {rng.choice(FEELINGS)}, the move is a walk, "
            f"not another reorganization of {rng.choice(TOOLS)}.",
        ],
        "reading": [
            f"Reading {rng.choice(READINGS)}. The bit about {rng.choice(TOPICS)} "
            f"finally made the idea click.",
            f"From {rng.choice(READINGS)}: capture first, organize later. "
            f"Trying to apply that to {rng.choice(TOOLS)}.",
            f"Disagreed with {rng.choice(READINGS)} on {rng.choice(TOPICS)} — it "
            f"assumes a tidy brain. Mine negotiates.",
        ],
        "task": [
            f"Need to follow up on {rng.choice(PROJECTS)} before it goes stale. "
            f"Smallest next action: open the file.",
            f"Three things only today: review {rng.choice(TOOLS)}, draft the "
            f"{rng.choice(PROJECTS)} outline, and stop at one coffee.",
            f"Parking this here so I stop holding it in my head: reschedule the "
            f"{rng.choice(PROJECTS)} check-in, it keeps slipping.",
        ],
        "meeting": [
            f"Sync notes (fictional): agreed {rng.choice(PROJECTS)} ships in two "
            f"phases. Action item is mine — turn it into a visible card.",
            f"Talked through {rng.choice(TOPICS)} with the imaginary team. Takeaway: "
            f"shorter loops, fewer status updates.",
            f"Stand-up recap: {rng.choice(PROJECTS)} unblocked, {rng.choice(TOOLS)} "
            f"still flaky. Owner: me. Due: someday, realistically next week.",
        ],
    }


def _make_note(rng, created_at, index):
    pools = _sentence_pool(rng)
    kind = rng.choice(list(pools.keys()))
    opener = rng.choice(pools[kind])

    # Vary length: short capture vs. a longer brain-dump.
    extra_count = rng.choices([0, 1, 2, 4], weights=[4, 5, 3, 2])[0]
    parts = [opener]
    for _ in range(extra_count):
        other_kind = rng.choice(list(pools.keys()))
        parts.append(rng.choice(pools[other_kind]))

    # Occasionally append a hashtag the ingestion tag-extractor will pick up.
    if rng.random() < 0.35:
        parts.append(f"#{rng.choice(['adhd', 'focus', 'project', 'idea', 'review', 'reading'])}")

    content = " ".join(parts)

    title_kind = {
        "project_idea": "Idea",
        "reflection": "Reflection",
        "reading": "Reading note",
        "task": "Task thought",
        "meeting": "Meeting note",
    }[kind]
    # Index folded into the title guarantees title+content uniqueness, so the
    # content_hash UNIQUE constraint in raw_notes never collides.
    title = f"{title_kind} #{index + 1}"

    return {
        "title": title,
        "content": content,
        "created_at": created_at.isoformat(),
    }


# ---------------------------------------------------------------------------
# Designed showcase scenarios — layered ON TOP of the random background so the
# pipeline has TRUE shape to find: coherent threads that should cluster, a
# multi-topic monster note (the eink-mega-bucket pathology), a near-duplicate
# pair, length extremes, and one clearly-themed note per controlled category.
#
# The generator only controls {title, content, created_at}; categories/clusters
# are assigned downstream by the LLM. So these notes embed strong category
# vocabulary the LLM should classify correctly — validated by eyeballing dev
# output (automated LLM assertion is deferred by design).
# ---------------------------------------------------------------------------

# Each beat is continued from a fixed anchor prefix, so every note in a thread
# carries the anchor token (-> they cluster) and reads as a coherent arc.
_LIGHTHOUSE_BEATS = [  # Projects & Tech
    "kicked it off today. The goal is a calmer onboarding dashboard. Sketched three milestones on one card so it stays visible.",
    "scoped milestone 1 — the dashboard data model. Keeping the feature set deliberately tiny so it actually ships.",
    "hit a blocker: the export API returns stale rows. Logged it as a bug to squash before the demo.",
    "spent the morning on the flaky sync test. Refactored the worst of it; the bug is finally reproducible.",
    "the stale-rows bug is fixed — a caching layer was holding old data. Small win, big relief.",
    "demoed the rough dashboard to myself. Ugly but it works; shipping the ugly version first was the right call.",
    "milestone 2: wiring the live feed into the dashboard. One feature at a time, no scope creep.",
    "got pulled into context-switching all day and barely touched it. Parking a note so I don't lose the thread.",
    "back on it. Cleaned up the feature flags and deleted a dead code path. The project feels lighter.",
    "wrote the tiny onboarding copy. Funny how the writing was harder than the code.",
    "milestone 3 in sight. Did a final refactor pass and fixed two edge-case bugs.",
    "shipped v1 — the onboarding dashboard is live. Closing the card and resisting the urge to gold-plate it.",
]
_HALFMARATHON_BEATS = [  # Health & Body
    "week 1. Three easy runs on the calendar. Going slow on purpose so my body adapts and I sleep better.",
    "first long run done — 5 miles. Legs heavy but the head felt clear afterward.",
    "rest day. Foam-rolled and protected my sleep instead of squeezing in a workout.",
    "tempo run felt strong. Pace is creeping faster without forcing it.",
    "niggle in my left shin. Backing off the mileage so it doesn't turn into an injury.",
    "shin's better. Easy run by the river, kept it gentle. Listening to my body for once.",
    "long run up to 8 miles. Fueling matters — bonked at mile 6 last week, not today.",
    "taper week. Less running, more sleep. Antsy energy but trusting the plan.",
    "race eve. Laid out the kit, early night, calming the nerves.",
    "race day — finished the half-marathon. Body's wrecked and happy.",
]
_SPANISH_BEATS = [  # Personal Growth
    "starting fresh. Ten minutes a day, no pressure. This is about growth, not fluency by Friday.",
    "learned the present tense. Mindset shift: mistakes are the point, not a verdict on me.",
    "missed two days and almost quit out of shame. Practicing self-compassion instead of spiraling.",
    "did a tiny conversation with the app's bot. Cringed, survived, kept going.",
    "noticed I avoid speaking because of rejection sensitivity. Naming it helps.",
    "first sentence understood in a song. Tiny dopamine hit. The habit is compounding.",
    "twenty-day streak. The growth-mindset framing is doing real work here.",
    "had a five-minute chat with a patient stranger online. Boundaries with my inner critic are holding.",
]

_CATEGORY_ANCHORS = [
    ("Personal Growth",
     "Been sitting with how I handle criticism. Working on boundaries instead of spiraling — small growth, but real. Might bring it to therapy."),
    ("Relationships & Social",
     "Coffee with an old friend today. Realized I've been a flaky friend lately; want to be more present for family and social plans."),
    ("Health & Body",
     "Slept badly again. Getting back to easy runs and protecting my sleep — my body's been running on fumes."),
    ("Projects & Tech",
     "Spun up a tiny side project tonight, a little dashboard. Fixed one annoying bug, shipped a rough feature, might refactor later."),
    ("Career & Work",
     "The performance review cycle at work is looming. Want to talk to my manager about a promotion and a clearer career path."),
    ("Creativity & Expression",
     "Started a watercolor sketchbook. Did a loose painting and some freewriting — creative muscles feel rusty, even hummed some music."),
    ("Politics & Society",
     "Read about the local zoning reform and an upcoming election. Thinking about how policy shapes the community, and whether I'll vote."),
    ("Daily Systems",
     "Reworked my morning routine and did a proper weekly review. Inbox is near zero; trying to make the habit stick and trust my calendar."),
]

_MONSTER_NOTE = (
    "Sunday reset brain dump — everything in my head at once. Slept badly so my body feels off; "
    "need to get back to easy runs and guard my sleep this week. Work is heavy: the performance "
    "review is coming and I want to ask my manager about a promotion, but I keep avoiding it. "
    "Project Lighthouse still has one open bug in the dashboard feature I should refactor before "
    "the demo. On the home front I've been a flaky friend — owe my sister a call and want more real "
    "time with family. Creatively I miss painting; the watercolor sketchbook is gathering dust and "
    "I haven't done any writing. Read about the local zoning fight and the upcoming election and got "
    "anxious about the community, then doom-scrolled instead of voting research. My whole daily "
    "system is fraying: inbox overflowing, no weekly review done, calendar ignored. Underneath it "
    "all is the same growth work — criticism sends me spiraling and my boundaries are mush. Naming "
    "it here so it's out of my head and on the page where I can actually look at it."
)


def build_designed_notes():
    """Return the designed showcase notes as rich dicts (title, content, scenario,
    anchor, _minute_offset). `generate()` strips these to the 3-field output."""
    notes = []
    offset = [0]
    GAP = 180  # minutes between designed notes; keeps them early in the window

    def add(title, content, scenario, anchor=None):
        notes.append({
            "title": title, "content": content, "scenario": scenario,
            "anchor": anchor, "_minute_offset": offset[0],
        })
        offset[0] += GAP

    # Three coherent threads (anchor token in every note -> they cluster).
    for i, beat in enumerate(_LIGHTHOUSE_BEATS):
        add(f"Project Lighthouse update {i + 1}", f"Project Lighthouse — {beat}",
            "thread:lighthouse", anchor="Project Lighthouse")
    for i, beat in enumerate(_HALFMARATHON_BEATS):
        add(f"Half-marathon training day {i + 1}", f"Half-marathon training — {beat}",
            "thread:halfmarathon", anchor="half-marathon")
    for i, beat in enumerate(_SPANISH_BEATS):
        add(f"Learning Spanish day {i + 1}", f"Learning Spanish — {beat}",
            "thread:spanish", anchor="learning Spanish")

    # One clearly-themed anchor note per controlled category.
    for category, content in _CATEGORY_ANCHORS:
        add(f"On {category.lower()}", content, f"category:{category}")

    # Multi-topic monster note (long extreme + multi-membership pathology).
    add("Sunday reset brain dump", _MONSTER_NOTE, "monster")

    # Near-duplicate pair (the truth exists in content; surfacing as a connection
    # is gated on the empty note_connections write path — out of scope here).
    add("Recurring thought (1)",
        "Recurring thought: I keep reorganizing my note-taking system instead of "
        "actually writing. The reorganizing feels productive, but it is really just avoidance.",
        "near_dup")
    add("Recurring thought (2)",
        "Recurring thought: I keep reorganizing my note-taking system instead of "
        "actually writing. The reorganizing feels productive, but it is honestly just avoidance.",
        "near_dup")

    # Short extremes (one-liners).
    add("Quick capture", "Call the dentist.", "length_extreme")
    add("Quick capture", "idea: tiny widget", "length_extreme")

    return notes


def generate(count, days, seed):
    rng = random.Random(seed)
    # Anchor the window to a fixed end date so output is fully deterministic
    # regardless of when the script runs.
    end = datetime(2026, 5, 28, 9, 0, 0, tzinfo=timezone.utc)
    start = end - timedelta(days=days)
    span_seconds = int((end - start).total_seconds())

    # Designed notes: dated deterministically at the EARLY edge of the window so a
    # small dev-process-batch (oldest-first) hits them first; threads stay ordered.
    designed = build_designed_notes()
    notes = []
    for dn in designed:
        created_at = start + timedelta(minutes=dn["_minute_offset"])
        notes.append({
            "title": dn["title"],
            "content": dn["content"],
            "created_at": created_at.isoformat(),
        })

    # Background volume fills the remainder of `count` (designed are part of the total).
    bg_count = max(0, count - len(designed))
    for i in range(bg_count):
        offset = rng.randint(0, span_seconds)
        created_at = start + timedelta(seconds=offset)
        notes.append(_make_note(rng, created_at, i))

    # Sort chronologically so a seeded run reads like a real capture stream.
    notes.sort(key=lambda n: n["created_at"])
    return notes


def main():
    parser = argparse.ArgumentParser(description="Generate fictional Selene dev notes.")
    parser.add_argument("--count", type=int, default=500, help="number of notes (default 500)")
    parser.add_argument("--days", type=int, default=90, help="spread over N days (default 90)")
    parser.add_argument("--seed", type=int, default=42, help="random seed (default 42)")
    parser.add_argument("--out", type=str, default=None, help="write to file instead of stdout")
    args = parser.parse_args()

    notes = generate(args.count, args.days, args.seed)
    payload = json.dumps(notes, indent=2)

    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(payload)
        print(f"Wrote {len(notes)} fictional notes to {args.out}", file=sys.stderr)
    else:
        print(payload)


if __name__ == "__main__":
    main()
