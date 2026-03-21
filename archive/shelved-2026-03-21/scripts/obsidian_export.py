#!/usr/bin/env python3
"""
Obsidian Export Script for Selene
Exports processed notes with ADHD-optimized formatting to Obsidian vault
"""

import sqlite3
import json
import os
from datetime import datetime
from pathlib import Path
import re


def get_notes_for_export(db_path, note_id=None):
    """Query database for notes ready to export

    Args:
        db_path: Path to SQLite database
        note_id: Optional - if provided, export only this specific note (raw_notes.id)
    """
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    if note_id:
        # Export specific note by ID
        query = """
        SELECT
            rn.id, rn.title, rn.content, rn.created_at, rn.tags, rn.word_count,
            pn.concepts, pn.primary_theme, pn.secondary_themes,
            pn.overall_sentiment, pn.sentiment_score, pn.emotional_tone,
            pn.energy_level, pn.sentiment_data
        FROM raw_notes rn
        JOIN processed_notes pn ON rn.id = pn.raw_note_id
        WHERE rn.id = ?
            AND rn.status = 'processed'
            AND pn.sentiment_analyzed = 1
        """
        cursor.execute(query, (note_id,))
    else:
        # Export all pending notes (batch mode)
        query = """
        SELECT
            rn.id, rn.title, rn.content, rn.created_at, rn.tags, rn.word_count,
            pn.concepts, pn.primary_theme, pn.secondary_themes,
            pn.overall_sentiment, pn.sentiment_score, pn.emotional_tone,
            pn.energy_level, pn.sentiment_data
        FROM raw_notes rn
        JOIN processed_notes pn ON rn.id = pn.raw_note_id
        WHERE rn.exported_to_obsidian = 0
            AND rn.status = 'processed'
            AND pn.sentiment_analyzed = 1
        ORDER BY rn.created_at DESC
        LIMIT 50
        """
        cursor.execute(query)

    notes = [dict(row) for row in cursor.fetchall()]
    conn.close()

    return notes


def parse_json_field(field, default=None):
    """Safely parse JSON fields"""
    if not field:
        return default if default is not None else []
    try:
        return json.loads(field)
    except (json.JSONDecodeError, TypeError):
        return default if default is not None else []


def extract_action_items(content):
    """Extract TODO items from note content"""
    action_items = []

    # Pattern 1: Checkbox format
    checkboxes = re.findall(r'^[-*]\s*\[[ x]\]\s*(.+)$', content, re.MULTILINE | re.IGNORECASE)
    action_items.extend(checkboxes)

    # Pattern 2: TODO/TASK/ACTION format
    todos = re.findall(r'^[-*]\s*(?:TODO|TASK|ACTION)[:)]\s*(.+)$', content, re.MULTILINE | re.IGNORECASE)
    action_items.extend(todos)

    # Pattern 3: "need to", "should", etc.
    intentions = re.findall(r'\b(?:need to|should|must|have to|remember to)\s+([^.!?]+)', content, re.IGNORECASE)
    action_items.extend(intentions)

    # Clean and deduplicate
    cleaned = []
    for item in action_items:
        item = item.strip()
        if 5 < len(item) < 200 and item not in cleaned:
            cleaned.append(item)

    return cleaned[:10]  # Limit to 10 items


def generate_adhd_markdown(note):
    """Generate ADHD-optimized markdown for a note"""

    # Parse JSON fields
    concepts = parse_json_field(note['concepts'])
    secondary_themes = parse_json_field(note['secondary_themes'])
    tags = parse_json_field(note['tags'])
    sentiment_data = parse_json_field(note['sentiment_data'], {
        'adhd_markers': {},
        'key_emotions': [],
        'stress_indicators': False
    })

    # Extract ADHD markers
    adhd_markers = sentiment_data.get('adhd_markers', {})
    key_emotions = sentiment_data.get('key_emotions', [])
    stress_indicators = sentiment_data.get('stress_indicators', False)

    # Parse date
    created_at = datetime.fromisoformat(note['created_at'].replace('Z', '+00:00'))
    date_str = created_at.strftime('%Y-%m-%d')
    time_str = created_at.strftime('%H:%M')
    year = created_at.strftime('%Y')
    month = created_at.strftime('%m')
    day_of_week = created_at.strftime('%A')

    # Energy level emoji
    energy_emoji = {
        'high': '⚡',
        'medium': '🔋',
        'low': '🪫'
    }.get(note['energy_level'], '🔋')

    # Emotional tone emoji
    emotion_emoji = {
        'excited': '🚀',
        'calm': '😌',
        'anxious': '😰',
        'frustrated': '😤',
        'content': '😊',
        'overwhelmed': '🤯',
        'motivated': '💪',
        'focused': '🎯'
    }.get(note['emotional_tone'], '💭')

    # Sentiment emoji
    sentiment_emoji = {
        'positive': '✅',
        'negative': '⚠️',
        'neutral': '⚪',
        'mixed': '🔀'
    }.get(note['overall_sentiment'], '⚪')

    # ADHD marker badges
    adhd_badges = []
    if adhd_markers.get('overwhelm'):
        adhd_badges.append('🧠 OVERWHELM')
    if adhd_markers.get('hyperfocus'):
        adhd_badges.append('🎯 HYPERFOCUS')
    if adhd_markers.get('executive_dysfunction'):
        adhd_badges.append('⚠️ EXEC-DYS')
    if stress_indicators:
        adhd_badges.append('😰 STRESS')

    adhd_badge_str = ' | '.join(adhd_badges) if adhd_badges else '✨ BASELINE'

    # Extract action items
    action_items = extract_action_items(note['content'])

    # Generate TL;DR
    sentences = re.split(r'[.!?]\s+', note['content'])
    first_sentences = '. '.join(sentences[:2])
    tldr = first_sentences[:200] + '...' if len(first_sentences) > 200 else first_sentences

    # Reading time
    reading_time = max(1, round(note['word_count'] / 200))

    # Context box
    context_concepts = ', '.join(concepts[:2]) if concepts else 'general notes'
    context_box = f"""> **⚡ Quick Context**
> {tldr}
>
> **Why this matters:** Related to {context_concepts}
> **Reading time:** {reading_time} min
> **Brain state:** {note['energy_level']} energy, {note['emotional_tone']}"""

    # Build all tags
    all_tags = [
        note['primary_theme'],
        *secondary_themes,
        *tags,
        f"energy-{note['energy_level']}",
        f"mood-{note['emotional_tone']}",
        f"sentiment-{note['overall_sentiment']}"
    ]

    if adhd_markers.get('overwhelm'):
        all_tags.append('adhd/overwhelm')
    if adhd_markers.get('hyperfocus'):
        all_tags.append('adhd/hyperfocus')
    if stress_indicators:
        all_tags.append('state/stressed')

    # Remove duplicates and empty values
    all_tags = list(dict.fromkeys(filter(None, all_tags)))

    # Build frontmatter
    concepts_yaml = '\n'.join(f'  - {c}' for c in concepts)
    tags_yaml = '\n'.join(f'  - {t}' for t in all_tags)

    title_escaped = note['title'].replace('"', '\\"')
    sentiment_score = note['sentiment_score'] or 0.5

    frontmatter = f"""---
title: "{title_escaped}"
date: {date_str}
time: {time_str}
day: {day_of_week}
theme: {note['primary_theme']}
energy: {note['energy_level']}
mood: {note['emotional_tone']}
sentiment: {note['overall_sentiment']}
sentiment_score: {sentiment_score}
concepts:
{concepts_yaml}
tags:
{tags_yaml}
adhd_markers:
  overwhelm: {str(adhd_markers.get('overwhelm', False)).lower()}
  hyperfocus: {str(adhd_markers.get('hyperfocus', False)).lower()}
  executive_dysfunction: {str(adhd_markers.get('executive_dysfunction', False)).lower()}
stress: {str(stress_indicators).lower()}
action_items: {len(action_items)}
reading_time: {reading_time}
word_count: {note['word_count']}
source: Selene
automated: true
---"""

    # Build status header
    status_header = f"""# {emotion_emoji} {note['title']}

## 🎯 Status at a Glance

| Indicator | Status | Details |
|-----------|--------|----------|
| Energy | {energy_emoji} {note['energy_level'].upper()} | Brain capacity indicator |
| Mood | {emotion_emoji} {note['emotional_tone']} | Emotional state |
| Sentiment | {sentiment_emoji} {note['overall_sentiment']} | Overall tone ({round(sentiment_score * 100)}%) |
| ADHD | {adhd_badge_str} | Markers detected |
| Actions | 🎯 {len(action_items)} items | Tasks extracted |

---"""

    # Build metadata section
    concept_links = ' • '.join(f'[[Concepts/{c}]]' for c in concepts)
    theme_links = ' • '.join(f'[[Themes/{t}]]' for t in [note['primary_theme'], *secondary_themes])

    metadata_section = f"""
**🏷️ Theme**: {theme_links}
**💡 Concepts**: {concept_links}
**📅 Created**: {date_str} ({day_of_week}) at {time_str}
**⏱️ Reading Time**: {reading_time} min

---

{context_box}

---"""

    # Build action items section
    action_items_section = ''
    if action_items:
        action_items_list = '\n'.join(f'- [ ] {item}' for item in action_items)
        action_items_section = f"""
## ✅ Action Items Detected

{action_items_list}

> **Tip:** Copy these to your daily todo list or use Obsidian Tasks plugin

---"""

    # Content section
    content_section = f"""
## 📝 Full Content

{note['content']}

---"""

    # Insights section
    energy_interpretation = {
        'high': '⚡ Great time for complex tasks',
        'low': '🪫 Consider rest or easy tasks',
        'medium': '🔋 Moderate capacity available'
    }.get(note['energy_level'], '')

    overwhelm_text = '⚠️ Signs of overwhelm detected - consider breaking tasks down' if adhd_markers.get('overwhelm') else ''
    hyperfocus_text = '🎯 Hyperfocus detected - valuable insights likely!' if adhd_markers.get('hyperfocus') else ''
    stress_text = '😰 Stress indicators present - be gentle with yourself' if stress_indicators else ''

    emotional_insights = '\n  - '.join(filter(None, [overwhelm_text, hyperfocus_text, stress_text]))
    if emotional_insights:
        emotional_insights = f"  - {emotional_insights}"

    key_emotions_section = ''
    if key_emotions:
        key_emotions_list = '\n'.join(f'- {e}' for e in key_emotions)
        key_emotions_section = f"""
### Key Emotions
{key_emotions_list}"""

    insights_section = f"""
## 🧠 ADHD Insights

### Brain State Analysis

- **Energy Level**: {note['energy_level']} {energy_emoji}
  - {energy_interpretation}

- **Emotional Tone**: {note['emotional_tone']} {emotion_emoji}
{emotional_insights}

- **Sentiment**: {note['overall_sentiment']} ({round(sentiment_score * 100)}%)
{key_emotions_section}

### Context Clues

- **When was this?** {day_of_week}, {date_str} at {time_str}
- **What was I thinking about?** {', '.join(concepts[:3])}
- **Theme**: {note['primary_theme']}
- **How did I feel?** {note['emotional_tone']}, {note['overall_sentiment']}

> **Memory Trigger**: Look for related notes tagged with these concepts to restore full context

---"""

    # Metadata footer
    analysis_confidence = sentiment_data.get('analysis_confidence', 0.5)
    metadata_footer = f"""
## 📊 Processing Metadata

- **Processed**: {datetime.now().strftime('%Y-%m-%d')}
- **Source**: Selene Knowledge Management System
- **Concept Count**: {len(concepts)}
- **Word Count**: {note['word_count']}
- **Sentiment Confidence**: {round(analysis_confidence * 100)}%

## 🔗 Related Notes

*Obsidian will automatically show backlinks here based on shared concepts and tags*

---

*🤖 This note was automatically processed and optimized for ADHD by Selene*
"""

    # Combine all sections
    markdown = f"""{frontmatter}

{status_header}

{metadata_section}

{action_items_section}

{content_section}

{insights_section}

{metadata_footer}"""

    return {
        'markdown': markdown,
        'date_str': date_str,
        'year': year,
        'month': month,
        'concepts': concepts,
        'theme': note['primary_theme'],
        'energy': note['energy_level'],
        'title': note['title']
    }


def create_slug(title):
    """Create URL-friendly slug from title"""
    slug = title.lower()
    slug = re.sub(r'[^a-z0-9\s-]', '', slug)
    slug = re.sub(r'\s+', '-', slug)
    return slug[:50]


def write_note_to_vault(note, markdown_data, vault_path):
    """Write note to multiple locations in vault"""

    title_slug = create_slug(note['title'])
    filename = f"{markdown_data['date_str']}-{title_slug}.md"

    # Define all paths
    paths = {
        'timeline': f"{vault_path}/Selene/Timeline/{markdown_data['year']}/{markdown_data['month']}/{filename}",
        'concept': f"{vault_path}/Selene/By-Concept/{markdown_data['concepts'][0] if markdown_data['concepts'] else 'uncategorized'}/{filename}",
        'theme': f"{vault_path}/Selene/By-Theme/{markdown_data['theme']}/{filename}",
        'energy': f"{vault_path}/Selene/By-Energy/{markdown_data['energy']}/{filename}"
    }

    # Create directories and write files
    for path_type, file_path in paths.items():
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(markdown_data['markdown'])

    # Create concept hub pages
    concepts_dir = f"{vault_path}/Selene/Concepts"
    os.makedirs(concepts_dir, exist_ok=True)

    for concept in markdown_data['concepts']:
        concept_file = f"{concepts_dir}/{concept}.md"
        if not os.path.exists(concept_file):
            concept_content = f"""# {concept}

**Type**: Concept Index
**Created**: {datetime.now().strftime('%Y-%m-%d')}
**Auto-generated**: Yes

## 🎯 What is this?

This is a hub page for all notes related to **{concept}**. Obsidian will automatically show backlinks below.

## 📚 Related Notes

*Backlinks will appear here automatically*

## 🧠 ADHD Tips

- Use this page to see all notes about {concept} in one place
- Great for refreshing your memory before diving into a specific note
- Check the backlinks section to find related context

---

*Auto-generated by Selene - edit freely!*
"""
            with open(concept_file, 'w', encoding='utf-8') as f:
                f.write(concept_content)

    return filename


def mark_as_exported(db_path, note_id):
    """Update database to mark note as exported"""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    query = """
    UPDATE raw_notes
    SET exported_to_obsidian = 1,
        exported_at = datetime('now')
    WHERE id = ?
    """

    cursor.execute(query, (note_id,))
    conn.commit()
    conn.close()


def main():
    """Main export function"""
    import sys

    # Configuration
    db_path = '/selene/data/selene.db'
    vault_path = os.environ.get('OBSIDIAN_VAULT_PATH', '/selene/vault')

    # Check for noteId argument (for event-driven webhook calls)
    note_id = None
    if len(sys.argv) > 1:
        try:
            note_id = int(sys.argv[1])
        except ValueError:
            print(json.dumps({
                'success': False,
                'error': 'Invalid noteId provided',
                'message': 'noteId must be an integer'
            }), file=sys.stderr)
            sys.exit(1)

    # Get notes to export
    notes = get_notes_for_export(db_path, note_id)

    if not notes:
        message = f'Note {note_id} not found or not ready for export' if note_id else 'No notes ready for export'
        print(json.dumps({
            'success': True,
            'message': message,
            'exported_count': 0
        }))
        return

    # Export each note
    exported_count = 0
    for note in notes:
        try:
            # Generate markdown
            markdown_data = generate_adhd_markdown(note)

            # Write to vault
            filename = write_note_to_vault(note, markdown_data, vault_path)

            # Mark as exported
            mark_as_exported(db_path, note['id'])

            exported_count += 1

        except Exception as e:
            print(f"Error exporting note {note['id']}: {e}", file=sys.stderr)
            continue

    # Return success response
    mode = 'specific note' if note_id else f'{exported_count} note(s)'
    print(json.dumps({
        'success': True,
        'message': f'Successfully exported {mode}',
        'exported_count': exported_count,
        'note_id': note_id,
        'timestamp': datetime.now().isoformat()
    }))


if __name__ == '__main__':
    import sys
    main()
