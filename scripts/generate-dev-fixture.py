#!/usr/bin/env python3
"""
generate-dev-fixture.py - Generate fictional dev notes for the Selene sandbox.

Emits a JSON array of {title, content, created_at} objects to stdout (or a file
with --out). Content is PURELY INVENTED — an ADHD knowledge-worker's note stream
with zero real PII (no real names, emails, addresses, phone numbers). It exists
only to give the dev database (~/selene-data-dev/selene.db) realistic-looking
volume so the processing pipeline has something to chew on.

The generator is deterministic: it seeds Python's `random` explicitly so re-runs
produce the same fixture. (This is a one-shot generator script, not workflow
runtime, so stdlib `random` is fine here.)

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


def generate(count, days, seed):
    rng = random.Random(seed)
    # Anchor the window to a fixed end date so output is fully deterministic
    # regardless of when the script runs.
    end = datetime(2026, 5, 28, 9, 0, 0, tzinfo=timezone.utc)
    start = end - timedelta(days=days)
    span_seconds = int((end - start).total_seconds())

    notes = []
    for i in range(count):
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
