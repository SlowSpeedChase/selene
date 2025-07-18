# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 🏠 LOCAL-FIRST AI SYSTEM

**PROJECT MISSION**: Build a completely local Second Brain Processing System that prioritizes:
- **Privacy**: All AI processing runs locally - data never leaves your machine
- **Performance**: Optimized for local hardware capabilities  
- **Cost**: No usage fees or API charges
- **Offline**: Works without internet connection
- **Control**: Full customization and model choice

## Essential Commands

### Package Management
```bash
# Install core dependencies
pip install -r requirements.txt

# Install development dependencies
pip install -r requirements-dev.txt

# Install in development mode
pip install -e ".[dev]"
```

### Testing & Code Quality
```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=selene

# Format code
black selene tests

# Sort imports
isort selene tests

# Lint code
flake8 selene tests

# Type checking
mypy selene

# Pre-commit hooks
pre-commit install
pre-commit run --all-files
```

### Running the Application
```bash
# Main CLI commands
selene start
selene version
selene --help

# LOCAL AI processing (recommended)
selene process --content "Your note content" --task summarize
selene process --file note.txt --task enhance --output enhanced.txt

# Vector database operations
selene vector store --content "Important notes" --metadata '{"type":"research"}'
selene vector search --query "machine learning insights" --results 10

# Chatbot interface
selene chat --vault "path/to/vault"

# Batch import system
selene batch-import --source drafts --tag selene

# Web interface
selene web                          # Start at http://127.0.0.1:8000 (localhost only)
selene web --host 0.0.0.0 --port 8000  # Production (network accessible)
selene web --host 0.0.0.0 --port 8080  # Development (network accessible)

# Web server management script
./scripts/web-servers.sh start-prod   # Start production server (port 8000)
./scripts/web-servers.sh start-dev    # Start development server (port 8080)
./scripts/web-servers.sh start-both   # Start both servers
./scripts/web-servers.sh stop-all     # Stop all servers
./scripts/web-servers.sh status       # Show running servers
./scripts/web-servers.sh urls         # Show access URLs

# Alternative execution
python3 -m selene.main start
python3 -m selene.main web
```

### Local AI Setup (Ollama)
```bash
# Install Ollama (one-time setup)
# macOS: brew install ollama
# Linux: curl -fsSL https://ollama.ai/install.sh | sh

# Start Ollama service
ollama serve

# Pull recommended models
ollama pull llama3.2:1b     # Lightweight (1B parameters)
ollama pull nomic-embed-text # Embeddings (274MB)

# Test processing
selene process --content "Test note" --task summarize

# Environment variables
export OLLAMA_HOST=http://localhost:11434
export OLLAMA_PORT=11434
export OLLAMA_TIMEOUT=120.0
```

## Project Structure

```
selene/                    # Main Python package
├── main.py               # CLI entry point
├── processors/           # AI processing pipeline
├── vector/              # Vector database (ChromaDB)
├── web/                 # FastAPI web interface
├── chat/                # Conversational AI system
├── batch/               # Batch import system
├── analytics/           # Analytics and monitoring
└── connection/          # Connection management

tests/                   # Test suite
scripts/                 # Deployment scripts
project-manager.py       # JIRA workflow manager
demo_selene.py          # Interactive demo
```

## Key Features

- **Local AI Processing**: Ollama + OpenAI fallback
- **Vector Database**: ChromaDB with semantic search
- **Web Interface**: Modern dashboard with real-time monitoring
- **Chatbot**: Conversational AI for vault management
- **Batch Import**: Import from Drafts, text files, Obsidian
- **Analytics**: Advanced system monitoring and insights

## Hardware Requirements

- **Minimum**: 8GB RAM, 4GB free disk space
- **Recommended**: 16GB+ RAM, SSD storage
- **Models**: 
  - `llama3.2:1b` - 1GB RAM, fast, good quality (recommended)
  - `nomic-embed-text` - 274MB, local embeddings (required)

## Configuration

- Uses `pyproject.toml` for packaging and tool configuration
- Environment variables via `.env` file
- Logging to `logs/selene.log` with 30-day retention
- Virtual environment in `venv/` directory