# Selene - Deployment Package

This is a minimal deployment package for Selene containing only the essential files needed for production use.

## 🚀 Quick Start

### 1. Installation
```bash
./install.sh
```

### 2. Setup Local AI (Recommended)
```bash
# Install Ollama
brew install ollama  # macOS
# or download from https://ollama.ai

# Start Ollama service
ollama serve

# Pull required models
ollama pull llama3.2:1b      # Fast text processing (1.3GB)
ollama pull nomic-embed-text  # Embeddings (274MB)
```

### 3. Start Selene
```bash
# Option 1: Use the wrapper script (recommended)
./selene-cli start              # Start system
./selene-cli web               # Start web interface
./selene-cli chat --vault ./notes  # Start chat

# Option 2: Use startup script
./start.sh web             # Start web interface
./start.sh chat            # Start chat interface

# Option 3: Use Python module directly
python3 -m selene.main --help
```

## 📦 What's Included

### Core Features
- ✅ **CLI Interface**: Full command-line functionality
- ✅ **Local AI Processing**: Ollama integration for privacy
- ✅ **Vector Database**: ChromaDB for semantic search
- ✅ **Web Interface**: FastAPI-based web UI
- ✅ **Chat Interface**: Basic conversational AI
- ✅ **Note Processing**: AI-powered note enhancement
- ✅ **Prompt Templates**: Built-in processing templates

### Core Commands
```bash
# Process notes with AI
./selene-cli process --content "Your note" --task summarize

# Vector database operations
./selene-cli vector store --file note.txt
./selene-cli vector search --query "machine learning"

# Web interface
./selene-cli web --port 8000

# Chat interface
./selene-cli chat --vault ./notes
```

## 🔧 Configuration

Edit `.env` file to configure:
```env
# Selene Configuration
SELENE_LOG_LEVEL=INFO
SELENE_DATA_DIR=./data

# Ollama Configuration
OLLAMA_HOST=http://localhost:11434
OLLAMA_PORT=11434
OLLAMA_TIMEOUT=120.0

# Optional: OpenAI API Key
# OPENAI_API_KEY=your-api-key-here
```

## 📁 Directory Structure

```
selene-deployment/
├── install.sh           # Installation script
├── start.sh            # Startup script
├── requirements.txt    # Core dependencies
├── pyproject.toml      # Package configuration
├── .env               # Environment variables
├── selene/            # Core application
│   ├── main.py        # CLI entry point
│   ├── processors/    # AI processing
│   ├── vector/        # Vector database
│   ├── web/          # Web interface
│   ├── chat/         # Chat system
│   └── prompts/      # Template system
└── logs/             # Application logs
```

## 🏥 Health Check

```bash
# Check system status
./selene-cli start

# Test AI processing
./selene-cli process --content "Test note" --task summarize

# Test vector database
./selene-cli vector store --content "Test content"
./selene-cli vector search --query "test"
```

## 🆘 Troubleshooting

### Ollama Issues
```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# Restart Ollama
ollama serve
```

### Python Issues
```bash
# Check Python version (requires 3.9+)
python3 --version

# Recreate virtual environment
rm -rf venv
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Dependencies
```bash
# Reinstall dependencies
pip install --upgrade -r requirements.txt
```

## 📊 Resource Requirements

### Minimum
- Python 3.9+
- 4GB RAM
- 2GB free disk space

### Recommended
- Python 3.11+
- 8GB+ RAM
- 5GB+ free disk space
- SSD storage

## 🔒 Privacy

Selene is designed for local-first processing:
- ✅ All AI processing happens locally (with Ollama)
- ✅ Data never leaves your machine
- ✅ No usage fees or API charges
- ✅ Works completely offline

## 📈 Performance

With recommended setup:
- Note processing: 7-12 seconds
- Vector operations: <1 second
- Web interface: Real-time responses
- Chat interface: <1 second response time

---

For questions or issues, see the full documentation at the main repository.
