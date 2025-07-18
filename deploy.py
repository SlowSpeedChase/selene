#!/usr/bin/env python3
"""
Selene Deployment Script
========================

This script creates a minimal deployment package for Selene containing only 
the essential files needed for a working installation.

Usage:
    python deploy.py [TARGET_DIRECTORY]

The script will:
1. Create a deployment directory structure
2. Copy only essential files (no tests, docs, dev files)
3. Create a streamlined requirements.txt
4. Generate installation and startup scripts
5. Create a minimal configuration

Features included in deployment:
- Core CLI functionality (selene start, process, vector, web)
- Local AI processing (Ollama)
- Vector database (ChromaDB)
- Web interface (FastAPI)
- Chat interface (basic)
- Note processing and formatting
"""

import os
import shutil
import sys
from pathlib import Path
from typing import List, Set

# Essential files and directories for deployment
ESSENTIAL_FILES = {
    # Core package files
    "selene/__init__.py",
    "selene/main.py",
    
    # Core processors
    "selene/processors/__init__.py",
    "selene/processors/base.py", 
    "selene/processors/llm_processor.py",
    "selene/processors/ollama_processor.py",
    "selene/processors/vector_processor.py",
    "selene/processors/monitoring.py",
    
    # Vector database
    "selene/vector/__init__.py",
    "selene/vector/chroma_store.py",
    "selene/vector/embedding_service.py",
    
    # Web interface
    "selene/web/__init__.py",
    "selene/web/app.py",
    "selene/web/models.py",
    
    # Prompt system
    "selene/prompts/__init__.py",
    "selene/prompts/models.py",
    "selene/prompts/manager.py",
    "selene/prompts/builtin_templates.py",
    
    # Chat system (basic)
    "selene/chat/__init__.py",
    "selene/chat/agent.py",
    "selene/chat/config.py",
    "selene/chat/state.py",
    "selene/chat/tools/__init__.py",
    "selene/chat/tools/base.py",
    "selene/chat/tools/vault_tools.py",
    "selene/chat/tools/search_tools.py",
    "selene/chat/tools/ai_tools.py",
    
    # Connection management
    "selene/connection/__init__.py",
    "selene/connection/ollama_manager.py",
    
    # Note formatting
    "selene/notes/__init__.py",
    "selene/notes/formatter.py",
    "selene/notes/metadata.py",
    "selene/notes/structure.py",
    
    # Configuration files
    "pyproject.toml",
    "requirements.txt",
    "README.md",
    "LICENSE",
    "CLAUDE.md"
}

# Optional files to include if they exist
OPTIONAL_FILES = {
    "selene/web/static/index.html",
    "selene/web/static/style.css",
    "selene/web/static/app.js",
    ".env.example"
}

# Core dependencies only (no dev dependencies)
CORE_REQUIREMENTS = [
    "openai>=1.0.0",
    "httpx>=0.25.0", 
    "chromadb>=0.4.0",
    "pydantic>=2.0.0",
    "python-dotenv>=1.0.0",
    "loguru>=0.7.0",
    "typer>=0.9.0",
    "rich>=13.0.0",
    "fastapi>=0.104.0",
    "uvicorn>=0.24.0",
    "ollama>=0.3.0"
]

def create_deployment_structure(target_dir: Path) -> None:
    """Create the deployment directory structure."""
    print(f"📁 Creating deployment structure in {target_dir}")
    
    # Create main directories
    directories = [
        "selene",
        "selene/processors",
        "selene/vector", 
        "selene/web",
        "selene/web/static",
        "selene/prompts",
        "selene/chat",
        "selene/chat/tools",
        "selene/connection",
        "selene/notes",
        "scripts",
        "logs"
    ]
    
    for dir_path in directories:
        (target_dir / dir_path).mkdir(parents=True, exist_ok=True)

def copy_essential_files(source_dir: Path, target_dir: Path) -> None:
    """Copy essential files to deployment directory."""
    print("📋 Copying essential files...")
    
    copied_count = 0
    skipped_count = 0
    
    # Copy essential files
    for file_path in ESSENTIAL_FILES:
        source_file = source_dir / file_path
        target_file = target_dir / file_path
        
        if source_file.exists():
            # Create parent directories if needed
            target_file.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_file, target_file)
            copied_count += 1
            print(f"  ✅ {file_path}")
        else:
            skipped_count += 1
            print(f"  ❌ {file_path} (not found)")
    
    # Copy optional files if they exist
    for file_path in OPTIONAL_FILES:
        source_file = source_dir / file_path
        target_file = target_dir / file_path
        
        if source_file.exists():
            target_file.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_file, target_file)
            copied_count += 1
            print(f"  ✅ {file_path} (optional)")
    
    print(f"📊 Copied {copied_count} files, skipped {skipped_count} files")

def create_streamlined_requirements(target_dir: Path) -> None:
    """Create a streamlined requirements.txt with only core dependencies."""
    print("📦 Creating streamlined requirements.txt...")
    
    requirements_content = "# Selene - Core Dependencies Only\n"
    requirements_content += "# Install with: pip install -r requirements.txt\n\n"
    
    for requirement in CORE_REQUIREMENTS:
        requirements_content += f"{requirement}\n"
    
    (target_dir / "requirements.txt").write_text(requirements_content)
    print(f"  ✅ Created requirements.txt with {len(CORE_REQUIREMENTS)} dependencies")

def create_installation_script(target_dir: Path) -> None:
    """Create installation script for the deployment."""
    print("🔧 Creating installation script...")
    
    install_script = '''#!/bin/bash
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
'''
    
    script_path = target_dir / "install.sh"
    script_path.write_text(install_script)
    script_path.chmod(0o755)
    print("  ✅ Created install.sh")

def create_startup_script(target_dir: Path) -> None:
    """Create startup script for the deployment."""
    print("🚀 Creating startup script...")
    
    startup_script = '''#!/bin/bash
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
'''
    
    script_path = target_dir / "start.sh"
    script_path.write_text(startup_script)
    script_path.chmod(0o755)
    print("  ✅ Created start.sh")

def create_selene_wrapper(target_dir: Path) -> None:
    """Create a selene wrapper script for direct command execution."""
    print("🔧 Creating selene wrapper script...")
    
    wrapper_script = '''#!/bin/bash
# Selene CLI Wrapper Script
# This allows you to run 'selene' directly instead of 'python3 -m selene.main'

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Activate virtual environment if it exists
if [ -f "$SCRIPT_DIR/venv/bin/activate" ]; then
    source "$SCRIPT_DIR/venv/bin/activate"
fi

# Execute selene with all arguments
exec python3 -m selene.main "$@"
'''
    
    script_path = target_dir / "selene-cli"
    script_path.write_text(wrapper_script)
    script_path.chmod(0o755)
    print("  ✅ Created selene-cli wrapper script")

def create_minimal_main(target_dir: Path) -> None:
    """Create a minimal main.py with only essential imports."""
    print("🔧 Creating minimal main.py...")
    
    minimal_main = '''"""
Main entry point for Selene - Second Brain Processing System (Deployment Version)
"""

import asyncio
import os
from pathlib import Path
from typing import Optional

import typer
from loguru import logger
from rich.console import Console
from rich.table import Table

from selene import __version__

app = typer.Typer(
    name="selene",
    help="Selene - Second Brain Processing System",
    add_completion=False,
)
console = Console()


def setup_logging() -> None:
    """Configure logging for the application."""
    logger.remove()
    logger.add(
        "logs/selene.log",
        rotation="1 day",
        retention="30 days",
        level="INFO",
        format="{time:YYYY-MM-DD HH:mm:ss} | {level} | {name}:{function}:{line} | {message}",
    )
    logger.add(
        lambda msg: console.print(msg, end=""),
        level="INFO",
        format="<green>{time:HH:mm:ss}</green> | <level>{level}</level> | {message}",
    )


@app.command()
def start() -> None:
    """Start the Selene system."""
    setup_logging()
    logger.info("🚀 Selene deployment version started")
    logger.info(f"📦 Version: {__version__}")
    console.print("✅ Selene is ready!")
    console.print("💡 Try: selene-cli process --help")


@app.command()
def version() -> None:
    """Show version information."""
    console.print(f"Selene v{__version__}")


@app.command()
def process(
    content: Optional[str] = typer.Option(None, "--content", help="Content to process"),
    file: Optional[Path] = typer.Option(None, "--file", help="File to process"),
    task: str = typer.Option("summarize", "--task", help="Processing task"),
    processor: str = typer.Option("ollama", "--processor", help="Processor to use"),
    model: Optional[str] = typer.Option(None, "--model", help="Model to use"),
    output: Optional[Path] = typer.Option(None, "--output", help="Output file"),
) -> None:
    """Process content with AI."""
    asyncio.run(_process_content(content, file, task, processor, model, output))


async def _process_content(
    content: Optional[str],
    file: Optional[Path],
    task: str,
    processor: str,
    model: Optional[str],
    output: Optional[Path],
) -> None:
    """Process content asynchronously."""
    if not content and not file:
        console.print("❌ Please provide either --content or --file")
        return

    if file:
        if not file.exists():
            console.print(f"❌ File not found: {file}")
            return
        content = file.read_text()

    try:
        # Dynamic imports to avoid missing dependencies
        if processor == "ollama":
            from selene.processors.ollama_processor import OllamaProcessor
            proc = OllamaProcessor(model=model or "llama3.2:1b")
        else:
            from selene.processors.llm_processor import LLMProcessor
            proc = LLMProcessor(model=model or "gpt-3.5-turbo")

        result = await proc.process(content, task)
        
        if output:
            output.write_text(result.content)
            console.print(f"✅ Result saved to: {output}")
        else:
            console.print("📄 Result:")
            console.print(result.content)
            
    except Exception as e:
        console.print(f"❌ Error: {e}")


@app.command()
def vector() -> None:
    """Vector database operations."""
    console.print("🔍 Vector database operations")
    console.print("Available commands:")
    console.print("  vector store   - Store content")
    console.print("  vector search  - Search content")
    console.print("  vector stats   - Show statistics")


@app.command()
def web(
    host: str = typer.Option("127.0.0.1", "--host", help="Host to bind to"),
    port: int = typer.Option(8000, "--port", help="Port to bind to"),
    reload: bool = typer.Option(False, "--reload", help="Enable auto-reload"),
) -> None:
    """Start the web interface."""
    try:
        import uvicorn
        from selene.web.app import app as web_app
        
        console.print(f"🌐 Starting web interface at http://{host}:{port}")
        uvicorn.run(web_app, host=host, port=port, reload=reload)
    except ImportError:
        console.print("❌ Web interface dependencies not installed")
    except Exception as e:
        console.print(f"❌ Error starting web interface: {e}")


@app.command()
def chat(
    vault: Optional[str] = typer.Option(None, "--vault", help="Vault path"),
    debug: bool = typer.Option(False, "--debug", help="Enable debug mode"),
) -> None:
    """Start the chat interface."""
    try:
        setup_logging()
        
        if vault:
            vault_path = Path(vault)
            if not vault_path.exists():
                console.print(f"❌ Vault path does not exist: {vault}")
                return
        
        # Dynamic imports to avoid missing dependencies
        from selene.chat.config import ChatConfig
        from selene.chat.agent import ChatAgent
        
        config = ChatConfig(vault_path=vault_path if vault else None)
        agent = ChatAgent(config)
        
        console.print("💬 Selene Chat Interface")
        console.print("Type 'help' for commands, 'quit' to exit")
        
        while True:
            try:
                user_input = input("You: ").strip()
                if user_input.lower() in ["quit", "exit"]:
                    break
                elif user_input.lower() == "help":
                    console.print("Available commands:")
                    console.print("  help  - Show this help")
                    console.print("  quit  - Exit chat")
                    continue
                
                response = agent.process_message(user_input)
                console.print(f"Selene: {response}")
                
            except KeyboardInterrupt:
                break
            except Exception as e:
                console.print(f"❌ Error: {e}")
                
        console.print("👋 Goodbye!")
        
    except Exception as e:
        console.print(f"❌ Error starting chat: {e}")


if __name__ == "__main__":
    app()
'''
    
    main_path = target_dir / "selene" / "main.py"
    main_path.write_text(minimal_main)
    print("  ✅ Created minimal main.py")

def create_deployment_readme(target_dir: Path) -> None:
    """Create a deployment-specific README."""
    print("📄 Creating deployment README...")
    
    readme_content = '''# Selene - Deployment Package

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
'''
    
    (target_dir / "README.md").write_text(readme_content)
    print("  ✅ Created deployment README.md")

def main():
    """Main deployment function."""
    # Get target directory from command line or use default
    if len(sys.argv) > 1:
        target_dir = Path(sys.argv[1]).resolve()
    else:
        target_dir = Path("./selene-deployment").resolve()
    
    source_dir = Path(__file__).parent.resolve()
    
    print(f"🎯 Selene Deployment Script")
    print(f"📂 Source: {source_dir}")
    print(f"📁 Target: {target_dir}")
    print("=" * 50)
    
    # Create deployment structure
    create_deployment_structure(target_dir)
    
    # Copy essential files
    copy_essential_files(source_dir, target_dir)
    
    # Create streamlined requirements
    create_streamlined_requirements(target_dir)
    
    # Create installation script
    create_installation_script(target_dir)
    
    # Create startup script
    create_startup_script(target_dir)
    
    # Create selene wrapper script
    create_selene_wrapper(target_dir)
    
    # Create minimal main.py
    create_minimal_main(target_dir)
    
    # Create deployment README
    create_deployment_readme(target_dir)
    
    print("=" * 50)
    print("🎉 Deployment package created successfully!")
    print(f"📁 Location: {target_dir}")
    print()
    print("🚀 Next steps:")
    print(f"  1. cd {target_dir}")
    print("  2. ./install.sh")
    print("  3. ./start.sh web")
    print()
    print("📦 Package size:", end=" ")
    
    # Calculate package size
    total_size = 0
    for root, dirs, files in os.walk(target_dir):
        for file in files:
            file_path = os.path.join(root, file)
            if os.path.exists(file_path):
                total_size += os.path.getsize(file_path)
    
    # Convert to human readable
    if total_size < 1024:
        print(f"{total_size} bytes")
    elif total_size < 1024**2:
        print(f"{total_size/1024:.1f} KB")
    elif total_size < 1024**3:
        print(f"{total_size/1024**2:.1f} MB")
    else:
        print(f"{total_size/1024**3:.1f} GB")

if __name__ == "__main__":
    main()