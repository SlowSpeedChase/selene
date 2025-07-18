# Architecture Overview

This document provides a comprehensive overview of the Selene system architecture, components, and design patterns.

## 🏗️ Core Architecture

Selene is designed as a **Local-First AI System** with modular architecture supporting:
- Local AI processing with cloud fallback
- Vector database for semantic search
- Web interface with real-time monitoring
- Conversational AI for vault management
- Batch processing and import systems

## 📁 Core Structure

```
selene/                    # Main Python package
├── main.py               # CLI entry point with Typer, note processing commands
├── processors/           # Note processing pipeline with AI integration
│   ├── base.py          # Abstract base processor and result classes
│   ├── llm_processor.py # OpenAI LLM-powered note processor
│   ├── ollama_processor.py # Local Ollama processor with template integration
│   ├── vector_processor.py # ChromaDB vector database processor
│   ├── multi_model_processor.py # Multi-model processing with routing
│   └── chain_processor.py # Chain processing for complex workflows
├── batch/               # Batch import system
│   ├── importer.py     # Main BatchImporter class with progress tracking
│   ├── sources.py      # Source implementations (Drafts, text, Obsidian)
│   └── processors.py  # Batch processing utilities and execution
├── prompts/            # Prompt template system
│   ├── models.py       # Template data models with variables
│   ├── manager.py      # Template CRUD operations and analytics
│   └── builtin_templates.py # 11 professional built-in templates
├── vector/             # Local vector database integration
│   ├── chroma_store.py # ChromaDB storage and retrieval
│   └── embedding_service.py # Text embedding generation
├── web/                # FastAPI web interface
│   ├── app.py         # REST API with template management endpoints
│   └── models.py      # Pydantic models for web requests/responses
├── analytics/          # Advanced analytics system
│   ├── models.py      # Analytics data models and schemas
│   ├── collector.py   # Thread-safe data collection with SQLite
│   ├── aggregator.py  # Statistical summaries and analysis
│   ├── api.py         # REST API endpoints for analytics
│   └── integrations.py # Integration hooks for existing systems
├── chat/               # Conversational AI chatbot system
│   ├── agent.py       # Main ChatAgent with conversation handling
│   ├── config.py      # Configuration management for vault paths
│   ├── state.py       # SQLite conversation memory and context
│   ├── tools/         # Extensible tool system for vault operations
│   └── nlp/           # Enhanced natural language processing
├── connection/         # Connection management system
│   └── ollama_manager.py # Centralized Ollama connection manager
├── notes/              # Note formatting system
│   ├── formatter.py   # Comprehensive note formatting with templates
│   ├── metadata.py    # Frontmatter and metadata management
│   └── structure.py   # Content organization and structuring
├── monitoring/         # File system monitoring and processing
├── queue/              # Processing queue and background tasks
├── jira/              # JIRA integration for project management
└── __init__.py        # Package initialization with version info

tests/                  # Test suite with pytest configuration
├── test_processors.py # Processor tests with async support
├── test_vector.py     # Vector database and embedding tests
├── test_notes.py      # Note formatting tests (23 cases)
└── test_batch_import.py # Batch import tests (4/4 passing)

scripts/               # Production deployment and management
├── production_setup.sh # Automated production setup
├── deploy.sh         # Automated deployment with rollback
└── monitor.sh        # System monitoring and health checks

project-manager.py     # JIRA-integrated workflow manager
demo_selene.py        # Interactive demonstration of features
```

## 🔧 Key Dependencies & Technologies

### Core Framework
- **CLI Framework**: Typer for command-line interface
- **Web Framework**: FastAPI for REST API and web interface
- **ASGI Server**: Uvicorn for production web serving

### AI & Machine Learning
- **LLM Integration**: OpenAI API & Ollama for local processing
- **Vector Database**: ChromaDB for semantic search and embeddings
- **Text Processing**: Custom processors with template system

### User Interface
- **Terminal UI**: Rich library for beautiful output and formatting
- **Web UI**: Modern HTML/CSS/JS dashboard with real-time monitoring
- **Progressive Web App**: Full PWA with offline capabilities

### Data & Storage
- **Database**: SQLite for conversation memory and analytics
- **Configuration**: Pydantic for data validation and settings
- **Environment**: python-dotenv for configuration management

### Development & Quality
- **Testing**: pytest with comprehensive test configuration
- **Logging**: Loguru for structured logging with rotation
- **File Monitoring**: Watchdog for file system events
- **Code Quality**: Black, isort, flake8, mypy with pre-commit hooks

## 🎯 Design Patterns & Principles

### Processor Architecture
- **Abstract Base Classes**: Consistent processor interface with `BaseProcessor`
- **Result Objects**: Standardized processing results with metadata
- **Template System**: Configurable prompt templates with variable substitution
- **Multi-Model Support**: Automatic routing and fallback between AI models

### Connection Management
- **Connection Pooling**: Centralized Ollama connection management
- **Health Monitoring**: Background health checks with automatic reconnection
- **Configuration**: Environment variable support with sensible defaults
- **Resource Cleanup**: Proper connection lifecycle management

### Web Architecture
- **REST API**: Comprehensive API endpoints for all functionality
- **Real-time Updates**: WebSocket support for live monitoring
- **Responsive Design**: Mobile-first design with progressive enhancement
- **Security**: Input validation and secure file handling

### Chat System
- **Tool-Based Architecture**: Extensible tool system with registration
- **Conversation Memory**: SQLite-based persistent conversation storage
- **NLP Pipeline**: Advanced natural language processing with intent classification
- **Context Management**: Turn-based conversation tracking with state persistence

## 🔄 Data Flow

### Processing Pipeline
1. **Input**: Content via CLI, web interface, or file monitoring
2. **Preprocessing**: Template selection and variable substitution
3. **AI Processing**: Local Ollama or cloud OpenAI processing
4. **Post-processing**: Result formatting and metadata extraction
5. **Storage**: Vector database storage for semantic search
6. **Output**: Formatted results with rich terminal or web display

### Vector Database Flow
1. **Content Ingestion**: Text content with optional metadata
2. **Embedding Generation**: Local nomic-embed-text embeddings
3. **Storage**: ChromaDB persistent storage with metadata indexing
4. **Search**: Semantic similarity search with configurable results
5. **Retrieval**: Document retrieval with metadata filtering

### Web Interface Flow
1. **Request Handling**: FastAPI request validation and routing
2. **Processing**: Async processing with progress tracking
3. **Real-time Updates**: WebSocket updates for long-running tasks
4. **Response**: JSON API responses with structured data
5. **Frontend**: Dynamic UI updates with modern JavaScript

## 🛡️ Security & Privacy

### Local-First Design
- **Data Privacy**: All AI processing can run locally
- **No Cloud Dependency**: Optional cloud fallback only
- **Secure Storage**: Local SQLite and ChromaDB storage
- **Input Validation**: Comprehensive input sanitization

### Configuration Management
- **Environment Variables**: Secure configuration via `.env` files
- **No Hard-coded Secrets**: All sensitive data via environment
- **Connection Security**: Secure HTTP client configuration
- **File System Safety**: Controlled file access with validation

## 📊 Performance Characteristics

### Local Processing
- **AI Processing**: 7-12 seconds per task (llama3.2:1b)
- **Vector Operations**: <1 second (store/search)
- **Memory Usage**: 1-3GB RAM for standard operation
- **Storage**: Efficient SQLite and ChromaDB storage

### Scalability
- **Concurrent Processing**: Async architecture with connection pooling
- **Batch Operations**: Optimized batch import with progress tracking
- **Resource Management**: Configurable limits and cleanup
- **Monitoring**: Real-time performance metrics and health checks

## 🔮 Extension Points

### Plugin Architecture
- **Processor Plugins**: Custom AI processors with base class inheritance
- **Tool Plugins**: Chat system tools with registration interface
- **Source Plugins**: Batch import sources with standardized interface
- **Template Plugins**: Custom prompt templates with variable system

### Integration Points
- **JIRA Integration**: Project management workflow automation
- **Obsidian Integration**: Vault management and note processing
- **Web API**: RESTful API for external integrations
- **CLI Extensions**: Typer command extensions for new functionality