# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 🏠 LOCAL-FIRST AI SYSTEM

**PROJECT MISSION**: Build a completely local Second Brain Processing System that prioritizes:
- **Privacy**: All AI processing runs locally - data never leaves your machine
- **Performance**: Optimized for local hardware capabilities  
- **Cost**: No usage fees or API charges
- **Offline**: Works without internet connection
- **Control**: Full customization and model choice

## Development Commands

### Package Management
```bash
# Install core dependencies
pip install -r requirements.txt

# Install development dependencies (includes testing, linting, formatting)
pip install -r requirements-dev.txt

# Install in development mode with optional dependencies
pip install -e ".[dev]"
```

### Testing
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
```

### Code Quality & Formatting
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

### Running the Application
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

# PROMPT TEMPLATE SYSTEM (NEW in SMS-33)
# Advanced AI processing with customizable prompt templates
selene process --content "text" --task summarize --template-id custom-template-uuid
selene process --file note.txt --template-variables '{"focus":"key insights","length":"brief"}'

# Cloud AI fallback (requires API key)
selene process --file note.txt --processor openai --api-key sk-...
selene process --content "text" --processor openai --model gpt-4

# Processor management
selene processor-info    # Show available processors and capabilities

# Web Interface (NEW in SMS-18)
selene web                          # Start web interface at http://127.0.0.1:8000
selene web --host 0.0.0.0 --port 8080  # Custom host and port
selene web --reload                 # Development mode with auto-reload

# Alternative direct execution
python -m selene.main start
python -m selene.main process --help
```

### Local AI Setup (Ollama)
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
```

### Project Manager Tool
```bash
# JIRA-integrated development workflow manager
python project-manager.py start    # Start daily workflow
python project-manager.py status   # Check current work status  
python project-manager.py finish   # Finish current work session
python project-manager.py tickets  # List available tickets

# Setup JIRA integration (run once)
python scripts/setup_jira.py
```

### Interactive Demo
```bash
# Comprehensive demonstration of all Selene features
python3 demo_selene.py

# Features demonstrated:
# - SMS-33 prompt template system with 11 built-in templates
# - Local AI processing with multiple tasks (summarize, enhance, analyze)
# - Vector database operations with semantic search
# - Web interface overview and API examples
# - System health checks and prerequisites validation
# - Interactive content selection and real-time processing
```

## Architecture Overview

### Core Structure
- **selene/**: Main Python package containing the CLI application
  - `main.py`: Entry point with Typer CLI, note processing commands
  - `processors/`: Note processing pipeline with AI integration
    - `base.py`: Abstract base processor and result classes with template support
    - `llm_processor.py`: OpenAI LLM-powered note processor
    - `ollama_processor.py`: Local Ollama processor with template integration
    - `vector_processor.py`: ChromaDB vector database processor
  - `prompts/`: SMS-33 Prompt template system (NEW)
    - `models.py`: Template data models with variables and validation
    - `manager.py`: Template CRUD operations and analytics
    - `builtin_templates.py`: 11 professional built-in templates
  - `vector/`: Local vector database integration
    - `chroma_store.py`: ChromaDB storage and retrieval
    - `embedding_service.py`: Text embedding generation
  - `web/`: FastAPI web interface (SMS-18)
    - `app.py`: REST API with template management endpoints
    - `models.py`: Pydantic models for web requests/responses
  - `monitoring/`: File system monitoring and processing
  - `queue/`: Processing queue and background task management
  - `jira/`: JIRA integration for project management
  - `__init__.py`: Package initialization with version info
- **tests/**: Test suite with pytest configuration
  - `test_processors.py`: Comprehensive processor tests with async support
  - `test_vector.py`: Vector database and embedding tests
- **scripts/**: Utility scripts for JIRA integration and project setup
- **project-manager.py**: Standalone JIRA-integrated workflow manager
- **demo_selene.py**: Interactive demonstration of all features (NEW)

### Key Dependencies & Technologies
- **CLI Framework**: Typer for command-line interface
- **Web Framework**: FastAPI for REST API and web interface
- **UI/Output**: Rich library for beautiful terminal output and formatting
- **Web UI**: Modern HTML/CSS/JS dashboard with real-time monitoring
- **Logging**: Loguru for structured logging with rotation
- **Core Integrations**: 
  - OpenAI & Ollama for LLM-powered note processing
  - ChromaDB for vector database and semantic search
  - Watchdog for file system monitoring
  - Pydantic for data validation
  - Uvicorn for ASGI web server

### Project Manager Integration
The project includes a comprehensive JIRA-integrated development workflow manager (`project-manager.py`) that handles:
- Sprint management and ticket selection from JIRA
- Automatic git branch creation and management  
- Time tracking with work session management
- JIRA ticket status transitions and work logging
- Development workflow automation with git operations

Configuration files:
- `.jira-config.yaml`: JIRA connection and project settings
- `.work-session.json`: Current work session state tracking

### Configuration & Environment
- Uses `pyproject.toml` for modern Python packaging and tool configuration
- Environment variables loaded via python-dotenv (`.env` file)
- Logging configured to `logs/selene.log` with 30-day retention
- Virtual environment expected in `venv/` directory

### Code Quality Standards
- Black formatting with 88-character line length
- isort import sorting with Black profile compatibility
- flake8 linting with strict configuration
- mypy type checking with `disallow_untyped_defs` enabled
- Pre-commit hooks for automated quality checks
- pytest with strict markers and comprehensive test configuration

## Key Development Notes

- The codebase is designed as a "Second Brain Processing System" for AI-powered note processing
- **SMS-14 Note Processing Pipeline is now implemented** with full LLM integration
- Core features include: content summarization, enhancement, insight extraction, question generation, and classification
- Strong emphasis on code quality with comprehensive tooling setup
- Modern Python practices: type hints, async support, proper packaging
- JIRA integration provides robust project management capabilities for development workflow

### Note Processing Features (SMS-14)
- **LLM Processor**: OpenAI GPT integration with configurable models
- **Processing Tasks**: 
  - `summarize`: Create concise summaries of content
  - `enhance`: Improve clarity and structure of notes
  - `extract_insights`: Extract key insights and patterns
  - `questions`: Generate thought-provoking questions
  - `classify`: Categorize and tag content
- **File & Content Support**: Process text directly or from files
- **Async Architecture**: Full async support for efficient processing
- **Rich Output**: Beautiful terminal formatting with metadata tables
- **Environment Configuration**: API key via environment or CLI parameter

### Prompt Template System Features (SMS-33)
- **Built-in Templates**: 11 professional templates for all processing tasks
- **Custom Templates**: Create and manage custom prompt templates with variables
- **Template Variables**: Support for required/optional variables with validation
- **Category Organization**: Templates organized by category (analysis, enhancement, etc.)
- **Usage Analytics**: Track template performance, quality scores, and success rates
- **Model Optimizations**: Per-model parameter overrides and configurations
- **Web Management**: Full CRUD operations via REST API and web interface
- **Template Rendering**: Variable substitution with fallback mechanisms
- **Search & Filtering**: Find templates by name, tags, category, or content
- **Version Tracking**: Template versioning with author and timestamp metadata

### Web Interface Features (SMS-18)
- **Modern Dashboard**: Real-time system monitoring and statistics
- **Content Processing**: Web-based AI content processing interface
- **Vector Search**: Interactive search interface for knowledge base
- **File Monitoring**: Web control for file monitoring system
- **Configuration Management**: Add/remove watched directories via web UI
- **Template Management**: Full prompt template CRUD operations (NEW)
- **REST API**: Comprehensive API endpoints for all functionality
- **Responsive Design**: Works on desktop and mobile devices
- **Real-time Updates**: Live status monitoring and progress tracking

### Development Status
- ✅ SMS-13: Project Setup (Foundation complete)
- ✅ SMS-14: LOCAL AI Note Processing Pipeline (Ollama + OpenAI fallback complete)
- ✅ SMS-15: LOCAL Vector Database (ChromaDB with embeddings complete - 20/20 tests PASS)
- ✅ SMS-16: JIRA Integration (Production ready)
- ✅ SMS-17: File Monitoring System (Architecture validated)
- ✅ SMS-18: Web UI (FastAPI + Modern Dashboard complete)
- ✅ SMS-33: Prompt Template System (Advanced AI prompt management complete)
- 🔄 Next: SMS-19 (Advanced AI Features) or SMS-20 (Mobile Interface)

### Hardware Requirements
- **Minimum**: 8GB RAM, 4GB free disk space
- **Recommended**: 16GB+ RAM, SSD storage, Apple Silicon/modern GPU
- **Models**: 
  - `llama3.2:1b` - 1GB RAM, very fast, good quality
  - `llama3.2` - 3GB RAM, fast, excellent quality (default)
  - `mistral` - 7GB RAM, slower, highest quality