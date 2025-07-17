# Batch Import User Guide

This guide shows you how to use Selene's batch import system to process notes from Drafts app, text files, and Obsidian vaults.

## Quick Start

### Prerequisites

1. **Install Selene**: Follow the installation instructions in the main README
2. **Start Ollama**: Make sure Ollama is running with a model (recommended: `llama3.2:1b`)
3. **Prepare your notes**: Tag notes with `selene` or your preferred tag

### Basic Usage

```bash
# Import from Drafts app (notes tagged with 'selene')
selene batch-import --source drafts --tag selene

# Import from text files in a directory
selene batch-import --source text --path ~/notes --tag selene

# Import from Obsidian vault
selene batch-import --source obsidian --path ~/vault --tag inbox
```

## Command Options

### Required Options

- `--source`: Source type (`drafts`, `text`, or `obsidian`)

### Optional Options

- `--path`: Path to source directory (required for `text` and `obsidian`)
- `--tag`: Tag filter for notes to import (default: `selene`)
- `--tasks`: Processing tasks (default: `enhance,extract_insights`)
- `--batch-size`: Concurrent processing limit (default: `5`)
- `--output`: Output directory (default: `processed_notes_{source}`)
- `--archive/--no-archive`: Archive processed notes (default: `true`)
- `--model`: AI model to use (default: `llama3.2:1b`)
- `--dry-run`: Preview without processing

## Source-Specific Setup

### Drafts App

1. **Tag your notes**: Add `#selene` to notes you want to process
2. **Run import**: `selene batch-import --source drafts --tag selene`
3. **Check results**: Processed notes will be in `processed_notes_drafts/`
4. **Archive**: Original notes will be tagged with `selene-processed`

**Note**: Drafts database auto-detection works on macOS. If not found, you may need to specify the path manually.

### Text Files

1. **Organize files**: Put text files in a directory
2. **Tag content**: Add `#selene` hashtag to file contents
3. **Run import**: `selene batch-import --source text --path ~/notes --tag selene`
4. **Check results**: Processed notes will be in `processed_notes_text/`
5. **Archive**: Original files will be moved to `processed/` folder

### Obsidian Vault

1. **Tag notes**: Add `selene` tag to frontmatter or use `#selene` hashtag
2. **Run import**: `selene batch-import --source obsidian --path ~/vault --tag selene`
3. **Check results**: Processed notes will be in `processed_notes_obsidian/`
4. **Archive**: Original notes will be moved to `processed/` folder

## Processing Tasks

### Available Tasks

- `enhance`: Improve clarity and structure of notes
- `extract_insights`: Extract key insights and patterns
- `summarize`: Create concise summaries
- `questions`: Generate thought-provoking questions
- `classify`: Categorize and tag content

### Task Examples

```bash
# Single task
selene batch-import --source text --path ~/notes --tasks enhance

# Multiple tasks
selene batch-import --source text --path ~/notes --tasks "enhance,extract_insights,questions"

# Research workflow
selene batch-import --source obsidian --path ~/vault --tasks "summarize,extract_insights"
```

## Advanced Usage

### Dry Run Mode

Preview what would be processed without actually processing:

```bash
selene batch-import --source text --path ~/notes --dry-run
```

This shows:
- Number of notes found
- Note titles and content length
- Processing configuration

### Custom Output Directory

```bash
selene batch-import --source drafts --output ~/processed_notes/daily_batch
```

### Batch Size Optimization

```bash
# Faster processing (more concurrent)
selene batch-import --source text --path ~/notes --batch-size 10

# Slower processing (less memory usage)
selene batch-import --source text --path ~/notes --batch-size 2
```

### Different Models

```bash
# Use larger model for better quality
selene batch-import --source drafts --model llama3.2

# Use smaller model for speed
selene batch-import --source drafts --model llama3.2:1b
```

## Output Format

### Processed Notes

Each processed note includes:

```markdown
---
title: Original Note Title
source: drafts
original_date: 2025-07-17T10:30:00
processed_date: 2025-07-17T10:35:00
tags: ["selene", "productivity"]
processing_tasks: ["enhance", "extract_insights"]
---

# Enhanced Note Content

The enhanced version of your note with improved clarity and structure.

## Processing Results

### Extract Insights

Key insights extracted from the original note:
- Insight 1
- Insight 2
```

### Vector Database

All processed notes are automatically stored in the vector database for semantic search:

```bash
# Search processed notes
selene vector search --query "productivity insights"

# List all stored notes
selene vector list
```

## Troubleshooting

### Common Issues

1. **Drafts database not found**
   - Solution: Specify path manually or check Drafts app installation

2. **No notes found**
   - Check tag filter: `--tag your_tag`
   - Verify source path: `--path correct_path`
   - Use `--dry-run` to debug

3. **Processing errors**
   - Check Ollama is running: `ollama list`
   - Verify model is available: `ollama pull llama3.2:1b`
   - Check logs in `logs/selene.log`

4. **Memory issues**
   - Reduce batch size: `--batch-size 2`
   - Use smaller model: `--model llama3.2:1b`

### Performance Tips

1. **Optimal batch size**: 5-10 notes for most systems
2. **Model selection**: `llama3.2:1b` for speed, `llama3.2` for quality
3. **Concurrent processing**: Monitor system resources during processing
4. **Archive management**: Use `--no-archive` to keep original notes

## Production Workflows

### Daily Note Processing

Create a script for daily processing:

```bash
#!/bin/bash
# daily_import.sh

echo "🚀 Starting daily note import..."

# Import from Drafts
selene batch-import --source drafts --tag daily --tasks enhance

# Import from text files
selene batch-import --source text --path ~/inbox --tag process

# Import from Obsidian inbox
selene batch-import --source obsidian --path ~/vault --tag inbox --tasks "enhance,extract_insights"

echo "✅ Daily import completed!"
```

### Research Workflow

```bash
# Enhanced research processing
selene batch-import --source obsidian --path ~/research --tag research \
  --tasks "summarize,extract_insights,questions" \
  --batch-size 3 \
  --model llama3.2 \
  --output ~/processed_research
```

### Meeting Notes Processing

```bash
# Process meeting notes
selene batch-import --source text --path ~/meetings --tag meeting \
  --tasks "enhance,extract_insights" \
  --batch-size 5 \
  --output ~/processed_meetings
```

## Integration with Existing Workflows

### With Obsidian

1. Use batch import to process inbox notes
2. Enhanced notes go to processed folder
3. Use vector search to find related notes
4. Create links between processed and existing notes

### With Drafts App

1. Tag drafts with `#selene` during creation
2. Run batch import daily or weekly
3. Processed notes become your knowledge base
4. Original drafts archived automatically

### With Text Files

1. Save notes from any source as text files
2. Add `#selene` hashtag to content
3. Run batch import on the directory
4. Processed notes ready for knowledge management

## Next Steps

After batch importing your notes:

1. **Explore with vector search**: Find related content using semantic search
2. **Use chat interface**: Ask questions about your notes with `selene chat`
3. **Create workflows**: Set up automated processing with cron jobs
4. **Integrate with web interface**: Access via `selene web` for easy management

## Getting Help

- **Documentation**: See `docs/` directory for more guides
- **Demo**: Run `python3 demo_batch_import.py` for interactive demo
- **Issues**: Check `logs/selene.log` for detailed error information
- **Support**: Use `selene --help` or `selene batch-import --help` for command options