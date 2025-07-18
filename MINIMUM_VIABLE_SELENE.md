# Minimum Viable Selene - Complete Guide

A comprehensive guide to the minimum files needed to run Selene Second Brain Processing System.

## 📋 **MINIMUM REQUIRED FILES**

### **Core Python Package Structure**
```
selene/
├── __init__.py                    # Package initialization
├── main.py                        # CLI entry point (PRIMARY)
├── processors/                    # AI Processing Engine
│   ├── __init__.py
│   ├── base.py                    # Abstract processor interface
│   ├── ollama_processor.py        # Local AI processor (ESSENTIAL)
│   └── llm_processor.py           # Cloud AI fallback
├── vector/                        # Vector Database
│   ├── __init__.py
│   ├── chroma_store.py            # ChromaDB integration
│   └── embedding_service.py       # Text embeddings
├── connections/                   # Connection Analysis (SMS-22)
│   ├── __init__.py
│   ├── models.py                  # Connection data models
│   ├── discovery.py               # Connection discovery engine
│   ├── analyzer.py                # Confidence scoring
│   ├── storage.py                 # SQLite database
│   └── statistics.py              # Analytics
└── web/                           # Web Interface
    ├── __init__.py
    ├── app.py                     # FastAPI application
    └── templates/
        └── index.html             # Main dashboard
```

### **Configuration Files**
```
├── pyproject.toml                 # Package configuration (REQUIRED)
├── requirements.txt               # Python dependencies (REQUIRED)
└── .env                          # Environment variables (optional)
```

### **Documentation**
```
├── README.md                     # Project overview
└── CLAUDE.md                     # Usage instructions
```

---

## 🚀 **GETTING STARTED - QUICK SETUP**

### **1. Install Dependencies**
```bash
# Install Python dependencies
pip install -r requirements.txt

# Install development tools (optional)
pip install -r requirements-dev.txt
```

### **2. Install Local AI (Ollama)**
```bash
# macOS
brew install ollama

# Linux
curl -fsSL https://ollama.ai/install.sh | sh

# Start Ollama service
ollama serve

# Pull required models
ollama pull llama3.2:1b         # Text processing (1.3GB)
ollama pull nomic-embed-text    # Embeddings (274MB)
```

### **3. Verify Installation**
```bash
# Test basic functionality
python -m selene.main --help

# Test AI processing
python -m selene.main process --content "Test note" --task summarize

# Test web interface
python -m selene.main web
```

---

## 📖 **CORE FUNCTIONALITY DOCUMENTATION**

### **1. CLI Commands (selene/main.py)**

#### **Basic Operations**
```bash
# System management
selene start                      # Initialize system
selene version                    # Show version
selene --help                     # Show help

# AI Note Processing
selene process --content "text" --task summarize
selene process --file note.txt --task enhance
selene process --file research.md --task extract_insights
```

#### **Vector Database Operations**
```bash
# Store notes with semantic search
selene vector store --content "Important notes" --metadata '{"type":"research"}'
selene vector store --file document.txt --id my-doc-1

# Search notes semantically
selene vector search --query "machine learning insights" --results 10
selene vector list --results 20
selene vector stats
```

#### **Connection Analysis (SMS-22)**
```bash
# Discover connections between notes
selene connections discover

# Analyze specific note connections
selene connections analyze --note-id note1

# Get connection statistics
selene connections stats
selene connections report
```

#### **Web Interface**
```bash
# Start web dashboard
selene web                        # http://localhost:8000
selene web --host 0.0.0.0 --port 8080
```

### **2. AI Processing Engine (selene/processors/)**

#### **OllamaProcessor - Local AI Processing**
```python
from selene.processors import OllamaProcessor

processor = OllamaProcessor()

# Process content
result = await processor.process_content(
    content="Meeting notes from today",
    task="summarize",
    model="llama3.2:1b"
)

print(result.processed_content)
print(f"Confidence: {result.metadata['confidence']}")
```

#### **Available Processing Tasks**
- **`summarize`** - Create concise summaries
- **`enhance`** - Improve clarity and structure
- **`extract_insights`** - Extract key insights
- **`questions`** - Generate thoughtful questions
- **`classify`** - Categorize and tag content

### **3. Vector Database (selene/vector/)**

#### **ChromaStore - Semantic Search**
```python
from selene.vector import ChromaStore

store = ChromaStore()

# Store document
store.store_document(
    content="Research about AI and machine learning",
    doc_id="research-001",
    metadata={"type": "research", "topic": "AI"}
)

# Search semantically
results = store.search("artificial intelligence", n_results=5)
print(results)
```

#### **EmbeddingService - Text Embeddings**
```python
from selene.vector import EmbeddingService

service = EmbeddingService()

# Generate embeddings
embedding = await service.generate_embedding("Sample text")
print(f"Embedding dimension: {len(embedding)}")
```

### **4. Connection Analysis (selene/connections/)**

#### **Connection Discovery**
```python
from selene.connections import ConnectionDiscovery, ConnectionStorage

# Initialize
discovery = ConnectionDiscovery()
storage = ConnectionStorage()

# Discover connections
connections = await discovery.discover_connections()

# Store connections
stored_count = storage.store_connections(connections)
print(f"Stored {stored_count} connections")
```

#### **Connection Types**
- **`SEMANTIC`** - Content similarity
- **`TEMPORAL`** - Time-based relationships
- **`TOPICAL`** - Shared themes
- **`REFERENCE`** - Explicit links
- **`CONCEPTUAL`** - Abstract concepts
- **`CAUSAL`** - Cause-effect relationships
- **`HIERARCHICAL`** - Parent-child relationships

### **5. Web Interface (selene/web/)**

#### **FastAPI Application**
```python
from selene.web import app

# The web app provides:
# - Real-time dashboard at http://localhost:8000
# - REST API endpoints for all functionality
# - Content processing interface
# - Vector search interface
# - Connection analysis dashboard
```

#### **Available Endpoints**
- **`GET /`** - Main dashboard
- **`POST /process`** - Process content
- **`GET /vector/search`** - Search vectors
- **`GET /connections/stats`** - Connection statistics
- **`GET /health`** - System health check

---

## ⚙️ **CONFIGURATION**

### **Environment Variables**
```bash
# Ollama Configuration
export OLLAMA_HOST=http://localhost:11434
export OLLAMA_PORT=11434
export OLLAMA_TIMEOUT=120.0

# OpenAI Fallback (optional)
export OPENAI_API_KEY=your-api-key-here

# Logging
export LOG_LEVEL=INFO
```

### **Default Models**
- **Text Processing:** `llama3.2:1b` (1.3GB, fast, good quality)
- **Embeddings:** `nomic-embed-text` (274MB, local embeddings)
- **Alternative:** `llama3.2` (3GB, slower, better quality)

---

## 🔧 **SYSTEM REQUIREMENTS**

### **Minimum Hardware**
- **RAM:** 8GB (16GB+ recommended)
- **Storage:** 4GB free space
- **CPU:** Modern multi-core processor

### **Software Dependencies**
```python
# Core dependencies (requirements.txt)
typer>=0.9.0           # CLI framework
rich>=13.0.0           # Terminal formatting
loguru>=0.7.0          # Logging
fastapi>=0.104.0       # Web framework
uvicorn>=0.24.0        # ASGI server
chromadb>=0.4.0        # Vector database
ollama>=0.2.0          # Local AI client
python-multipart       # File uploads
jinja2                 # Template engine
```

### **Optional Dependencies**
```python
# Development tools (requirements-dev.txt)
pytest>=7.0.0          # Testing framework
black>=23.0.0          # Code formatting
isort>=5.12.0          # Import sorting
flake8>=6.0.0          # Linting
mypy>=1.0.0            # Type checking
```

---

## 🧪 **TESTING**

### **Run Tests**
```bash
# Run all tests
pytest

# Run specific test file
pytest tests/test_processors.py

# Run with coverage
pytest --cov=selene
```

### **Manual Testing**
```bash
# Test AI processing
python -m selene.main process --content "Test content" --task summarize

# Test vector operations
python -m selene.main vector store --content "Test document"
python -m selene.main vector search --query "test"

# Test web interface
python -m selene.main web
# Visit http://localhost:8000

# Test connections
python -m selene.main connections discover
python -m selene.main connections stats
```

---

## 📊 **PERFORMANCE BENCHMARKS**

### **Local AI Processing (llama3.2:1b)**
- **Summarization:** 7-12 seconds per note
- **Enhancement:** 10-15 seconds per note
- **Insight extraction:** 8-14 seconds per note
- **Question generation:** 6-10 seconds per note

### **Vector Operations**
- **Document storage:** <1 second
- **Semantic search:** <1 second
- **Bulk operations:** ~100 documents/second

### **Connection Discovery**
- **Small vault (50 notes):** 2-5 seconds
- **Medium vault (200 notes):** 10-30 seconds
- **Large vault (500+ notes):** 1-3 minutes

---

## 🚨 **TROUBLESHOOTING**

### **Common Issues**

#### **1. Ollama Not Running**
```bash
# Check if Ollama is running
ollama list

# Start Ollama service
ollama serve

# Pull required models
ollama pull llama3.2:1b
ollama pull nomic-embed-text
```

#### **2. Import Errors**
```bash
# Install in development mode
pip install -e .

# Or install dependencies
pip install -r requirements.txt
```

#### **3. Database Issues**
```bash
# Check if databases exist
ls -la *.db chroma_db/

# Reset databases (caution: deletes data)
rm -rf chroma_db/ *.db
```

#### **4. Performance Issues**
```bash
# Check system resources
htop
df -h

# Use lighter model
export OLLAMA_MODEL=llama3.2:1b

# Reduce batch sizes
export SELENE_BATCH_SIZE=5
```

---

## 🎯 **USAGE PATTERNS**

### **1. Basic Note Processing**
```bash
# Process a single note
selene process --file "meeting-notes.md" --task enhance

# Process with specific model
selene process --content "Draft text" --task summarize --model llama3.2:1b
```

### **2. Knowledge Management**
```bash
# Store notes for semantic search
selene vector store --file "research-paper.md" --metadata '{"type":"research"}'

# Search across all notes
selene vector search --query "machine learning applications" --results 10
```

### **3. Connection Discovery**
```bash
# Discover all connections
selene connections discover

# Analyze specific note
selene connections analyze --note-id "important-note"

# Get network statistics
selene connections stats
```

### **4. Web Dashboard**
```bash
# Start web interface
selene web --host 0.0.0.0 --port 8000

# Access dashboard at http://localhost:8000
# Features: processing, search, connections, analytics
```

---

## 📈 **SCALING CONSIDERATIONS**

### **For Large Note Collections (1000+ notes)**
- Use connection discovery in batches
- Increase vector database memory allocation
- Consider using faster hardware
- Monitor disk space for databases

### **For Team Usage**
- Host web interface on network (`--host 0.0.0.0`)
- Use shared database storage
- Configure proper logging and monitoring
- Set up automated backups

---

## 🔐 **PRIVACY & SECURITY**

### **Local-First Architecture**
- **All AI processing runs locally** with Ollama
- **No data transmission** to external services
- **Local vector database** with ChromaDB
- **Optional cloud fallback** (OpenAI) with explicit API key

### **Data Storage**
- **Vector database:** `chroma_db/` directory
- **Connections:** `connections.db` SQLite file
- **Logs:** `logs/selene.log` (30-day retention)

---

## 📚 **ADDITIONAL RESOURCES**

### **Architecture Documentation**
- See `CLAUDE.md` for detailed usage examples
- Check `pyproject.toml` for package configuration
- Review `tests/` directory for implementation examples

### **Model Information**
- **llama3.2:1b:** Fast, efficient, good quality (recommended)
- **nomic-embed-text:** Local embeddings, no external API
- **Alternative models:** Available through Ollama registry

### **Integration Examples**
- **Obsidian workflow:** Process `.md` files directly
- **Automation:** Batch processing with scripts
- **API usage:** FastAPI endpoints for programmatic access

---

This document provides everything needed to run Selene with its core functionality. The system prioritizes privacy, performance, and local processing while providing sophisticated AI-powered note analysis and connection discovery capabilities.