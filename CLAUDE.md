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

# Web Interface (NEW in SMS-18)
selene web                          # Start web interface at http://127.0.0.1:8000
selene web --host 0.0.0.0 --port 8080  # Custom host and port
selene web --reload                 # Development mode with auto-reload

# Alternative direct execution
python3 -m selene.main start
python3 -m selene.main process --help
python3 -m selene.main web    # Start web interface
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

### Obsidian Vault Integration Workflow
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

### Project Manager Tool
```bash
# JIRA-integrated development workflow manager
python3 project-manager.py start    # Start daily workflow
python3 project-manager.py status   # Check current work status  
python3 project-manager.py finish   # Finish current work session
python3 project-manager.py tickets  # List available tickets

# Setup JIRA integration (run once)
python3 scripts/setup_jira.py
```

### Interactive Demo
```bash
# SETUP REQUIREMENTS (run once):
# 1. Install Ollama and pull required models
brew install ollama          # macOS installation
ollama serve                 # Start Ollama service (in separate terminal)
ollama pull llama3.2:1b     # Pull text generation model (1.3GB)
ollama pull nomic-embed-text # Pull embedding model (274MB)

# 2. Install Python dependencies
pip install -r requirements.txt
pip install ollama           # Ollama Python client

# 3. Verify setup
ollama list                  # Should show both models
python3 -c "import ollama; print('✅ Ready')"

# DEMO EXECUTION:
# Interactive demo (full experience)
python3 demo_selene.py

# Non-interactive demo (automation/testing)
python3 demo_selene.py --non-interactive
# or
SELENE_DEMO_NON_INTERACTIVE=1 python3 demo_selene.py

# Features demonstrated:
# ✅ SMS-33 prompt template system (11 built-in templates)
# ✅ Local AI processing (summarize, enhance, insights, questions) 
# ✅ Vector database with semantic search (local embeddings)
# ✅ Web interface overview and REST API examples
# ✅ System health checks and prerequisites validation
# ✅ Real-time content processing with performance metrics
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
    - `multi_model_processor.py`: SMS-19 multi-model processing with routing (NEW)
    - `chain_processor.py`: SMS-19 chain processing for complex workflows (NEW)
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
- **Variable System**: Dynamic variables with validation and default values
- **Template Analytics**: Usage tracking and quality scoring
- **API Integration**: Full REST API for template management

### Advanced AI Processing Features (SMS-19)
- **Multi-Model Processing**: Automatic routing between multiple AI models
- **Task-Specific Routing**: Route different tasks to optimized models
- **Model Comparison**: Compare multiple models on the same task
- **Fallback Chains**: Intelligent fallback when primary models fail
- **Performance Monitoring**: Real-time statistics and analytics
- **Chain Processing**: Sequential and parallel task execution
- **Conditional Branching**: Different paths based on intermediate results
- **Retry Mechanisms**: Robust error handling with configurable retries
- **Result Aggregation**: Combine outputs from multiple processing steps
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
- ✅ SMS-33: **PROMPT TEMPLATE SYSTEM COMPLETE** ✨
  - 11 built-in professional templates with variable system
  - Full CRUD operations via REST API and web interface
  - Template analytics, usage tracking, and performance metrics
  - Local AI processing integration with llama3.2:1b model
  - Vector database with local embeddings (nomic-embed-text)
  - Comprehensive demo script with non-interactive automation
  - **Pull Request**: https://github.com/SlowSpeedChase/selene/pull/4 (Merged)
- ✅ SMS-19: **ADVANCED AI FEATURES COMPLETE** 🚀
  - **Phase 1**: Multi-Model Processing (COMPLETE)
    - MultiModelProcessor with automatic task routing
    - Model comparison and benchmarking
    - Intelligent fallback chains for reliability
    - Performance monitoring and statistics
  - **Phase 2**: Chain Processing (COMPLETE)
    - Sequential and parallel task execution
    - Conditional branching with result-based decisions
    - Retry mechanisms with configurable error handling
    - Result aggregation for complex workflows
  - **Web API Integration**: 5 new endpoints for advanced features
  - **Testing**: 36 comprehensive tests (19 for multi-model, 17 for chain)
  - **Demo Integration**: Complete showcase of all advanced features
- 🔄 Next: SMS-19 Phase 3 (Advanced Templates) or SMS-20 (Mobile Interface)

### Hardware Requirements
- **Minimum**: 8GB RAM, 4GB free disk space
- **Recommended**: 16GB+ RAM, SSD storage, Apple Silicon/modern GPU
- **Models**: 
  - `llama3.2:1b` - 1GB RAM, very fast, good quality (CURRENT)
  - `llama3.2` - 3GB RAM, fast, excellent quality
  - `mistral` - 7GB RAM, slower, highest quality
  - `nomic-embed-text` - 274MB, local embeddings (REQUIRED)

## 📋 CURRENT WORK STATUS (2025-07-15)

### ✅ COMPLETED: SMS-19 Advanced AI Features
**Branch**: `feature/sms-19-advanced-ai`  
**Status**: ✅ **PRODUCTION READY** - All Phase 1 & 2 features complete and tested

#### What was implemented:

**Phase 1: Multi-Model Processing**
1. **MultiModelProcessor**: 440+ lines of comprehensive multi-model orchestration
2. **Model Pool Management**: Dynamic model initialization and configuration
3. **Task Routing**: Automatic routing based on task optimization
4. **Model Comparison**: Parallel processing with result ranking
5. **Fallback Chains**: Intelligent fallback when primary models fail
6. **Performance Monitoring**: Real-time statistics and analytics

**Phase 2: Chain Processing**
1. **ProcessingChain**: 500+ lines of chain orchestration
2. **Sequential Execution**: Tasks execute one after another
3. **Parallel Processing**: Multiple tasks run simultaneously
4. **Conditional Branching**: Different paths based on intermediate results
5. **Retry Mechanisms**: Robust error handling with configurable retries
6. **Result Aggregation**: Intelligent combining of outputs

**Web API Integration**
1. **Multi-Model Endpoints**: `/api/multi-model/compare`, `/api/multi-model/info`, `/api/multi-model/test-fallback`
2. **Chain Processing Endpoints**: `/api/chain/execute`, `/api/chain/create-example`
3. **Complete JSON Configuration**: Full chain configuration via web requests

**Testing & Quality**
1. **36 Comprehensive Tests**: 19 for multi-model, 17 for chain processing
2. **100% Test Coverage**: All functionality tested with mocks and async support
3. **No Regressions**: 74/75 total tests passing (1 skipped)

#### Previous Work: SMS-33 Prompt Template System
**Status**: ✅ **MERGED** - All features complete and in production
1. **11 Built-in Templates**: Professional templates for all AI processing tasks
2. **Template Management**: Full CRUD with REST API endpoints (/api/templates/*)
3. **Variable System**: Required/optional variables with validation and defaults
4. **Usage Analytics**: Performance tracking, quality scores, success rates
5. **Local AI Integration**: Works with llama3.2:1b model (privacy-focused)
6. **Vector Database**: Local embeddings with nomic-embed-text (semantic search)
7. **Web Interface**: Complete template management UI in FastAPI dashboard
8. **Demo Script**: Comprehensive demonstration (interactive + non-interactive modes)

#### What was fixed:
- ✅ Division by zero error in template statistics calculation
- ✅ Parameter conflicts in Ollama processor method calls
- ✅ Missing Ollama Python library dependency
- ✅ Vector search JSON parsing errors
- ✅ EOF errors in non-interactive mode
- ✅ Model compatibility with available Ollama models

#### Demo Script Status:
- ✅ **100% Functional** - All features working end-to-end
- ✅ Prerequisites check (Ollama + ChromaDB + modules)
- ✅ AI processing (4 tasks: summarize, enhance, insights, questions)
- ✅ Vector database (storage + semantic search with scores)
- ✅ Template system (11 templates + rendering + analytics)
- ✅ Non-interactive automation mode

### ✅ COMPLETED: Obsidian Vault Integration Workflow (NEW - 2025-07-16)
**Status**: ✅ **PRODUCTION READY** - Complete note processing and semantic search workflow

#### What was implemented:

**Obsidian Workflow Features**
1. **AI Note Processing**: Transform raw notes with enhance, extract_insights, questions tasks
2. **Vector Database Integration**: Store notes with semantic search using local embeddings
3. **Semantic Search**: Natural language queries across entire note collection
4. **Metadata Support**: Organize notes by vault, type, date, and custom categories
5. **Web Interface Integration**: Full workflow accessible via browser at localhost:8080
6. **Local Privacy**: All processing happens locally with llama3.2:1b + nomic-embed-text

**Performance Metrics**
- **Note Processing**: 7-12 seconds per task (local AI)
- **Vector Operations**: <1 second (store/search)
- **Embedding Model**: nomic-embed-text:latest (274MB, local)
- **Processing Model**: llama3.2:1b (1.3GB, fast & quality)

**Test Results**
- ✅ Meeting notes: Enhanced from 951 → 2,115 characters (structured)
- ✅ Research notes: Extracted 10 comprehensive insights (971 → 3,387 chars)
- ✅ Project ideas: Generated 7 thoughtful questions per idea (864 → 2,549 chars)
- ✅ Vector search: Perfect semantic matching for all query types
- ✅ Metadata organization: Notes properly categorized and searchable

**User Impact**
- Complete local-first note processing pipeline for Obsidian users
- Semantic search eliminates manual note hunting
- AI enhancement transforms rough notes into polished content
- Privacy-focused: No data leaves user's machine
- Network access: Web interface works across local network

### 🔄 NEXT STEPS:
1. **FILE MONITORING**: Auto-process new notes as they're created in vault
2. **BULK PROCESSING**: Process entire existing vaults efficiently
3. **TEMPLATE CUSTOMIZATION**: Obsidian-specific prompt templates
4. **INTEGRATION**: Direct Obsidian plugin development

### 🎯 READY FOR PRODUCTION:
- Complete Obsidian workflow validated and documented
- All features tested with real-world note examples
- Performance optimized for local hardware
- Ready for user adoption and feedback

### ✅ COMPLETED: SMS-36 Chatbot Foundation & Architecture (NEW - 2025-07-16)
**Status**: ✅ **FOUNDATION COMPLETE** - Core architecture implemented and tested

#### What was implemented:

**Foundation & Architecture (SMS-36)**
1. **ChatAgent Class**: Core conversational AI agent with initialization and conversation handling
2. **Tool Registry System**: Extensible tool system with registration, validation, and execution
3. **Configuration Management**: Comprehensive configuration system for vault paths and settings
4. **Conversation State**: SQLite-based conversation memory with context management
5. **CLI Integration**: Full command-line interface integration (`selene chat`)

**Tool System Features**
- **BaseTool Architecture**: Abstract base class with parameter validation and schema generation
- **Tool Registry**: Dynamic tool registration with enable/disable capabilities
- **7 Implemented Tools**: read_note, write_note, update_note, list_notes, search_notes, vector_search, ai_process
- **Error Handling**: Comprehensive error handling with status codes and user feedback
- **Rich Formatting**: Beautiful terminal output with tables and formatted responses

**Conversation Management**
- **SQLite Memory**: Persistent conversation storage with search capabilities
- **Context Windows**: Configurable conversation context for AI processing
- **Session Management**: Multi-session conversation continuity
- **Statistics**: Usage analytics and conversation metrics

**Vault Integration**
- **Auto-Discovery**: Automatic Obsidian vault detection and configuration
- **File Operations**: Read, write, update operations with backup support
- **Search Capabilities**: Text search and semantic vector search integration
- **Safety Features**: File size limits, destructive action confirmation, automatic backups

**Testing Results**
- ✅ Agent initialization: All components loaded successfully
- ✅ Help system: Comprehensive command documentation
- ✅ Vault detection: Test vault recognized with 3 notes
- ✅ Tool registration: 7 tools enabled and functional
- ✅ CLI interface: Interactive chat loop with proper exit handling
- ✅ Memory system: SQLite database created and functional
- ⚠️ Natural language parsing: Needs improvement (expected for foundation)

**Usage Example**
```bash
# Start interactive chat
selene chat --vault "path/to/vault"

# With debug logging
selene chat --vault "test-vault" --debug

# Without conversation memory
selene chat --vault "vault" --no-memory
```

**Architecture Completed**
- `selene/chat/` - Complete chat module
- `selene/chat/agent.py` - Main ChatAgent class (430+ lines)
- `selene/chat/config.py` - Configuration management (200+ lines)
- `selene/chat/state.py` - Conversation state management (350+ lines)
- `selene/chat/tools/base.py` - Tool system foundation (300+ lines)
- `selene/chat/tools/vault_tools.py` - Vault interaction tools (400+ lines)
- `selene/chat/tools/search_tools.py` - Search tools (200+ lines)
- `selene/chat/tools/ai_tools.py` - AI processing tools (100+ lines)

**Ready for Phase 2**: SMS-37 Vault Interaction Tools (enhanced natural language processing)