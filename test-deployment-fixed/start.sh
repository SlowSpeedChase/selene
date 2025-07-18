#!/bin/bash
# Selene Startup Script

# Activate virtual environment
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
else
    echo "❌ Virtual environment not found. Run ./install.sh first."
    exit 1
fi

# Check if Ollama is running (optional)
if command -v ollama &> /dev/null; then
    if ! curl -s http://localhost:11434/api/tags &> /dev/null; then
        echo "⚠️  Ollama not running. Start it with: ollama serve"
        echo "   Or continue with OpenAI API key for cloud processing."
    else
        echo "✅ Ollama is running"
    fi
fi

# Start Selene based on argument
case "${1:-cli}" in
    "web")
        echo "🌐 Starting Selene Web Interface..."
        python3 -m selene.main web --host 0.0.0.0 --port 8000
        ;;
    "chat")
        echo "💬 Starting Selene Chat..."
        python3 -m selene.main chat --vault "${2:-./notes}"
        ;;
    "cli"|*)
        echo "🖥️  Starting Selene CLI..."
        echo "Available commands:"
        echo "  ./start.sh web    - Start web interface"
        echo "  ./start.sh chat   - Start chat interface"
        echo "  python3 -m selene.main --help - Show all commands"
        echo ""
        python3 -m selene.main --help
        ;;
esac
