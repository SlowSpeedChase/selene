#!/bin/bash
# Selene Installation Script

set -e

echo "🚀 Installing Selene - Second Brain Processing System"
echo "=================================================="

# Check Python version
python_version=$(python3 --version 2>&1 | cut -d' ' -f2)
echo "📋 Python version: $python_version"

# Create virtual environment
echo "📦 Creating virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Upgrade pip
echo "⬆️  Upgrading pip..."
pip install --upgrade pip

# Install dependencies
echo "📦 Installing dependencies..."
pip install -r requirements.txt

# Install Selene in development mode
echo "⚙️  Installing Selene..."
pip install -e .

# Create logs directory
mkdir -p logs

# Create default .env file
if [ ! -f .env ]; then
    echo "🔐 Creating default .env file..."
    cat > .env << 'EOF'
# Selene Configuration
SELENE_LOG_LEVEL=INFO
SELENE_DATA_DIR=./data

# Ollama Configuration (if using local AI)
OLLAMA_HOST=http://localhost:11434
OLLAMA_PORT=11434
OLLAMA_TIMEOUT=120.0

# Optional: OpenAI API Key for cloud AI fallback
# OPENAI_API_KEY=your-api-key-here
EOF
fi

echo "✅ Installation complete!"
echo ""
echo "🎯 Quick Start:"
echo "  1. Activate virtual environment: source venv/bin/activate"
echo "  2. Start Ollama (if using local AI): ollama serve"
echo "  3. Pull AI models: ollama pull llama3.2:1b && ollama pull nomic-embed-text"
echo "  4. Start Selene: selene start"
echo "  5. Or start web interface: selene web"
echo ""
echo "📚 For full documentation, see README.md"
