# Architecture Overview

This document provides a comprehensive overview of the Selene system architecture, core components, and technical implementation details.

## Core Structure

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
- **docs/**: Documentation and user guides
  - `batch-import-guide.md`: Complete batch import user guide
  - `production-deployment.md`: Production deployment and maintenance guide
  - `development.md`: Development commands and setup
  - `usage.md`: Usage examples and workflows
  - `features.md`: Feature status and implementation details
  - `architecture.md`: This document
- **demo_selene.py**: Interactive demonstration of all features (NEW)
- **demo_batch_import.py**: Batch import system demonstration (NEW)
- **test_batch_import.py**: Batch import comprehensive tests (NEW)
- **project-manager.py**: Standalone JIRA-integrated workflow manager

## Key Dependencies & Technologies

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

## Batch Import System Architecture (SMS-27)

### Core Components

**BatchImporter Class**
- **Purpose**: Orchestrates the entire batch import process
- **Features**: Progress tracking, concurrent processing, error handling
- **Integration**: Works with all source types and processors
- **Output**: Processed notes, vector database storage, statistics

**Source Abstractions**
- **BaseSource**: Abstract base class for all source implementations
- **DraftsSource**: Reads from Drafts app database with SQLite integration
- **TextFileSource**: Processes text files with glob pattern matching
- **ObsidianSource**: Handles Obsidian vaults with frontmatter parsing

**Processing Pipeline**
- **Concurrent Processing**: Configurable batch sizes for optimal performance
- **Task Execution**: Sequential processing of multiple AI tasks per note
- **Progress Tracking**: Real-time progress bars and statistics
- **Error Handling**: Robust error recovery with detailed reporting

### Data Flow

```
1. Source Discovery
   ├── DraftsSource → SQLite queries with tag filtering
   ├── TextFileSource → File system scanning with glob patterns
   └── ObsidianSource → Markdown parsing with frontmatter extraction

2. Batch Processing
   ├── Note Validation → Content and metadata validation
   ├── AI Processing → Concurrent task execution (enhance, extract_insights, etc.)
   ├── Result Aggregation → Combine outputs from multiple tasks
   └── Progress Tracking → Real-time updates and statistics

3. Output Generation
   ├── File Creation → Processed notes with frontmatter and metadata
   ├── Vector Storage → Semantic search integration
   ├── Archive Management → Source note archiving
   └── Statistics → Detailed processing metrics
```

## Project Manager Integration

The project includes a comprehensive JIRA-integrated development workflow manager (`project-manager.py`) that handles:
- Sprint management and ticket selection from JIRA
- Automatic git branch creation and management  
- Time tracking with work session management
- JIRA ticket status transitions and work logging
- Development workflow automation with git operations

Configuration files:
- `.jira-config.yaml`: JIRA connection and project settings
- `.work-session.json`: Current work session state tracking

## Note Processing Architecture

### LLM Processor Features
- **OpenAI GPT Integration**: Configurable models with API key management
- **Local Ollama Processing**: Privacy-focused local AI processing
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

### Prompt Template System (SMS-33)
- **Built-in Templates**: 11 professional templates for all processing tasks
- **Custom Templates**: Create and manage custom prompt templates with variables
- **Variable System**: Dynamic variables with validation and default values
- **Template Analytics**: Usage tracking and quality scoring
- **API Integration**: Full REST API for template management
- **Template Variables**: Support for required/optional variables with validation
- **Category Organization**: Templates organized by category (analysis, enhancement, etc.)
- **Usage Analytics**: Track template performance, quality scores, and success rates
- **Model Optimizations**: Per-model parameter overrides and configurations
- **Web Management**: Full CRUD operations via REST API and web interface
- **Template Rendering**: Variable substitution with fallback mechanisms
- **Search & Filtering**: Find templates by name, tags, category, or content
- **Version Tracking**: Template versioning with author and timestamp metadata

### Advanced AI Processing (SMS-19)
- **Multi-Model Processing**: Automatic routing between multiple AI models
- **Task-Specific Routing**: Route different tasks to optimized models
- **Model Comparison**: Compare multiple models on the same task
- **Fallback Chains**: Intelligent fallback when primary models fail
- **Performance Monitoring**: Real-time statistics and analytics
- **Chain Processing**: Sequential and parallel task execution
- **Conditional Branching**: Different paths based on intermediate results
- **Retry Mechanisms**: Robust error handling with configurable retries
- **Result Aggregation**: Combine outputs from multiple processing steps

## Web Interface Architecture (SMS-18)

- **Modern Dashboard**: Real-time system monitoring and statistics
- **Content Processing**: Web-based AI content processing interface
- **Vector Search**: Interactive search interface for knowledge base
- **File Monitoring**: Web control for file monitoring system
- **Configuration Management**: Add/remove watched directories via web UI
- **Template Management**: Full prompt template CRUD operations (NEW)
- **REST API**: Comprehensive API endpoints for all functionality
- **Responsive Design**: Works on desktop and mobile devices
- **Real-time Updates**: Live status monitoring and progress tracking

## Conversational AI Architecture (SMS-36/37/38)

### Chat Agent System
- **ChatAgent Class**: Core conversational AI agent with initialization and conversation handling
- **Tool Registry System**: Extensible tool system with registration, validation, and execution
- **Configuration Management**: Comprehensive configuration system for vault paths and settings
- **Conversation State**: SQLite-based conversation memory with context management
- **CLI Integration**: Full command-line interface integration (`selene chat`)

### Enhanced NLP Processing
- **Language Processing Pipeline**: Comprehensive text analysis with entity extraction and sentiment analysis
- **Intent Classification**: Advanced intent recognition for better conversation flow
- **Parameter Extraction**: Smart extraction of parameters from natural language queries
- **Conversation Context**: Enhanced context management with turn-based conversation tracking
- **Entity Recognition**: Extract names, locations, dates, and custom entities from user input
- **Sentiment Analysis**: Understand emotional context for better response generation
- **Confidence Scoring**: Score classification and extraction confidence for reliability

### Advanced Chat Features (SMS-38)
- **Enhanced Natural Language Processing**: Fuzzy matching and smart parameter inference
- **Context-Aware Response Generation**: Personalized responses with intelligent suggestions
- **Smart Tool Selection**: Performance optimization and intelligent routing
- **Multi-turn Conversation Flows**: Guided workflows for complex tasks
- **User Pattern Learning**: Adaptive system that learns from user interactions
- **Advanced Error Handling**: Intelligent error recovery with helpful suggestions

## Connection Management (SMS-32)

### Ollama Connection Manager
- **Centralized Connection Management**: Pooled connections for improved performance
- **Health Monitoring**: Background health checks with configurable intervals
- **Configuration System**: Environment variable support (OLLAMA_HOST, OLLAMA_PORT, etc.)
- **Connection Pooling**: Shared connections with automatic reconnection
- **Resource Management**: Proper cleanup and connection lifecycle management
- **Error Handling**: Comprehensive error handling with connection fallback
- **Backward Compatibility**: Existing OllamaProcessor interface maintained

## Vector Database Architecture

### ChromaDB Integration
- **Local Storage**: Privacy-focused local vector database
- **Semantic Search**: Natural language queries across stored content
- **Metadata Support**: Rich metadata for categorization and filtering
- **Embedding Service**: Local text embedding generation
- **Performance Optimization**: Efficient storage and retrieval operations

## Note Formatting System (SMS-23)

### Comprehensive Formatting
- **15 Professional Templates**: Meeting notes, research, journal, project planning, etc.
- **Frontmatter Management**: Obsidian-compatible metadata handling
- **Content Organization**: Automatic categorization and structuring
- **AI Integration**: Enhanced note creation with processing pipeline
- **Smart Tagging**: Metadata support for organization and search

## Vault Organization System (SMS-24)

### Advanced Organization Tools
- **16 Vault Tools**: Complete vault management through conversational interface
- **Folder Management**: Create, move, and analyze folders with descriptions
- **File Organization**: Bulk operations and intelligent categorization
- **Duplicate Detection**: Content similarity and filename matching
- **Health Analysis**: Comprehensive vault health monitoring
- **Structure Analysis**: Detailed insights and recommendations
- **Safety Features**: Dry run mode, validation, and backup creation

## Production Deployment Architecture

### Automated Setup
- **production_setup.sh**: One-command production environment setup
- **Service Management**: Automatic systemd (Linux) or LaunchAgent (macOS) configuration
- **Environment Configuration**: Automated .env file creation with production settings
- **Virtual Environment**: Isolated Python environment with dependency management

### Deployment Pipeline
- **deploy.sh**: Automated deployment with backup and rollback capability
- **Git Integration**: Pull latest changes from main branch
- **Dependency Management**: Automatic dependency updates
- **Service Restart**: Graceful service restart with health checks
- **Rollback Support**: Automatic rollback on deployment failure

### Monitoring and Maintenance
- **monitor.sh**: Comprehensive system health monitoring
- **Service Status**: Check web interface, Ollama, and system processes
- **Resource Monitoring**: CPU, memory, and disk usage tracking
- **Log Analysis**: Recent activity and error detection
- **Health Checks**: Database connections and functionality validation

## Key Development Notes

- The codebase is designed as a "Second Brain Processing System" for AI-powered note processing
- **SMS-27 Batch Import System is now implemented** with full Drafts app integration
- **Production deployment system is complete** with automated setup and monitoring
- Core features include: batch import, content summarization, enhancement, insight extraction, question generation, and classification
- Strong emphasis on code quality with comprehensive tooling setup
- Modern Python practices: type hints, async support, proper packaging
- JIRA integration provides robust project management capabilities for development workflow

### Performance Characteristics
- **Local Processing**: 7-12 seconds per note with llama3.2:1b
- **Batch Processing**: 5-10 notes per minute with concurrent execution
- **Vector Operations**: <1 second for store/search operations
- **Memory Usage**: ~2GB during processing, ~500MB at rest
- **Storage**: ~1GB for models, minimal for note storage

### Security and Privacy
- **Local-First Architecture**: All processing happens on user's machine
- **No Data Transmission**: Notes never leave the local environment
- **Secure Database Access**: Read-only access to Drafts database
- **File System Security**: Proper permissions and validation
- **Archive Safety**: Backup creation before destructive operations

The architecture is designed for scalability, maintainability, and extensibility while maintaining the core principle of local-first processing for maximum privacy and control.