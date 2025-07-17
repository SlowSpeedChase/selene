# Selene - Local-First Second Brain Processing System

A completely local AI-powered Second Brain system for processing and managing notes. All AI processing runs locally on your machine - no data leaves your device, no usage fees, works offline.

## 🚀 Features

### Core AI Processing
- **Local AI Processing**: Complete privacy with Ollama integration (llama3.2, mistral)
- **OpenAI Fallback**: Optional cloud AI support for enhanced capabilities
- **Multi-Model Processing**: Automatic task routing across multiple AI models
- **Chain Processing**: Sequential and parallel task execution with conditional branching

### Advanced Template System
- **11 Built-in Templates**: Professional templates for all processing tasks
- **Custom Templates**: Create and manage custom prompt templates with variables
- **Template Analytics**: Usage tracking, quality scoring, and performance metrics
- **Variable System**: Dynamic variables with validation and default values

### Vector Database & Search
- **Local Vector Database**: ChromaDB with local embeddings (nomic-embed-text)
- **Semantic Search**: Intelligent content retrieval with similarity scoring
- **Offline Embeddings**: No cloud dependencies for vector operations
- **Knowledge Base**: Build your personal knowledge repository

### Web Interface
- **Modern Dashboard**: Real-time system monitoring and statistics
- **Interactive Processing**: Web-based AI content processing
- **Template Management**: Full CRUD operations for prompt templates
- **REST API**: Comprehensive API endpoints for all functionality

### Mobile Interface (NEW)
- **Progressive Web App**: Installable on iOS, Android, and desktop
- **Voice Input**: Speech-to-text for hands-free note capture
- **Offline Support**: Continue working without internet connection
- **Touch Optimized**: Gesture navigation and mobile-friendly UI
- **Background Sync**: Queue requests and process when back online
- **Native Experience**: Full-screen app with custom icons and splash screens

### Real-Time Processing Monitor (NEW)
- **10 Processing Stages**: Detailed visibility from validation to completion
- **Live Progress Tracking**: Real-time progress bars and stage updates
- **WebSocket Updates**: Instant notifications of processing events
- **Session Management**: Track individual processing requests with unique IDs
- **Performance Metrics**: Token counts, processing times, success rates
- **Web Dashboard**: Dedicated monitoring tab with statistics and timelines

### Batch Import System (NEW)
- **Drafts App Integration**: Import notes with tag filtering and auto-archive
- **Multi-Source Support**: Text files, Obsidian vaults, and Drafts app
- **Concurrent Processing**: Configurable batch sizes for optimal performance
- **Archive Management**: Automatically archive processed notes from source
- **Production Ready**: Complete deployment system with monitoring

### File Monitoring & Automation
- **Intelligent File Monitoring**: Real-time file system watching with automated processing
- **Queue Management**: Background processing with task queuing
- **JIRA Integration**: Development workflow management with ticket tracking

### Privacy & Performance
- **100% Local**: All processing runs on your machine
- **No Usage Fees**: No API charges or subscription costs
- **Offline Capable**: Works without internet connection
- **Hardware Optimized**: Efficient local model deployment

## Quick Start

### Prerequisites

- Python 3.9 or higher
- pip (Python package manager)

### Installation

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd selene
   ```

2. **Create and activate a virtual environment**:
   ```bash
   # Create virtual environment
   python -m venv venv
   
   # Activate virtual environment
   # On macOS/Linux:
   source venv/bin/activate
   # On Windows:
   venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   # Install core dependencies
   pip install -r requirements.txt
   
   # For development (includes testing and linting tools)
   pip install -r requirements-dev.txt
   
   # Or install in development mode with optional dependencies
   pip install -e ".[dev]"
   ```

4. **Set up environment variables** (optional):
   ```bash
   cp .env.example .env
   # Edit .env with your API keys and configuration
   ```

### Usage

#### Local AI Setup (Recommended)
```bash
# 1. Install and start Ollama
brew install ollama          # macOS
ollama serve                 # Start service (separate terminal)

# 2. Pull required models
ollama pull llama3.2:1b     # Text generation (1.3GB)
ollama pull nomic-embed-text # Embeddings (274MB)

# 3. Verify setup
ollama list                  # Should show both models
```

#### Quick Start Commands
```bash
# Start the system
selene start

# LOCAL AI note processing (no API key needed)
selene process --content "Your notes here" --task summarize
selene process --file note.txt --task enhance
selene process --content "Meeting notes" --task questions

# Vector database operations
selene vector store --content "Important research notes"
selene vector search --query "machine learning insights"

# Batch import from various sources
selene batch-import --source drafts --tag selene          # Import from Drafts app
selene batch-import --source text --path ~/notes          # Import from text files
selene batch-import --source obsidian --path ~/vault      # Import from Obsidian

# Advanced AI processing
selene process --content "text" --processor multi_model --task summarize
selene chain --steps "summarize,extract_insights,questions" --file note.txt

# Web interface
selene web                   # Start at http://127.0.0.1:8000

# Batch import demo
python3 demo_batch_import.py # Batch import system demonstration

# Mobile PWA demo
python3 demo_mobile.py       # Mobile interface demonstration

# Monitoring system demo
python3 test_monitoring.py   # Real-time processing monitor test

# Interactive demo
python3 demo_selene.py       # Full system demonstration
```

#### Template System
```bash
# Process with built-in templates
selene process --content "text" --task summarize --template-id custom-uuid

# Template management via web interface
selene web                   # Visit /templates for management
```

## Development

### Project Structure

```
selene/
├── selene/                         # Main package
│   ├── main.py                    # CLI entry point with Typer
│   ├── processors/                # AI processing pipeline
│   │   ├── ollama_processor.py   # Local AI with Ollama
│   │   ├── llm_processor.py      # OpenAI cloud AI
│   │   ├── multi_model_processor.py  # Multi-model routing
│   │   ├── chain_processor.py    # Chain processing
│   │   └── vector_processor.py   # Vector database ops
│   ├── batch/                     # Batch import system
│   │   ├── importer.py           # Main batch importer
│   │   ├── sources.py            # Drafts, text, Obsidian sources
│   │   └── processors.py         # Batch processing utilities
│   ├── prompts/                   # Template system
│   │   ├── manager.py            # Template management
│   │   ├── models.py             # Template data models
│   │   └── builtin_templates.py  # Built-in templates
│   ├── vector/                    # Vector database
│   │   ├── chroma_store.py       # ChromaDB integration
│   │   └── embedding_service.py  # Local embeddings
│   ├── web/                       # Web interface
│   │   ├── app.py                # FastAPI REST API
│   │   ├── models.py             # Web request models
│   │   └── templates/            # HTML templates
│   ├── monitoring/                # File monitoring
│   ├── queue/                     # Background processing
│   └── jira/                      # JIRA integration
├── tests/                         # Comprehensive test suite
│   ├── test_processors.py        # Processor tests
│   ├── test_vector.py            # Vector database tests
│   ├── test_multi_model_processor.py  # Multi-model tests
│   └── test_chain_processor.py   # Chain processing tests
├── demo_selene.py                 # Interactive demo
├── demo_batch_import.py           # Batch import demo
├── test_batch_import.py           # Batch import tests
├── project-manager.py             # JIRA workflow manager
├── scripts/                       # Production deployment
│   ├── production_setup.sh       # Production setup script
│   ├── deploy.sh                 # Deployment script
│   └── monitor.sh                # System monitoring
└── docs/                          # Documentation
    ├── batch-import-guide.md     # Batch import user guide
    └── production-deployment.md  # Production deployment guide
```

### Running Tests

```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=selene

# Run specific test file
pytest tests/test_main.py
```

### Code Quality

The project uses several tools to maintain code quality:

```bash
# Format code
black selene tests

# Sort imports
isort selene tests

# Lint code
flake8 selene tests

# Type checking
mypy selene
```

### Pre-commit Hooks

Install pre-commit hooks to automatically run quality checks:

```bash
pre-commit install
```

## Configuration

### Environment Variables

Create a `.env` file in the project root:

```bash
# OpenAI Configuration
OPENAI_API_KEY=your_openai_api_key_here

# ChromaDB Configuration
CHROMA_DB_PATH=./chroma_db

# Logging Configuration
LOG_LEVEL=INFO
LOG_FILE=logs/selene.log

# File Monitoring
WATCH_DIRECTORIES=./data,./notes
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests and quality checks
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🎯 Development Status

### ✅ Completed Features
- **SMS-14**: Local AI Note Processing Pipeline (Ollama + OpenAI fallback)
- **SMS-15**: Local Vector Database (ChromaDB with embeddings)
- **SMS-16**: JIRA Integration (Development workflow management)
- **SMS-17**: File Monitoring System (Real-time processing)
- **SMS-18**: Web UI (FastAPI + Modern Dashboard)
- **SMS-33**: Prompt Template System (11 built-in templates + custom templates)
- **SMS-19**: Advanced AI Features (Multi-model processing + Chain processing)
- **SMS-20**: Mobile Interface (Progressive Web App + Voice input + Offline support)

### 🚀 Next Features
- **SMS-21**: Plugin System (Extensible architecture)
- **SMS-22**: Advanced Analytics (Usage insights and optimization)
- **SMS-23**: Advanced Mobile Features (Camera integration, share targets)

### 📊 Current Stats
- **74/75 tests passing** (comprehensive test coverage)
- **11 built-in templates** with variable system
- **36 advanced AI tests** (multi-model + chain processing)
- **5 major AI processors** (Local, Cloud, Multi-model, Chain, Vector)
- **100% local processing** capability
- **Progressive Web App** with Lighthouse score 95+ (Performance, PWA)
- **Voice input support** with Web Speech API integration
- **Offline-first architecture** with service worker caching

## Support

For questions, issues, or contributions, please open an issue on GitHub.