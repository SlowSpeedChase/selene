"""
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
