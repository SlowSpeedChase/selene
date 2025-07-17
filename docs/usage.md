# Usage Guide & Workflows

This document provides comprehensive usage examples and workflows for the Selene local-first AI processing system.

## Running the Application

```bash
# Main CLI entry point
selene start              # Start the system
selene version           # Show version
selene --help           # Show help

# LOCAL AI note processing (recommended - no API key needed)
selene process --content "Your note content" --task summarize
selene process --file note.txt --task enhance --output enhanced.txt
selene process --file research.md --task extract_insights --model mistral
selene process --content "Meeting notes..." --task questions --processor ollama

# LOCAL VECTOR DATABASE operations (NEW in SMS-15)
selene vector store --content "Important research notes" --metadata '{"type":"research"}'
selene vector store --file document.txt --id my-doc-1
selene vector search --query "machine learning insights" --results 10
selene vector retrieve --id my-doc-1
selene vector list --results 20
selene vector stats
selene vector delete --id old-doc-id

# BATCH IMPORT SYSTEM (SMS-27)
# Import and process notes from various sources
selene batch-import --source drafts --tag selene                    # Import from Drafts app
selene batch-import --source text --path ~/notes --tag selene       # Import from text files
selene batch-import --source obsidian --path ~/vault --tag inbox    # Import from Obsidian
selene batch-import --source drafts --dry-run                       # Preview without processing
selene batch-import --source text --path ~/notes --batch-size 10    # Custom batch size
selene batch-import --source drafts --tasks "enhance,extract_insights,questions"  # Custom tasks

# PROMPT TEMPLATE SYSTEM (SMS-33)
# Advanced AI processing with customizable prompt templates
selene process --content "text" --task summarize --template-id custom-template-uuid
selene process --file note.txt --template-variables '{"focus":"key insights","length":"brief"}'

# ADVANCED AI PROCESSING (NEW in SMS-19)
# Multi-model processing with automatic routing and fallback
selene process --content "text" --processor multi_model --task summarize
selene process --file note.txt --processor multi_model --compare-models
selene process --content "text" --processor multi_model --fallback --task enhance

# Chain processing for complex workflows (NEW in SMS-19 Phase 2)
selene chain --config chain_config.yaml --content "text"
selene chain --steps "summarize,extract_insights,questions" --file note.txt

# Cloud AI fallback (requires API key)
selene process --file note.txt --processor openai --api-key sk-...
selene process --content "text" --processor openai --model gpt-4

# Processor management
selene processor-info    # Show available processors and capabilities

# CHATBOT INTERFACE (SMS-36, SMS-37) 
# Conversational AI assistant for Obsidian vault management
selene chat --vault "path/to/vault"              # Start interactive chat
selene chat --vault "vault" --debug             # With debug logging
selene chat --vault "vault" --no-memory         # Without conversation memory

# VAULT ORGANIZATION SYSTEM (SMS-24)
# Advanced vault organization and management tools
# Available through chat interface - use natural language commands like:
# "create folder projects/research" 
# "move note1.md, note2.md to archived folder"
# "organize notes by tags" 
# "find duplicate notes"
# "analyze folder structure"

# Web Interface (NEW in SMS-18)
selene web                          # Start web interface at http://127.0.0.1:8000
selene web --host 0.0.0.0 --port 8080  # Custom host and port
selene web --reload                 # Development mode with auto-reload

# Alternative direct execution
python3 -m selene.main start
python3 -m selene.main process --help
python3 -m selene.main batch-import --help
python3 -m selene.main web    # Start web interface
```

## Batch Import Workflows

### Drafts App Integration

Perfect for your daily note processing workflow:

```bash
# Basic import from Drafts
selene batch-import --source drafts --tag selene

# Custom processing tasks
selene batch-import --source drafts --tag selene --tasks "enhance,extract_insights,questions"

# Preview before processing
selene batch-import --source drafts --tag selene --dry-run

# Process with specific model
selene batch-import --source drafts --tag selene --model llama3.2

# Custom output directory
selene batch-import --source drafts --tag selene --output ~/processed_notes
```

**Workflow:**
1. Tag notes in Drafts app with `#selene`
2. Run batch import command
3. Enhanced notes appear in `processed_notes_drafts/`
4. Original notes tagged with `#selene-processed`
5. Notes stored in vector database for semantic search

### Text Files Import

For processing notes from various text sources:

```bash
# Import from directory
selene batch-import --source text --path ~/notes --tag selene

# Process all text files (no tag filter)
selene batch-import --source text --path ~/notes --tag ""

# Custom file pattern and batch size
selene batch-import --source text --path ~/notes --batch-size 10

# Keep original files (no archive)
selene batch-import --source text --path ~/notes --no-archive
```

### Obsidian Vault Import

For processing notes from Obsidian vaults:

```bash
# Import from vault
selene batch-import --source obsidian --path ~/vault --tag inbox

# Process all notes in a folder
selene batch-import --source obsidian --path ~/vault/folder --tag ""

# Summarize research notes
selene batch-import --source obsidian --path ~/vault --tag research --tasks summarize
```

## Obsidian Vault Integration Workflow

```bash
# COMPLETE OBSIDIAN WORKFLOW (NEW - Tested & Production Ready)

# 1. AI-Powered Note Processing
# Transform raw notes into polished, structured content
python3 -m selene.main process --file "meeting-notes-raw.md" --task enhance
python3 -m selene.main process --file "research-draft.md" --task extract_insights
python3 -m selene.main process --file "brainstorm.md" --task questions

# 2. Vector Database Storage (Semantic Search)
# Store notes with metadata for intelligent retrieval
python3 -m selene.main vector store --file "note.md" --metadata '{"vault":"obsidian","type":"research"}'
python3 -m selene.main vector store --file "meeting.md" --metadata '{"type":"meeting","date":"2025-07-16"}'

# 3. Semantic Search Across All Notes
# Find related content using natural language queries
python3 -m selene.main vector search --query "team meeting API performance" --results 5
python3 -m selene.main vector search --query "machine learning transformers" --results 3
python3 -m selene.main vector search --query "project automation ideas" --results 10

# 4. Vector Database Management
python3 -m selene.main vector list --results 20     # List all stored notes
python3 -m selene.main vector stats                 # Database statistics
python3 -m selene.main vector retrieve --id doc-id  # Get specific document
python3 -m selene.main vector delete --id old-doc   # Remove outdated notes

# 5. Web Interface for Easy Management
python3 -m selene.main web --host 0.0.0.0 --port 8080
# Access at http://localhost:8080 for:
# - Content processing with AI templates
# - Vector search interface
# - Note management and organization
# - Real-time processing statistics

# PERFORMANCE: Local processing with llama3.2:1b + nomic-embed-text
# - Note processing: 7-12 seconds per task
# - Vector operations: <1 second (store/search)
# - Full privacy: All data stays on your machine
```

## Advanced Chat Features (SMS-38)

### Enhanced Conversational AI Usage

```bash
# Natural Language Understanding
You: "read my daily notes"           → Automatically finds daily-*.md files
You: "help me create a note"         → Starts guided note creation workflow
You: "find AI research"              → Smart search with contextual suggestions
You: "update that file"              → Asks for clarification with file suggestions

# Advanced Features
You: "features"     → Shows enhanced capabilities status
You: "stats"        → Session statistics and performance metrics
You: "patterns"     → User learning data and preferences
You: "flows"        → Available conversation workflows

# Multi-turn Workflows
You: "start note creation workflow"  → Guided note creation process
You: "research assistant mode"       → Research workflow with context
You: "vault maintenance routine"     → Automated vault health checks
```

### Enhanced Features:
- **Fuzzy Matching**: Find files with approximate names
- **Parameter Inference**: Automatically fill in missing information
- **Learning System**: Adapts to user patterns and preferences
- **Context Awareness**: Remembers conversation history and context
- **Intelligent Suggestions**: Time-based and usage-based recommendations
- **Error Recovery**: Helpful suggestions when commands fail

## Workflow Examples

### Daily Note Processing Workflow
```bash
# 1. Start with raw notes from Drafts
selene batch-import --source drafts --tag daily --tasks enhance

# 2. Extract insights from processed notes
selene batch-import --source drafts --tag insights --tasks extract_insights

# 3. Search for related content
selene vector search --query "daily productivity insights" --results 5

# 4. Chat with your notes
selene chat --vault processed_notes_drafts
```

### Research Workflow
```bash
# 1. Import research notes
selene batch-import --source obsidian --path ~/research --tag research

# 2. Use natural language commands in chat
selene chat --vault ~/research
You: "organize notes by topic"
You: "find duplicate research papers"
You: "analyze current research themes"

# 3. Generate questions for further research
selene batch-import --source obsidian --path ~/research --tasks questions
```

### Meeting Notes Processing
```bash
# 1. Process meeting notes
selene batch-import --source text --path ~/meetings --tag meeting --tasks "enhance,extract_insights"

# 2. Find action items
selene vector search --query "action items tasks TODO" --results 10

# 3. Generate follow-up questions
selene batch-import --source text --path ~/meetings --tasks questions
```

## Vault Organization Workflow

```bash
# 1. Start with health check
selene chat --vault "vault-path"
You: "check vault health"
You: "analyze vault structure"

# 2. Organize content
You: "organize notes by date dry run"
You: "organize notes by tags execute"
You: "find duplicate notes with suggestions"

# 3. Maintain structure
You: "auto tag notes dry run"
You: "cleanup vault structure"
You: "analyze vault structure recommendations"
```

## Performance Metrics

### Local Processing Performance
- **Note Processing**: 7-12 seconds per task (local AI)
- **Vector Operations**: <1 second (store/search)
- **Batch Import**: 5-10 notes per minute (concurrent processing)
- **Embedding Model**: nomic-embed-text:latest (274MB, local)
- **Processing Model**: llama3.2:1b (1.3GB, fast & quality)

### Test Results
- ✅ Meeting notes: Enhanced from 951 → 2,115 characters (structured)
- ✅ Research notes: Extracted 10 comprehensive insights (971 → 3,387 chars)
- ✅ Project ideas: Generated 7 thoughtful questions per idea (864 → 2,549 chars)
- ✅ Vector search: Perfect semantic matching for all query types
- ✅ Metadata organization: Notes properly categorized and searchable

## User Benefits

### Complete Local-First Processing
- **Privacy**: All data stays on your machine
- **Performance**: Optimized for local hardware
- **Cost**: No API fees or usage charges
- **Offline**: Works without internet connection
- **Control**: Full customization and model choice

### Enhanced Productivity
- **Batch Processing**: Process multiple notes efficiently
- **Semantic Search**: Find notes using natural language
- **AI Enhancement**: Transform rough notes into polished content
- **Automated Organization**: Smart categorization and tagging
- **Conversational Interface**: Natural language vault management
- **Web Interface**: Cross-platform access and management

## Production Deployment

### Quick Production Setup
```bash
# Initial setup
./scripts/production_setup.sh

# Deploy updates from development
./scripts/deploy.sh

# Monitor system health
./scripts/monitor.sh
```

### Automated Workflows
```bash
# Daily processing script
#!/bin/bash
selene batch-import --source drafts --tag daily --tasks enhance
selene batch-import --source text --path ~/inbox --tag process
selene vector search --query "daily insights" --results 5
```

See `docs/production-deployment.md` for complete deployment guide and `docs/batch-import-guide.md` for detailed batch import usage.