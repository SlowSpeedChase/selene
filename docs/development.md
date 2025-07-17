# Development Guide

This document contains development commands, setup instructions, and project management tools for the Selene project.

## Package Management

```bash
# Install core dependencies
pip install -r requirements.txt

# Install development dependencies (includes testing, linting, formatting)
pip install -r requirements-dev.txt

# Install in development mode with optional dependencies
pip install -e ".[dev]"
```

## Testing

```bash
# Run all tests
pytest

# Run with coverage reporting
pytest --cov=selene

# Run specific test file
pytest tests/test_main.py

# Run with specific markers
pytest -m unit          # Unit tests only
pytest -m integration   # Integration tests only

# Test batch import system
python3 test_batch_import.py
```

## Code Quality & Formatting

```bash
# Format code (Black formatter, line length 88)
black selene tests

# Sort imports (isort, Black-compatible profile)
isort selene tests

# Lint code (flake8)
flake8 selene tests

# Type checking (mypy, strict mode enabled)
mypy selene

# Install and run pre-commit hooks
pre-commit install
pre-commit run --all-files
```

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
selene batch-import --source drafts --output ~/processed --no-archive  # Custom output, no archive

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

## Local AI Setup (Ollama)

```bash
# Install Ollama (one-time setup)
# macOS: brew install ollama
# Linux: curl -fsSL https://ollama.ai/install.sh | sh
# Windows: Download from https://ollama.ai

# Start Ollama service
ollama serve

# Pull recommended models for note processing
ollama pull llama3.2        # Default model (3B parameters, fast)
ollama pull mistral         # Alternative model (7B parameters)
ollama pull llama3.2:1b     # Lightweight option (1B parameters)

# Test local AI processing
selene process --content "Test note" --task summarize

# Environment Variables (SMS-32 Connection Manager)
export OLLAMA_HOST=http://localhost:11434    # Ollama server URL
export OLLAMA_PORT=11434                     # Ollama server port
export OLLAMA_TIMEOUT=120.0                 # Request timeout in seconds
export OLLAMA_MAX_CONNECTIONS=10            # Max concurrent connections
export OLLAMA_HEALTH_CHECK_INTERVAL=30     # Health check interval in seconds
export OLLAMA_MAX_RETRIES=3                # Max retry attempts
export OLLAMA_RETRY_DELAY=1.0              # Delay between retries
export OLLAMA_CONNECTION_TIMEOUT=10.0      # Connection timeout
export OLLAMA_READ_TIMEOUT=60.0            # Read timeout
export OLLAMA_VALIDATE_ON_INIT=true        # Validate connection on startup
```

## Production Deployment

```bash
# Initial production setup
./scripts/production_setup.sh

# Deploy updates
./scripts/deploy.sh

# Monitor system
./scripts/monitor.sh

# Backup data
./scripts/backup.sh
```

## Demo Scripts

```bash
# Interactive demo (full experience)
python3 demo_selene.py

# Batch import demo
python3 demo_batch_import.py

# Non-interactive demo (automation/testing)
python3 demo_selene.py --non-interactive
# or
SELENE_DEMO_NON_INTERACTIVE=1 python3 demo_selene.py

# Features demonstrated:
# ✅ SMS-27 batch import system (Drafts, text, Obsidian)
# ✅ SMS-33 prompt template system (11 built-in templates)
# ✅ Local AI processing (summarize, enhance, insights, questions) 
# ✅ Vector database with semantic search (local embeddings)
# ✅ Web interface overview and REST API examples
# ✅ System health checks and prerequisites validation
# ✅ Real-time content processing with performance metrics
```

## Configuration & Environment

- Uses `pyproject.toml` for modern Python packaging and tool configuration
- Environment variables loaded via python-dotenv (`.env` file)
- Logging configured to `logs/selene.log` with 30-day retention
- Virtual environment expected in `venv/` directory

## Code Quality Standards

- Black formatting with 88-character line length
- isort import sorting with Black profile compatibility
- flake8 linting with strict configuration
- mypy type checking with `disallow_untyped_defs` enabled
- Pre-commit hooks for automated quality checks
- pytest with strict markers and comprehensive test configuration

## Development Best Practices (Learned from SMS-38)

- **Test Early, Test Often**: Validate each component before building the next
- **Incremental Integration**: Build → Test → Demo → Continue
- **Progressive Demos**: Show working functionality at each development stage
- **Component Validation**: Ensure imports, basic functionality, and integration work
- **Never build everything then test everything**: Maintain working system throughout development

## Hardware Requirements

- **Minimum**: 8GB RAM, 4GB free disk space
- **Recommended**: 16GB+ RAM, SSD storage, Apple Silicon/modern GPU
- **Models**: 
  - `llama3.2:1b` - 1GB RAM, very fast, good quality (CURRENT)
  - `llama3.2` - 3GB RAM, fast, excellent quality
  - `mistral` - 7GB RAM, slower, highest quality
  - `nomic-embed-text` - 274MB, local embeddings (REQUIRED)