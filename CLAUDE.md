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

# CHATBOT INTERFACE (SMS-36, SMS-37) 
# Conversational AI assistant for Obsidian vault management
selene chat --vault "path/to/vault"              # Start interactive chat
selene chat --vault "vault" --debug             # With debug logging
selene chat --vault "vault" --no-memory         # Without conversation memory

# BATCH IMPORT SYSTEM (SMS-27)
# Import and process notes from various sources
selene batch-import --source drafts --tag selene                    # Import from Drafts app
selene batch-import --source text --path ~/notes --tag selene       # Import from text files
selene batch-import --source obsidian --path ~/vault --tag inbox    # Import from Obsidian
selene batch-import --source drafts --dry-run                       # Preview without processing
selene batch-import --source text --path ~/notes --batch-size 10    # Custom batch size
selene batch-import --source drafts --tasks "enhance,extract_insights,questions"  # Custom tasks
selene batch-import --source drafts --output ~/processed --no-archive  # Custom output, no archive

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
# ✅ SMS-27 batch import system (Drafts, text, Obsidian)
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
  - `batch/`: SMS-27 Batch import system (NEW)
    - `importer.py`: Main BatchImporter class with progress tracking
    - `sources.py`: Source implementations (Drafts, text files, Obsidian)
    - `processors.py`: Batch processing utilities and concurrent execution
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
  - `chat/`: SMS-36/37 Conversational AI chatbot system (NEW)
    - `agent.py`: Main ChatAgent with conversation handling
    - `config.py`: Configuration management for vault paths
    - `state.py`: SQLite conversation memory and context management
    - `tools/`: Extensible tool system for vault operations
    - `nlp/`: Enhanced natural language processing pipeline (NEW)
  - `connection/`: SMS-32 Connection management system (NEW)
    - `ollama_manager.py`: Centralized Ollama connection manager
    - Configuration, health monitoring, and connection pooling
  - `notes/`: SMS-23 Note formatting system (NEW)
    - `formatter.py`: Comprehensive note formatting with 15 templates
    - `metadata.py`: Frontmatter and metadata management
    - `structure.py`: Content organization and structuring
  - `__init__.py`: Package initialization with version info
- **tests/**: Test suite with pytest configuration
  - `test_processors.py`: Comprehensive processor tests with async support
  - `test_vector.py`: Vector database and embedding tests
  - `test_notes.py`: Note formatting system tests with 23 comprehensive cases
  - `test_batch_import.py`: Batch import system tests with 4/4 passing
- **scripts/**: Production deployment and management
  - `production_setup.sh`: Automated production environment setup
  - `deploy.sh`: Automated deployment with rollback capability
  - `monitor.sh`: Comprehensive system monitoring and health checks
- **project-manager.py**: Standalone JIRA-integrated workflow manager
- **demo_selene.py**: Interactive demonstration of all features (NEW)
- **demo_batch_import.py**: Batch import system demonstration (NEW)
- **test_batch_import.py**: Batch import comprehensive tests (NEW)

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
- **SMS-27 Batch Import System is now implemented** with full Drafts app integration
- **Production deployment system is complete** with automated setup and monitoring
- Core features include: batch import, content summarization, enhancement, insight extraction, question generation, and classification
- Strong emphasis on code quality with comprehensive tooling setup
- Modern Python practices: type hints, async support, proper packaging
- JIRA integration provides robust project management capabilities for development workflow

### 🧪 Development Best Practices (Learned from SMS-38)
- **Test Early, Test Often**: Validate each component before building the next
- **Incremental Integration**: Build → Test → Demo → Continue
- **Progressive Demos**: Show working functionality at each development stage
- **Component Validation**: Ensure imports, basic functionality, and integration work
- **Never build everything then test everything**: Maintain working system throughout development

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
- ✅ SMS-36: **CHATBOT FOUNDATION COMPLETE** 🤖
  - Core ChatAgent architecture with tool system
  - SQLite conversation memory and context management
  - 7 vault interaction tools with error handling
  - CLI integration with `selene chat` command
- ✅ SMS-37: **ENHANCED NLP PROCESSING COMPLETE** 🧠
  - Advanced natural language processing pipeline
  - Intent classification and parameter extraction
  - Entity recognition and sentiment analysis
  - Conversation context with turn-based tracking
- ✅ SMS-32: **OLLAMA CONNECTION MANAGER COMPLETE** 🔗
  - Centralized connection management for Ollama services
  - Connection pooling with health monitoring and automatic reconnection
  - Environment variable configuration (OLLAMA_HOST, OLLAMA_PORT, etc.)
  - Resource cleanup and connection lifecycle management
- ✅ SMS-38: **ADVANCED CHAT FEATURES COMPLETE** 🧠
  - Enhanced natural language processing with fuzzy matching and parameter inference
  - Context-aware response generation with personalization and learning
  - Smart tool selection with performance optimization and validation
  - Multi-turn conversation flows with guided workflows and state management
  - Advanced conversation features: suggestions, clarifications, pattern learning
  - Comprehensive testing suite with 50+ test cases covering all features
  - CLI and web interface integration with backward compatibility
  - **Production Ready**: Complete intelligent conversational AI system
- ✅ SMS-23: **NOTE FORMATTER COMPLETE** 📝
  - Comprehensive note formatting system with 15 professional templates
  - Frontmatter and metadata management for Obsidian compatibility
  - Content organization and structuring with automatic categorization
  - Integration with AI processing pipeline for enhanced note creation
  - 23 comprehensive tests covering all formatting functionality
  - Template system for meeting notes, research, journal, project planning, etc.
  - Smart content organization with tagging and metadata support
  - **Production Ready**: Complete note formatting and organization system
- ✅ SMS-20: **MOBILE INTERFACE COMPLETE** 📱
  - **Progressive Web App (PWA)**: Complete manifest.json with app metadata and shortcuts
  - **Service Worker**: Comprehensive caching, offline functionality, and background sync
  - **Mobile-Optimized UI**: Responsive CSS with breakpoints, touch-friendly interface
  - **Advanced Mobile Features**: Voice input, swipe gestures, pull-to-refresh, offline queue
  - **Installation Support**: PWA installation prompts and app shortcuts
  - **Cross-Platform**: Works on iOS, Android, and desktop browsers
  - **Accessibility**: Focus management, reduced motion, high contrast support
  - **Performance**: Resource preloading, caching, and mobile-specific optimizations
  - **Production Ready**: Complete mobile-first AI processing interface
- 🔄 Next: SMS-21 (Plugin System) or SMS-22 (Advanced Analytics)

### Hardware Requirements
- **Minimum**: 8GB RAM, 4GB free disk space
- **Recommended**: 16GB+ RAM, SSD storage, Apple Silicon/modern GPU
- **Models**: 
  - `llama3.2:1b` - 1GB RAM, very fast, good quality (CURRENT)
  - `llama3.2` - 3GB RAM, fast, excellent quality
  - `mistral` - 7GB RAM, slower, highest quality
  - `nomic-embed-text` - 274MB, local embeddings (REQUIRED)

## 📋 CURRENT WORK STATUS (2025-07-17)

### ✅ COMPLETED: SMS-20 Mobile Interface
**Branch**: `feature/sms-27-drafts-importer` (current working branch)  
**Status**: ✅ **ALREADY FULLY IMPLEMENTED** - Comprehensive mobile PWA interface discovered and documented

#### SMS-20 Mobile Interface - Complete Feature Set:
**Progressive Web App (PWA) Foundation**
- ✅ Complete manifest.json with app metadata, icons, and shortcuts
- ✅ Service worker with comprehensive caching and offline functionality
- ✅ Background sync for offline processing queue
- ✅ Push notification infrastructure ready
- ✅ Installation prompts and app shortcuts

**Mobile-Optimized User Interface**
- ✅ Responsive CSS with breakpoints for tablets and phones
- ✅ Touch-friendly interface with 44px minimum touch targets
- ✅ Mobile navigation with hamburger menu for small screens
- ✅ Swipe gestures for intuitive tab navigation
- ✅ Pull-to-refresh functionality for content updates

**Advanced Mobile Features**
- ✅ Voice input with speech recognition for content entry
- ✅ Offline queue management for processing requests
- ✅ Connection status indicator for network awareness
- ✅ Mobile-specific form optimizations and keyboard handling
- ✅ Accessibility features (focus management, reduced motion, high contrast)

**Performance & Cross-Platform Support**
- ✅ Resource preloading and intelligent caching strategies
- ✅ Viewport optimization to prevent iOS zoom
- ✅ WebKit-specific touch optimizations
- ✅ Dark mode and high contrast support
- ✅ Cross-platform compatibility (iOS, Android, desktop browsers)

**Mobile AI Processing Workflow**
- ✅ Touch-optimized forms with proper input sizing (16px to prevent zoom)
- ✅ Voice input integration for hands-free content entry
- ✅ Responsive grid layouts that stack appropriately on mobile
- ✅ Mobile-first chat interface with touch-friendly interactions
- ✅ Optimized vector search with mobile-friendly result displays

### ✅ COMPLETED: SMS-38 Advanced Chat Features
**Branch**: `feature/sms-32` (ready for merge to main)  
**Status**: ✅ **IMPLEMENTATION COMPLETE** - All advanced chat features implemented and tested

#### What was implemented:

**1. Enhanced Natural Language Processing**
1. **EnhancedLanguageProcessor**: 500+ lines with fuzzy matching and smart parameter inference
2. **Alternative Interpretations**: Generate multiple possible interpretations for ambiguous requests
3. **Parameter Inference**: Automatically infer missing parameters from context and patterns
4. **Fuzzy File Matching**: Find files with approximate names and smart suggestions
5. **User Pattern Learning**: Learn from user interactions for better personalization

**2. Context-Aware Response Generation**
1. **ContextAwareResponseGenerator**: 650+ lines of intelligent response generation
2. **Personalized Responses**: Adapt responses based on user patterns and preferences
3. **Contextual Suggestions**: Time-based and usage-based smart suggestions
4. **Response Types**: Success, error, clarification, and informational responses
5. **Follow-up Actions**: Intelligent next-step recommendations

**3. Smart Tool Selection & Parameter Inference**
1. **SmartToolSelector**: 700+ lines of intelligent tool routing and optimization
2. **Performance-Based Selection**: Route tools based on success rates and execution times
3. **Parameter Validation**: Advanced validation with intelligent error messages
4. **Tool Performance Tracking**: Learn from tool execution patterns and optimize
5. **Capability Matching**: Match user intents to optimal tool configurations

**4. Conversation Flow Management**
1. **ConversationFlowManager**: 800+ lines of multi-step workflow orchestration
2. **Built-in Workflows**: Note creation and research assistant templates
3. **State Management**: Persistent conversation state with timeout handling
4. **Dynamic Branching**: Conditional flow progression based on user input
5. **Flow Analytics**: Progress tracking and completion statistics

**5. Enhanced Chat Agent Integration**
1. **EnhancedChatAgent**: 900+ lines integrating all advanced features
2. **Seamless Integration**: CLI and web interface support with backward compatibility
3. **Rich Status Reporting**: Feature introspection and session statistics
4. **Advanced Commands**: Stats, patterns, flows, and feature management
5. **User Learning**: Pattern recognition and preference adaptation

**Testing & Quality**
1. **Comprehensive Test Suite**: 1000+ lines with 50+ test cases covering all features
2. **Integration Testing**: End-to-end scenarios and workflow validation
3. **Performance Testing**: Response times and resource usage validation
4. **Error Handling**: Robust error recovery and fallback mechanisms

#### Key Features Delivered:

**Enhanced Conversational AI**
- **Natural Language Understanding**: Fuzzy matching, parameter inference, context awareness
- **Intelligent Responses**: Personalized, context-aware responses with smart suggestions
- **Learning Capabilities**: User pattern recognition and preference adaptation
- **Multi-turn Workflows**: Guided processes for complex tasks (note creation, research)
- **Advanced Error Handling**: Intelligent error recovery with helpful suggestions

**Production-Ready Implementation**
- **CLI Integration**: Enhanced agent now default with rich feature showcase
- **Web API Integration**: Optional enhanced features with backward compatibility
- **Comprehensive Testing**: 50+ test cases covering all advanced functionality
- **Performance Optimization**: <1 second response times for most operations
- **Documentation**: Complete implementation summary and usage examples

#### Usage Examples:

**Natural Conversation**
```bash
You: "read my daily notes"           → Automatically finds daily-*.md files
You: "help me create a note"         → Starts guided note creation workflow
You: "find AI research"              → Smart search with contextual suggestions
You: "update that file"              → Asks for clarification with file suggestions
```

**Advanced Features**
```bash
You: "features"     → Shows enhanced capabilities status
You: "stats"        → Session statistics and performance metrics
You: "patterns"     → User learning data and preferences
You: "flows"        → Available conversation workflows
```

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

### 🎯 SMS-38 IMPACT:
**Conversational AI Revolution**: SELENE now provides an intelligent, context-aware chat experience that:
- **Understands natural language** with fuzzy matching and smart inference
- **Learns from user patterns** to provide increasingly personalized assistance
- **Guides complex workflows** through multi-step conversation flows
- **Provides intelligent suggestions** based on context and usage patterns
- **Handles errors gracefully** with helpful recovery suggestions

**Ready for Production**: Complete enhanced chat system with CLI and web integration, comprehensive testing, and backward compatibility.

### 🔄 NEXT STEPS:
1. **SMS-20**: Mobile Interface (Progressive Web App)
2. **SMS-21**: Plugin System (Extensible architecture)
3. **SMS-22**: Advanced Analytics (Usage insights)
4. **Integration**: Advanced file monitoring with enhanced chat workflows

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

### ✅ COMPLETED: SMS-37 Enhanced NLP Processing (NEW - 2025-07-16)
**Status**: ✅ **COMPLETE** - Advanced natural language processing pipeline implemented

#### What was implemented:

**Enhanced NLP Processing (SMS-37)**
1. **Language Processing Pipeline**: Comprehensive text analysis with entity extraction and sentiment analysis
2. **Intent Classification**: Advanced intent recognition for better conversation flow
3. **Parameter Extraction**: Smart extraction of parameters from natural language queries
4. **Conversation Context**: Enhanced context management with turn-based conversation tracking
5. **NLP Integration**: Seamless integration with existing ChatAgent architecture

**NLP Features**
- **Entity Recognition**: Extract names, locations, dates, and custom entities from user input
- **Sentiment Analysis**: Understand emotional context for better response generation
- **Intent Classification**: Classify user intents (read, write, search, process, etc.)
- **Parameter Extraction**: Extract tool parameters from natural language descriptions
- **Context Awareness**: Maintain conversation context across multiple turns
- **Confidence Scoring**: Score classification and extraction confidence for reliability

**Implementation Details**
- **4 Core NLP Modules**: `language_processor.py`, `intent_classifier.py`, `parameter_extractor.py`, `conversation_context.py`
- **Comprehensive Testing**: 10+ test cases covering all NLP functionality
- **Performance Optimized**: Local processing with minimal dependencies
- **Extensible Design**: Easy to add new intents, entities, and processing rules

**Ready for Production**: Complete NLP pipeline ready for SMS-38 (Advanced Chat Features)

### ✅ COMPLETED: SMS-32 Ollama Connection Manager (NEW - 2025-07-16)
**Status**: ✅ **COMPLETE** - Centralized connection management for Ollama services implemented

#### What was implemented:

**Connection Management System (SMS-32)**
1. **OllamaConnectionManager**: Centralized connection pooling and management
2. **Health Monitoring**: Background health checks with configurable intervals
3. **Configuration System**: Environment variable support (OLLAMA_HOST, OLLAMA_PORT, etc.)
4. **Connection Pooling**: Shared connections with automatic reconnection
5. **Resource Management**: Proper cleanup and connection lifecycle management

**Key Features**
- **Connection Pooling**: Reuse connections across multiple processors
- **Health Monitoring**: Automatic health checks with retry mechanisms
- **Environment Config**: Support for OLLAMA_HOST, OLLAMA_PORT, and other env vars
- **Error Handling**: Comprehensive error handling with connection fallback
- **Resource Cleanup**: Proper connection lifecycle management
- **Backward Compatibility**: Existing OllamaProcessor interface maintained

**Implementation Details**
- **OllamaConnectionManager**: 400+ lines of comprehensive connection management
- **OllamaConfig**: Configuration system with environment variable support
- **Connection Pooling**: Shared HTTP clients with configurable limits
- **Health Monitoring**: Background monitoring with status tracking
- **23 Comprehensive Tests**: Full test coverage with mocking and async support

**Integration**
- **Updated OllamaProcessor**: Uses connection manager for improved reliability
- **Global Manager**: Shared connection manager instance for efficiency
- **Context Manager**: Safe connection handling with automatic cleanup
- **Configuration**: Environment variables override default settings

**Ready for Production**: All Ollama processors now use centralized connection management

## 🎯 PROJECT STATUS UPDATE (2025-07-16)

### ✅ MAJOR MILESTONE: SMS-19 Advanced AI Features Merged

**Commit**: `2c2740a` - "SMS-19: Complete Advanced AI Features Implementation"  
**Branch**: Successfully merged `feature/sms-19-advanced-ai` → `main`  
**Test Results**: 74/75 tests passing (1 skipped integration test)

#### What was delivered:
- **940+ lines** of new advanced AI processing code
- **36 comprehensive tests** for multi-model and chain processing  
- **5 new REST API endpoints** for advanced features
- **Complete documentation** and examples
- **Zero breaking changes** to existing functionality

#### Production-Ready Features:
1. **Multi-Model Processing**: Automatic task routing across multiple AI models
2. **Chain Processing**: Sequential and parallel task execution with conditional branching
3. **Performance Monitoring**: Real-time statistics and analytics
4. **Fallback Mechanisms**: Intelligent fallback when primary models fail
5. **Web API Integration**: Complete REST API support for all advanced features

### 🚀 DEVELOPMENT VELOCITY
- **SMS-33**: Prompt Template System (Merged)
- **SMS-19**: Advanced AI Features (Merged) 
- **SMS-18**: Web Interface (Production)
- **SMS-17**: File Monitoring (Architecture Ready)
- **SMS-16**: JIRA Integration (Production)
- **SMS-15**: Vector Database (Production)
- **SMS-14**: Local AI Processing (Production)

### 📊 CURRENT STATISTICS
- **Total Features**: 8 major SMS implementations complete
- **Test Coverage**: 74/75 tests passing (98.7% success rate)
- **Code Quality**: All linting, formatting, and type checking passing
- **Documentation**: Comprehensive with examples and tutorials
- **Performance**: Optimized for local hardware with <10s processing times

### 🔮 NEXT PRIORITIES
1. **SMS-20**: Mobile Interface (Progressive Web App)
2. **SMS-21**: Plugin System (Extensible architecture)
3. **SMS-22**: Advanced Analytics (Usage insights)

**Selene is now a comprehensive, production-ready local-first AI processing system! 🎉**