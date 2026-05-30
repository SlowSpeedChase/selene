#!/usr/bin/env python3
"""
Structural tests for generate-dev-fixture.py (the designed showcase corpus).

We test the GENERATOR's guarantees, not LLM output: the generator only controls
{title, content, created_at}; categories/clusters are assigned downstream by the
LLM (and the design explicitly defers automated assertion of that — eyeball it).
So here we assert the designed scenarios are embedded, the output shape is right,
generation is deterministic, and there's no PII.

Run:  python3 scripts/test_generate_dev_fixture.py
"""

import importlib.util
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
# The generator filename is hyphenated (not a valid module name), so load by path.
_spec = importlib.util.spec_from_file_location("gen_dev_fixture", os.path.join(HERE, "generate-dev-fixture.py"))
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)

CATEGORIES = [
    "Personal Growth", "Relationships & Social", "Health & Body", "Projects & Tech",
    "Career & Work", "Creativity & Expression", "Politics & Society", "Daily Systems",
]

# Signature vocabulary per category — the generator must embed these so (a) the test
# can detect coverage and (b) the downstream LLM classifies into the intended category.
CATEGORY_KEYWORDS = {
    "Personal Growth": ["growth", "criticism", "boundaries", "therapy", "mindset"],
    "Relationships & Social": ["friend", "relationship", "family", "social"],
    "Health & Body": ["run", "sleep", "workout", "marathon", "body"],
    "Projects & Tech": ["project", "refactor", "dashboard", "bug", "feature"],
    "Career & Work": ["work", "career", "manager", "performance review", "promotion"],
    "Creativity & Expression": ["paint", "sketch", "writing", "watercolor", "music"],
    "Politics & Society": ["zoning", "election", "policy", "community", "vote"],
    "Daily Systems": ["routine", "inbox", "habit", "weekly review", "calendar"],
}


def _has_any(text, keywords):
    t = text.lower()
    return any(k in t for k in keywords)


def _jaccard(a, b):
    sa, sb = set(a.lower().split()), set(b.lower().split())
    return len(sa & sb) / len(sa | sb) if (sa | sb) else 0.0


class TestDesignedScenarios(unittest.TestCase):
    def setUp(self):
        self.designed = gen.build_designed_notes()

    def test_at_least_two_coherent_threads_each_substantial(self):
        threads = {}
        for n in self.designed:
            s = n["scenario"]
            if s.startswith("thread:"):
                threads.setdefault(s, []).append(n)
        self.assertGreaterEqual(len(threads), 2, "need >=2 coherent project threads")
        for s, notes in threads.items():
            self.assertGreaterEqual(len(notes), 8, f"thread {s} should be substantial (>=8 notes)")
            # Every note in a thread shares the thread's anchor token (so they cluster).
            anchor = notes[0].get("anchor")
            self.assertTrue(anchor, f"thread {s} notes must carry an 'anchor' token")
            for note in notes:
                self.assertIn(anchor.lower(), note["content"].lower())

    def test_multi_topic_monster_note(self):
        monsters = [n for n in self.designed if n["scenario"] == "monster"]
        self.assertGreaterEqual(len(monsters), 1, "need >=1 multi-topic monster note")
        m = monsters[0]
        self.assertGreater(len(m["content"]), 800, "monster note should be a long brain-dump")
        hits = sum(1 for kws in CATEGORY_KEYWORDS.values() if _has_any(m["content"], kws))
        self.assertGreaterEqual(hits, 5, "monster note should span >=5 categories")

    def test_near_duplicate_pair_exists(self):
        # NOTE: scoped to "the pair EXISTS in content". It will NOT surface as a
        # note_connection until the empty note_connections/note_associations write
        # path is fixed (the Constellation Phase B diagnostic spike) — out of scope here.
        nd = [n for n in self.designed if n["scenario"] == "near_dup"]
        self.assertGreaterEqual(len(nd), 2, "need a near-duplicate pair")
        a, b = nd[0]["content"], nd[1]["content"]
        self.assertNotEqual(a, b, "near-dup pair should differ slightly (not identical)")
        self.assertGreater(_jaccard(a, b), 0.7, "near-dup pair should be highly similar")

    def test_all_eight_categories_have_an_anchor_note(self):
        covered = {n["scenario"].split(":", 1)[1] for n in self.designed
                   if n["scenario"].startswith("category:")}
        for c in CATEGORIES:
            self.assertIn(c, covered, f"category '{c}' needs an anchor note")
        # And each anchor's content actually carries that category's vocabulary.
        for n in self.designed:
            if n["scenario"].startswith("category:"):
                cat = n["scenario"].split(":", 1)[1]
                self.assertTrue(_has_any(n["content"], CATEGORY_KEYWORDS[cat]),
                                f"anchor for '{cat}' lacks its signature vocabulary")

    def test_length_extremes(self):
        lengths = [len(n["content"]) for n in self.designed]
        self.assertLess(min(lengths), 25, "need a one-liner (short extreme)")
        self.assertGreater(max(lengths), 800, "need a long brain-dump (long extreme)")


class TestOutput(unittest.TestCase):
    def test_output_shape_and_includes_designed(self):
        notes = gen.generate(count=200, days=90, seed=42)
        self.assertEqual(len(notes), 200)
        for n in notes:
            self.assertEqual(set(n.keys()), {"title", "content", "created_at"})
        joined = " ".join(n["content"] for n in notes)
        self.assertIn("Project Lighthouse", joined, "designed thread must be present in output")

    def test_designed_notes_always_present_even_if_count_small(self):
        notes = gen.generate(count=5, days=90, seed=42)
        self.assertGreaterEqual(len(notes), len(gen.build_designed_notes()))

    def test_deterministic_byte_identical(self):
        a = gen.generate(count=200, days=90, seed=42)
        b = gen.generate(count=200, days=90, seed=42)
        self.assertEqual(a, b, "same seed must produce byte-identical output (incl. dates)")

    def test_no_pii(self):
        notes = gen.generate(count=200, days=90, seed=42)
        blob = " ".join(n["content"] + " " + n["title"] for n in notes)
        self.assertNotRegex(blob, r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", "no emails")
        self.assertNotRegex(blob, r"\b\d{3}[-.]\d{3}[-.]\d{4}\b", "no phone numbers")


if __name__ == "__main__":
    unittest.main(verbosity=2)
