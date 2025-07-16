"""
Main entry point for Selene - Second Brain Processing System
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
from selene.jira import JiraClient, TicketManager
from selene.monitoring import FileWatcher, MonitorConfig
from selene.processors import LLMProcessor, OllamaProcessor, VectorProcessor
from selene.queue import ProcessingQueue, QueueManager

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
    logger.info("System started")
    console.print(
        f"[bold green]Selene v{__version__} - Second Brain Processing System[/bold green]"
    )
    console.print("[cyan]System initialized successfully![/cyan]")


@app.command()
def version() -> None:
    """Show version information."""
    console.print(f"Selene version: {__version__}")


@app.command()
def process(
    content: Optional[str] = typer.Option(
        None, "--content", "-c", help="Content to process directly"
    ),
    file_path: Optional[Path] = typer.Option(
        None, "--file", "-f", help="File to process"
    ),
    task: str = typer.Option(
        "enhance",
        "--task",
        "-t",
        help="Processing task: summarize, enhance, extract_insights, questions, classify",
    ),
    processor: str = typer.Option(
        "ollama",
        "--processor",
        "-p",
        help="Processor type: ollama (local), openai (cloud), vector (local database)",
    ),
    model: str = typer.Option(
        "llama3.2",
        "--model",
        "-m",
        help="Model to use (llama3.2, mistral, gpt-4o-mini, etc.)",
    ),
    output: Optional[Path] = typer.Option(
        None, "--output", "-o", help="Output file path"
    ),
    api_key: Optional[str] = typer.Option(
        None, "--api-key", help="OpenAI API key (only for openai processor)"
    ),
    ollama_url: str = typer.Option(
        "http://localhost:11434", "--ollama-url", help="Ollama server URL"
    ),
) -> None:
    """Process notes using AI-powered enhancement."""
    setup_logging()

    # Validate processor choice
    if processor not in ["ollama", "openai", "vector"]:
        console.print(
            f"[red]Error: Invalid processor '{processor}'. Choose 'ollama', 'openai', or 'vector'.[/red]"
        )
        raise typer.Exit(1)

    # Handle API key requirements for OpenAI
    if processor == "openai":
        openai_key = api_key or os.getenv("OPENAI_API_KEY")
        if not openai_key:
            console.print(
                "[red]Error: OpenAI API key required for OpenAI processor. Use --api-key or set OPENAI_API_KEY environment variable.[/red]"
            )
            raise typer.Exit(1)

    # Validate input
    if not content and not file_path:
        console.print("[red]Error: Must provide either --content or --file[/red]")
        raise typer.Exit(1)

    if content and file_path:
        console.print(
            "[red]Error: Cannot use both --content and --file simultaneously[/red]"
        )
        raise typer.Exit(1)

    # Get content to process
    if file_path:
        if not file_path.exists():
            console.print(f"[red]Error: File not found: {file_path}[/red]")
            raise typer.Exit(1)

        try:
            content = file_path.read_text(encoding="utf-8")
        except Exception as e:
            console.print(f"[red]Error reading file: {e}[/red]")
            raise typer.Exit(1)

    # Initialize processor based on type
    try:
        if processor == "ollama":
            processor_instance = OllamaProcessor(
                {"base_url": ollama_url, "model": model}
            )
        elif processor == "openai":
            processor_instance = LLMProcessor(
                {"openai_api_key": openai_key, "model": model}
            )
        else:  # vector
            processor_instance = VectorProcessor(
                {"db_path": "./chroma_db", "collection_name": "selene_notes"}
            )
    except Exception as e:
        console.print(f"[red]Error initializing {processor} processor: {e}[/red]")
        raise typer.Exit(1)

    # Process content
    async def run_processing():
        console.print(
            f"[cyan]Processing with {processor} processor, task: {task}[/cyan]"
        )

        # Use the processor's selected model (may have been auto-selected during validation)
        actual_model = getattr(processor_instance, "model", model)

        if file_path:
            result = await processor_instance.process_file(
                file_path, task=task, model=actual_model
            )
        else:
            result = await processor_instance.process(
                content, task=task, model=actual_model
            )

        return result

    try:
        result = asyncio.run(run_processing())
    except Exception as e:
        console.print(f"[red]Processing failed: {e}[/red]")
        raise typer.Exit(1)

    # Display results
    if result.success:
        console.print(
            f"[green]✅ Processing completed in {result.processing_time:.2f}s[/green]"
        )

        # Show metadata table
        table = Table(title="Processing Metadata")
        table.add_column("Property", style="cyan")
        table.add_column("Value", style="white")

        for key, value in result.metadata.items():
            table.add_row(str(key), str(value))

        console.print(table)
        console.print()

        # Show processed content
        console.print("[bold]Processed Content:[/bold]")
        console.print("─" * 50)
        console.print(result.content)

        # Save to output file if specified
        if output:
            try:
                output.write_text(result.content, encoding="utf-8")
                console.print(f"[green]✅ Output saved to: {output}[/green]")
            except Exception as e:
                console.print(f"[yellow]Warning: Failed to save output: {e}[/yellow]")
    else:
        console.print(f"[red]❌ Processing failed: {result.error}[/red]")
        raise typer.Exit(1)


@app.command()
def vector(
    action: str = typer.Argument(
        ..., help="Vector action: store, search, retrieve, delete, list, stats"
    ),
    content: Optional[str] = typer.Option(
        None, "--content", "-c", help="Content to process"
    ),
    file_path: Optional[Path] = typer.Option(
        None, "--file", "-f", help="File to process"
    ),
    doc_id: Optional[str] = typer.Option(
        None, "--id", help="Document ID for retrieve/delete operations"
    ),
    query: Optional[str] = typer.Option(None, "--query", "-q", help="Search query"),
    n_results: int = typer.Option(
        5, "--results", "-n", help="Number of search results"
    ),
    metadata: Optional[str] = typer.Option(
        None, "--metadata", "-m", help="JSON metadata for document"
    ),
    db_path: str = typer.Option(
        "./chroma_db", "--db-path", help="Vector database path"
    ),
    collection: str = typer.Option(
        "selene_notes", "--collection", help="Collection name"
    ),
) -> None:
    """Manage vector database operations for document storage and retrieval."""
    setup_logging()

    # Validate action
    valid_actions = ["store", "search", "retrieve", "delete", "list", "stats"]
    if action not in valid_actions:
        console.print(
            f"[red]Error: Invalid action '{action}'. Choose from: {', '.join(valid_actions)}[/red]"
        )
        raise typer.Exit(1)

    # Validate input based on action
    if action == "store":
        if not content and not file_path:
            console.print(
                "[red]Error: Must provide either --content or --file for store action[/red]"
            )
            raise typer.Exit(1)
    elif action == "search":
        if not query:
            console.print("[red]Error: Must provide --query for search action[/red]")
            raise typer.Exit(1)
    elif action in ["retrieve", "delete"]:
        if not doc_id:
            console.print(f"[red]Error: Must provide --id for {action} action[/red]")
            raise typer.Exit(1)

    # Get content if file provided
    if file_path:
        if not file_path.exists():
            console.print(f"[red]Error: File not found: {file_path}[/red]")
            raise typer.Exit(1)

        try:
            content = file_path.read_text(encoding="utf-8")
        except Exception as e:
            console.print(f"[red]Error reading file: {e}[/red]")
            raise typer.Exit(1)

    # Parse metadata if provided
    doc_metadata = {}
    if metadata:
        try:
            import json

            doc_metadata = json.loads(metadata)
        except json.JSONDecodeError as e:
            console.print(f"[red]Error parsing metadata JSON: {e}[/red]")
            raise typer.Exit(1)

    # Add file path to metadata if provided
    if file_path:
        doc_metadata["source_file"] = str(file_path)

    # Initialize vector processor
    try:
        vector_processor = VectorProcessor(
            {"db_path": db_path, "collection_name": collection}
        )
    except Exception as e:
        console.print(f"[red]Error initializing vector processor: {e}[/red]")
        raise typer.Exit(1)

    # Run vector operation
    async def run_vector_operation():
        console.print(f"[cyan]Running vector operation: {action}[/cyan]")

        if action == "store":
            result = await vector_processor.process(
                content,
                task="store",
                metadata=doc_metadata,
                doc_id=doc_id,
                file_path=str(file_path) if file_path else None,
            )
        elif action == "search":
            result = await vector_processor.process(
                query, task="search", n_results=n_results
            )
        elif action == "retrieve":
            result = await vector_processor.process(doc_id, task="retrieve")
        elif action == "delete":
            result = await vector_processor.process(doc_id, task="delete")
        elif action == "list":
            result = await vector_processor.process("", task="list", limit=n_results)
        else:  # stats
            result = await vector_processor.process("", task="stats")

        return result

    try:
        result = asyncio.run(run_vector_operation())
    except Exception as e:
        console.print(f"[red]Vector operation failed: {e}[/red]")
        raise typer.Exit(1)

    # Display results
    if result.success:
        console.print(
            f"[green]✅ {action.title()} completed in {result.processing_time:.2f}s[/green]"
        )

        # Show result content
        if result.content:
            console.print(f"[bold]Result:[/bold]")
            console.print("─" * 50)
            console.print(result.content)
            console.print()

        # Show metadata table
        if result.metadata:
            table = Table(title=f"{action.title()} Metadata")
            table.add_column("Property", style="cyan")
            table.add_column("Value", style="white")

            for key, value in result.metadata.items():
                if key == "results" and isinstance(value, list):
                    # Special handling for search results
                    console.print()
                    search_table = Table(title="Search Results")
                    search_table.add_column("Rank", style="cyan")
                    search_table.add_column("Score", style="yellow")
                    search_table.add_column("ID", style="green")
                    search_table.add_column("Preview", style="white")

                    for res in value:
                        search_table.add_row(
                            str(res["rank"]),
                            str(res["similarity_score"]),
                            (
                                res["document_id"][:20] + "..."
                                if len(res["document_id"]) > 20
                                else res["document_id"]
                            ),
                            (
                                res["content_preview"][:50] + "..."
                                if len(res["content_preview"]) > 50
                                else res["content_preview"]
                            ),
                        )

                    console.print(search_table)
                elif key == "documents" and isinstance(value, list):
                    # Special handling for document list
                    console.print()
                    doc_table = Table(title="Documents")
                    doc_table.add_column("ID", style="cyan")
                    doc_table.add_column("Preview", style="white")
                    doc_table.add_column("Source", style="green")

                    for doc in value:
                        source = doc["metadata"].get("source_file", "N/A")
                        doc_table.add_row(
                            (
                                doc["document_id"][:20] + "..."
                                if len(doc["document_id"]) > 20
                                else doc["document_id"]
                            ),
                            (
                                doc["content_preview"][:50] + "..."
                                if len(doc["content_preview"]) > 50
                                else doc["content_preview"]
                            ),
                            source,
                        )

                    console.print(doc_table)
                else:
                    # Regular metadata
                    if isinstance(value, (dict, list)):
                        value = str(value)
                    table.add_row(str(key), str(value))

            if table.rows:
                console.print(table)

    else:
        console.print(f"[red]❌ {action.title()} failed: {result.error}[/red]")
        raise typer.Exit(1)


@app.command()
def processor_info() -> None:
    """Show information about available processors."""
    setup_logging()

    console.print("[bold]Available Processors:[/bold]")
    console.print()

    # Ollama Processor Info
    try:
        ollama_processor = OllamaProcessor({"validate_on_init": False})
        info = ollama_processor.get_processor_info()

        table = Table(title="🏠 Ollama Local Processor (Recommended)")
        table.add_column("Property", style="cyan")
        table.add_column("Value", style="white")

        for key, value in info.items():
            if isinstance(value, list):
                value = ", ".join(value)
            table.add_row(str(key), str(value))

        console.print(table)
        console.print()
    except Exception as e:
        console.print(f"[yellow]Could not load Ollama processor info: {e}[/yellow]")

    # OpenAI Processor Info
    try:
        openai_processor = LLMProcessor({"openai_api_key": "dummy"})
        info = openai_processor.get_processor_info()

        table = Table(title="☁️  OpenAI Cloud Processor")
        table.add_column("Property", style="cyan")
        table.add_column("Value", style="white")

        for key, value in info.items():
            if isinstance(value, list):
                value = ", ".join(value)
            table.add_row(str(key), str(value))

        console.print(table)

        console.print(
            "\n[dim]Note: OpenAI processor requires API key and internet connection[/dim]"
        )
    except Exception as e:
        console.print(f"[yellow]Could not load OpenAI processor info: {e}[/yellow]")


@app.command()
def doctor() -> None:
    """Diagnose system health and setup issues."""
    setup_logging()

    console.print("[bold blue]🩺 Selene System Diagnostics[/bold blue]")
    console.print("=" * 50)
    console.print()

    # Check Python version
    import sys

    python_version = (
        f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
    )
    console.print(f"🐍 Python Version: {python_version}")

    if sys.version_info < (3, 9):
        console.print("   ❌ Python 3.9+ required", style="red")
    else:
        console.print("   ✅ Python version OK", style="green")
    console.print()

    # Check Ollama connection and models
    console.print("🏠 [bold]Local AI (Ollama) Diagnostics:[/bold]")

    try:
        # Test without validation to get detailed info
        ollama_processor = OllamaProcessor({"validate_on_init": False})

        # Run connection check
        import asyncio

        connection_info = asyncio.run(ollama_processor.check_connection())

        if connection_info.get("connected"):
            console.print(
                f"   ✅ Ollama service running at {connection_info['base_url']}",
                style="green",
            )

            available_models = connection_info.get("available_models", [])
            console.print(f"   📦 Available models: {len(available_models)}")

            if available_models:
                for model in available_models[:5]:  # Show first 5
                    console.print(f"      • {model}")
                if len(available_models) > 5:
                    console.print(f"      ... and {len(available_models) - 5} more")
                console.print("   ✅ Models available", style="green")
            else:
                console.print("   ⚠️  No models installed", style="yellow")
                console.print("   💡 Run: ollama pull llama3.2")

        else:
            console.print(
                f"   ❌ Cannot connect to Ollama at {ollama_processor.base_url}",
                style="red",
            )
            console.print("   🔧 Fix: Start Ollama with 'ollama serve'")
            console.print("   📥 Install: https://ollama.ai/download")

    except Exception as e:
        console.print(f"   ❌ Ollama diagnostics failed: {e}", style="red")

    console.print()

    # Check OpenAI (cloud) availability
    console.print("☁️  [bold]Cloud AI (OpenAI) Diagnostics:[/bold]")
    api_key = os.getenv("OPENAI_API_KEY")
    if api_key:
        console.print("   ✅ OPENAI_API_KEY environment variable set", style="green")
        console.print(f"   🔑 Key: {api_key[:8]}...{api_key[-4:]}")
    else:
        console.print("   ⚠️  OPENAI_API_KEY not set", style="yellow")
        console.print("   💡 Set environment variable or use --api-key flag")
    console.print()

    # Check dependencies
    console.print("📦 [bold]Dependencies Check:[/bold]")

    required_deps = {
        "httpx": "HTTP client for Ollama",
        "openai": "OpenAI API client",
        "typer": "CLI framework",
        "rich": "Terminal formatting",
        "loguru": "Logging",
    }

    for dep, desc in required_deps.items():
        try:
            __import__(dep)
            console.print(f"   ✅ {dep}: {desc}", style="green")
        except ImportError:
            console.print(f"   ❌ {dep}: {desc} - MISSING", style="red")

    console.print()

    # Smart model recommendation
    console.print("🎯 [bold]Recommendations:[/bold]")

    try:
        ollama_processor = OllamaProcessor({"validate_on_init": False})
        connection_info = asyncio.run(ollama_processor.check_connection())

        if connection_info.get("connected"):
            available_models = connection_info.get("available_models", [])

            if available_models:
                # Find best model
                best_model = ollama_processor._find_best_available_model(
                    available_models
                )
                console.print(
                    f"   🚀 Use this command: selene process --model {best_model} --content 'test'"
                )

                # Suggest additional models
                suggested_models = ["llama3.2", "mistral", "phi3:mini"]
                missing_models = [
                    m for m in suggested_models if m not in available_models
                ]

                if missing_models:
                    console.print("   📥 Consider installing these models:")
                    for model in missing_models[:3]:
                        console.print(f"      ollama pull {model}")
            else:
                console.print("   📥 Install a model: ollama pull llama3.2")
                console.print("   🚀 Then test: selene process --content 'Hello world'")
        else:
            console.print("   🔧 Start Ollama: ollama serve")
            console.print("   📥 Install model: ollama pull llama3.2")
            console.print("   🚀 Test: selene process --content 'Hello world'")

    except Exception as e:
        console.print(f"   ⚠️  Could not generate recommendations: {e}", style="yellow")

    console.print()
    console.print("[bold green]🎉 Diagnostics complete![/bold green]")
    console.print("💡 Run 'selene process --help' for usage information")


@app.command()
def jira_setup() -> None:
    """Set up JIRA integration with your Atlassian instance."""
    setup_logging()

    console.print("[bold blue]🔧 JIRA Integration Setup[/bold blue]")
    console.print("=" * 50)
    console.print()

    console.print(
        "Your JIRA instance: [cyan]https://slowspeedchase.atlassian.net[/cyan]"
    )
    console.print()

    console.print("[bold]Steps to complete setup:[/bold]")
    console.print("1. Go to your JIRA account settings")
    console.print("2. Navigate to Security → API tokens")
    console.print("3. Create a new API token")
    console.print("4. Copy the token value")
    console.print("5. Update .jira-config.yaml with your email and API token")
    console.print()

    console.print("[bold yellow]⚠️  Security Note:[/bold yellow]")
    console.print("• Keep your API token secure and private")
    console.print("• Do not commit .jira-config.yaml with real credentials")
    console.print("• Consider using environment variables for production")
    console.print()

    console.print("[bold]Example .jira-config.yaml update:[/bold]")
    console.print(
        """[dim]
auth:
  email: "youremail@example.com"
  api_token: "ATATT3xFfGF0..."
[/dim]"""
    )

    console.print("\n💡 After setup, run: [cyan]selene jira status[/cyan]")


@app.command()
def jira_status() -> None:
    """Check JIRA connection and project status."""
    setup_logging()

    console.print("[bold blue]📊 JIRA Project Status[/bold blue]")
    console.print("=" * 50)
    console.print()

    async def check_jira_status():
        try:
            jira_client = JiraClient()

            # Test authentication
            console.print("🔐 Testing JIRA authentication...")
            auth_success = await jira_client.authenticate()

            if not auth_success:
                console.print("[red]❌ JIRA authentication failed[/red]")
                console.print(
                    "💡 Run: [cyan]selene jira-setup[/cyan] for configuration help"
                )
                return

            console.print("[green]✅ JIRA authentication successful[/green]")

            # Get connection info
            conn_info = jira_client.get_connection_info()
            console.print(f"🌐 URL: {conn_info['url']}")
            console.print(f"📧 Email: {conn_info['email']}")
            console.print(f"🎯 Project: {conn_info['project_key']}")
            console.print()

            # Get project status
            ticket_manager = TicketManager(jira_client)
            tickets = await ticket_manager.get_project_status()

            if tickets:
                console.print("[bold]📋 Project Tickets:[/bold]")

                table = Table()
                table.add_column("Key", style="cyan")
                table.add_column("Summary", style="white")
                table.add_column("Status", style="green")
                table.add_column("Type", style="yellow")
                table.add_column("Updated", style="dim")

                for ticket in tickets:
                    # Truncate long summaries
                    summary = ticket.summary
                    if len(summary) > 50:
                        summary = summary[:47] + "..."

                    # Format date
                    updated = ticket.updated[:10] if ticket.updated else "N/A"

                    table.add_row(
                        ticket.key, summary, ticket.status, ticket.issue_type, updated
                    )

                console.print(table)
                console.print(f"\n📈 Total tickets: {len(tickets)}")
            else:
                console.print("[yellow]⚠️  No tickets found in project[/yellow]")
                console.print(
                    "💡 Run: [cyan]selene jira sync[/cyan] to create project tickets"
                )

        except Exception as e:
            console.print(f"[red]❌ JIRA status check failed: {e}[/red]")

    asyncio.run(check_jira_status())


@app.command()
def jira_sync() -> None:
    """Sync project progress with JIRA tickets."""
    setup_logging()

    console.print("[bold blue]🔄 JIRA Project Sync[/bold blue]")
    console.print("=" * 50)
    console.print()

    async def sync_jira_project():
        try:
            jira_client = JiraClient()

            # Test authentication
            console.print("🔐 Authenticating with JIRA...")
            auth_success = await jira_client.authenticate()

            if not auth_success:
                console.print("[red]❌ JIRA authentication failed[/red]")
                console.print(
                    "💡 Run: [cyan]selene jira-setup[/cyan] for configuration help"
                )
                return

            console.print("[green]✅ JIRA authentication successful[/green]")
            console.print()

            # Create/update project tickets
            ticket_manager = TicketManager(jira_client)

            console.print("📝 Creating/updating project tickets...")
            created_tickets = await ticket_manager.create_project_tickets()

            if created_tickets:
                console.print(
                    f"[green]✅ Processed {len(created_tickets)} tickets[/green]"
                )

                table = Table(title="Project Tickets")
                table.add_column("Key", style="cyan")
                table.add_column("Summary", style="white")
                table.add_column("Status", style="green")
                table.add_column("Type", style="yellow")

                for ticket in created_tickets:
                    summary = ticket.summary
                    if len(summary) > 40:
                        summary = summary[:37] + "..."

                    table.add_row(ticket.key, summary, ticket.status, ticket.issue_type)

                console.print(table)
            else:
                console.print("[yellow]⚠️  No tickets created[/yellow]")

            console.print()

            # Sync current status
            console.print("🔄 Syncing project status...")
            sync_results = await ticket_manager.sync_project_status()

            if sync_results.get("error"):
                console.print(f"[red]❌ Sync failed: {sync_results['error']}[/red]")
            else:
                console.print(f"[green]✅ Sync completed[/green]")
                console.print(f"📊 Tickets found: {sync_results['tickets_found']}")
                console.print(f"📝 Tickets updated: {sync_results['tickets_updated']}")

                if sync_results.get("errors"):
                    console.print(
                        f"[yellow]⚠️  Errors: {len(sync_results['errors'])}[/yellow]"
                    )
                    for error in sync_results["errors"][:3]:  # Show first 3 errors
                        console.print(f"   • {error}")

            console.print()
            console.print("[bold green]🎉 JIRA sync complete![/bold green]")
            console.print(f"🌐 View tickets at: https://slowspeedchase.atlassian.net")

        except Exception as e:
            console.print(f"[red]❌ JIRA sync failed: {e}[/red]")

    asyncio.run(sync_jira_project())


@app.command()
def web(
    host: str = typer.Option(
        "127.0.0.1", "--host", "-h", help="Host to bind the web server"
    ),
    port: int = typer.Option(8000, "--port", "-p", help="Port to bind the web server"),
    reload: bool = typer.Option(
        False, "--reload", help="Enable auto-reload for development"
    ),
) -> None:
    """Start the web interface for Selene."""
    setup_logging()

    console.print("[bold blue]🌐 Starting Selene Web Interface[/bold blue]")
    console.print("=" * 50)
    console.print()

    try:
        import uvicorn

        from selene.web import create_app

        app_instance = create_app()

        console.print(f"🚀 Starting web server at [cyan]http://{host}:{port}[/cyan]")
        console.print(
            f"📊 API Documentation: [cyan]http://{host}:{port}/api/docs[/cyan]"
        )
        console.print(
            f"📖 ReDoc Documentation: [cyan]http://{host}:{port}/api/redoc[/cyan]"
        )
        console.print()
        console.print("[dim]Press Ctrl+C to stop the server[/dim]")

        # Run the web server
        uvicorn.run(
            app_instance,
            host=host,
            port=port,
            reload=reload,
            log_level="info",
            access_log=True,
        )

    except ImportError:
        console.print("[red]❌ FastAPI or Uvicorn not installed[/red]")
        console.print("💡 Install with: [cyan]pip install fastapi uvicorn[/cyan]")
        raise typer.Exit(1)
    except Exception as e:
        console.print(f"[red]❌ Failed to start web server: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def monitor(
    action: str = typer.Argument(
        ..., help="Monitor action: start, stop, status, add, remove, config"
    ),
    path: Optional[Path] = typer.Option(
        None, "--path", "-p", help="Directory path for add/remove actions"
    ),
    patterns: Optional[str] = typer.Option(
        None, "--patterns", help="File patterns (comma-separated, e.g., '*.txt,*.md')"
    ),
    recursive: bool = typer.Option(
        True, "--recursive/--no-recursive", help="Watch subdirectories"
    ),
    auto_process: bool = typer.Option(
        True, "--auto-process/--no-auto-process", help="Enable automatic processing"
    ),
    tasks: Optional[str] = typer.Option(
        "summarize,extract_insights",
        "--tasks",
        help="Processing tasks (comma-separated)",
    ),
    processor: str = typer.Option(
        "ollama", "--processor", help="Default processor (ollama, openai, vector)"
    ),
    config_file: str = typer.Option(
        ".monitor-config.yaml", "--config", help="Configuration file path"
    ),
) -> None:
    """Manage file monitoring and auto-processing system."""
    setup_logging()

    # Validate action
    valid_actions = [
        "start",
        "stop",
        "status",
        "add",
        "remove",
        "config",
        "process-existing",
    ]
    if action not in valid_actions:
        console.print(
            f"[red]Error: Invalid action '{action}'. Choose from: {', '.join(valid_actions)}[/red]"
        )
        raise typer.Exit(1)

    async def run_monitor_action():
        try:
            if action == "config":
                # Show current configuration
                config = MonitorConfig.from_file(config_file)

                console.print("[bold blue]📁 File Monitoring Configuration[/bold blue]")
                console.print("=" * 50)
                console.print()

                # Configuration summary
                summary = config.get_summary()

                table = Table(title="Configuration Summary")
                table.add_column("Setting", style="cyan")
                table.add_column("Value", style="white")

                table.add_row("Processing Enabled", str(summary["processing_enabled"]))
                table.add_row("Default Processor", summary["default_processor"])
                table.add_row("Batch Size", str(summary["batch_size"]))
                table.add_row(
                    "Max Concurrent Jobs", str(summary["max_concurrent_jobs"])
                )
                table.add_row(
                    "Watched Directories", str(summary["watched_directories_count"])
                )
                table.add_row(
                    "Supported Extensions",
                    ", ".join(config.supported_extensions[:5]) + "...",
                )

                console.print(table)
                console.print()

                # Watched directories
                if config.watched_directories:
                    console.print("[bold]📂 Watched Directories:[/bold]")

                    dirs_table = Table()
                    dirs_table.add_column("Path", style="cyan")
                    dirs_table.add_column("Patterns", style="white")
                    dirs_table.add_column("Recursive", style="green")
                    dirs_table.add_column("Auto Process", style="yellow")
                    dirs_table.add_column("Tasks", style="magenta")

                    for wd in config.watched_directories:
                        patterns_str = ", ".join(wd.patterns[:3])
                        if len(wd.patterns) > 3:
                            patterns_str += "..."

                        tasks_str = ", ".join(wd.processing_tasks[:2])
                        if len(wd.processing_tasks) > 2:
                            tasks_str += "..."

                        dirs_table.add_row(
                            wd.path,
                            patterns_str,
                            "✅" if wd.recursive else "❌",
                            "✅" if wd.auto_process else "❌",
                            tasks_str,
                        )

                    console.print(dirs_table)
                else:
                    console.print(
                        "[yellow]No directories configured for monitoring[/yellow]"
                    )

                console.print(f"\n💡 Config file: {config_file}")
                return

            elif action == "add":
                if not path:
                    console.print("[red]Error: --path required for add action[/red]")
                    raise typer.Exit(1)

                if not path.exists():
                    console.print(f"[red]Error: Directory does not exist: {path}[/red]")
                    raise typer.Exit(1)

                # Load config
                config = MonitorConfig.from_file(config_file)

                # Parse patterns and tasks
                pattern_list = (
                    patterns.split(",")
                    if patterns
                    else ["*.txt", "*.md", "*.pdf", "*.docx"]
                )
                task_list = (
                    tasks.split(",") if tasks else ["summarize", "extract_insights"]
                )

                # Add directory
                success = config.add_watched_directory(
                    path=str(path),
                    patterns=pattern_list,
                    recursive=recursive,
                    auto_process=auto_process,
                    processing_tasks=task_list,
                    store_in_vector_db=True,
                )

                if success:
                    # Save config
                    config.save_to_file(config_file)
                    console.print(f"[green]✅ Added watched directory: {path}[/green]")
                    console.print(f"📋 Patterns: {', '.join(pattern_list)}")
                    console.print(f"🔄 Tasks: {', '.join(task_list)}")
                else:
                    console.print(f"[red]❌ Failed to add directory: {path}[/red]")

                return

            elif action == "remove":
                if not path:
                    console.print("[red]Error: --path required for remove action[/red]")
                    raise typer.Exit(1)

                # Load config
                config = MonitorConfig.from_file(config_file)

                # Remove directory
                success = config.remove_watched_directory(str(path))

                if success:
                    # Save config
                    config.save_to_file(config_file)
                    console.print(
                        f"[green]✅ Removed watched directory: {path}[/green]"
                    )
                else:
                    console.print(
                        f"[yellow]⚠️  Directory not found in watch list: {path}[/yellow]"
                    )

                return

            # For start, stop, status, process-existing - need to work with actual file watcher
            config = MonitorConfig.from_file(config_file)

            # Validate configuration
            config_issues = config.validate()
            if config_issues:
                console.print(
                    f"[red]Configuration issues: {', '.join(config_issues)}[/red]"
                )
                console.print(
                    "💡 Run: [cyan]selene monitor config[/cyan] to check configuration"
                )
                raise typer.Exit(1)

            # Create file watcher and queue manager
            processing_queue = ProcessingQueue(
                max_size=config.queue_max_size,
                max_concurrent=config.max_concurrent_jobs,
            )
            queue_manager = QueueManager(
                processing_queue, max_workers=config.max_concurrent_jobs
            )
            file_watcher = FileWatcher(config, processing_queue)

            if action == "start":
                console.print(
                    "[bold blue]🚀 Starting File Monitoring System[/bold blue]"
                )
                console.print("=" * 50)
                console.print()

                # Start queue processing
                console.print("🔧 Starting queue manager...")
                queue_started = await queue_manager.start_processing()

                if not queue_started:
                    console.print("[red]❌ Failed to start queue manager[/red]")
                    raise typer.Exit(1)

                # Start file watching
                console.print("👀 Starting file watcher...")
                watcher_started = await file_watcher.start_watching()

                if not watcher_started:
                    console.print("[red]❌ Failed to start file watcher[/red]")
                    await queue_manager.stop_processing()
                    raise typer.Exit(1)

                console.print(
                    "[green]✅ File monitoring system started successfully![/green]"
                )
                console.print()

                # Show status
                status = file_watcher.get_status_summary()

                console.print(
                    f"📁 Watching {len(status['watcher_status']['watched_paths'])} directories:"
                )
                for watch_path in status["watcher_status"]["watched_paths"]:
                    console.print(f"   • {watch_path}")

                console.print(f"\n🔄 Queue workers: {queue_manager.max_workers}")
                console.print(f"📊 Queue capacity: {config.queue_max_size}")
                console.print(f"⚙️  Default processor: {config.default_processor}")

                console.print("\n💡 Monitor status: [cyan]selene monitor status[/cyan]")
                console.print("🛑 Stop monitoring: [cyan]selene monitor stop[/cyan]")

                # Keep running (in real implementation, this would run as a service)
                console.print("\n[dim]Press Ctrl+C to stop monitoring...[/dim]")
                try:
                    while True:
                        await asyncio.sleep(1)
                except KeyboardInterrupt:
                    console.print("\n🛑 Stopping file monitoring...")
                    await file_watcher.stop_watching()
                    await queue_manager.stop_processing()
                    console.print("[green]✅ File monitoring stopped[/green]")

            elif action == "status":
                console.print("[bold blue]📊 File Monitoring Status[/bold blue]")
                console.print("=" * 50)
                console.print()

                # This is a simplified status check since we can't connect to a running instance
                console.print(
                    "[yellow]⚠️  Status check for detached monitoring not yet implemented[/yellow]"
                )
                console.print("💡 Current configuration:")

                summary = config.get_summary()
                console.print(
                    f"   📁 Watched directories: {summary['watched_directories_count']}"
                )
                console.print(
                    f"   ⚙️  Default processor: {summary['default_processor']}"
                )
                console.print(
                    f"   🔄 Processing enabled: {summary['processing_enabled']}"
                )

                if summary["watched_directories_count"] > 0:
                    console.print("\n📂 Configured paths:")
                    for watch_path in summary["watched_paths"]:
                        console.print(f"   • {watch_path}")

                console.print(
                    "\n💡 To start monitoring: [cyan]selene monitor start[/cyan]"
                )

            elif action == "process-existing":
                console.print("[bold blue]🔄 Processing Existing Files[/bold blue]")
                console.print("=" * 50)
                console.print()

                # Start queue manager
                console.print("🔧 Starting queue manager...")
                queue_started = await queue_manager.start_processing()

                if not queue_started:
                    console.print("[red]❌ Failed to start queue manager[/red]")
                    raise typer.Exit(1)

                # Process existing files
                console.print("📁 Scanning for existing files...")
                await file_watcher.process_existing_files(str(path) if path else None)

                # Wait for processing to complete
                console.print("⏳ Processing files...")

                # Monitor queue until empty
                while True:
                    status = queue_manager.get_status()
                    queue_size = status["queue"]["queue_size"]
                    processing_count = status["queue"]["processing_count"]

                    if queue_size == 0 and processing_count == 0:
                        break

                    console.print(
                        f"   Queue: {queue_size}, Processing: {processing_count}"
                    )
                    await asyncio.sleep(2)

                # Show final stats
                final_status = queue_manager.get_status()
                total_processed = final_status["statistics"]["total_processed"]
                total_errors = final_status["statistics"]["total_errors"]

                console.print(f"\n[green]✅ Processing complete![/green]")
                console.print(f"📊 Files processed: {total_processed}")
                console.print(f"❌ Errors: {total_errors}")

                await queue_manager.stop_processing()

            elif action == "stop":
                console.print(
                    "[yellow]⚠️  Stop command for detached monitoring not yet implemented[/yellow]"
                )
                console.print("💡 Use Ctrl+C to stop interactive monitoring")

        except Exception as e:
            console.print(f"[red]❌ Monitor action failed: {e}[/red]")
            raise typer.Exit(1)

    asyncio.run(run_monitor_action())


@app.command()
def chat(
    vault: Optional[str] = typer.Option(
        None, "--vault", "-v", help="Path to Obsidian vault directory"
    ),
    config_file: Optional[str] = typer.Option(
        None, "--config", "-c", help="Path to chat configuration file"
    ),
    no_memory: bool = typer.Option(
        False, "--no-memory", help="Disable conversation memory"
    ),
    debug: bool = typer.Option(
        False, "--debug", help="Enable debug logging"
    )
) -> None:
    """Start interactive chat with your Obsidian vault."""
    setup_logging()
    
    if debug:
        logger.remove()
        logger.add(
            lambda msg: console.print(msg, end=""),
            level="DEBUG",
            format="<green>{time:HH:mm:ss}</green> | <level>{level}</level> | {message}",
        )
    
    async def run_chat():
        """Run the chat interface."""
        try:
            from selene.chat import ChatAgent, ChatConfig
            
            # Load configuration
            if config_file:
                config = ChatConfig.from_file(config_file)
            else:
                config = ChatConfig.from_file()
                
            # Override config with command line options
            if vault:
                config.vault_path = vault
            if no_memory:
                config.conversation_memory = False
                
            # Initialize agent
            agent = ChatAgent(config)
            
            if not await agent.initialize():
                console.print("[red]❌ Failed to initialize chat agent[/red]")
                raise typer.Exit(1)
                
            # Start interactive chat loop
            console.print("\n🤖 SELENE Chat Agent Ready!")
            console.print("Type 'help' for commands, 'exit' to quit.\n")
            
            try:
                while True:
                    # Get user input
                    try:
                        user_input = input("You: ").strip()
                    except (EOFError, KeyboardInterrupt):
                        break
                        
                    if not user_input:
                        continue
                        
                    if user_input.lower() in ['exit', 'quit', '/exit', '/quit']:
                        break
                        
                    # Process message
                    response = await agent.chat(user_input)
                    console.print(f"\nSELENE: {response}\n")
                    
            except KeyboardInterrupt:
                pass
                
            # Shutdown
            await agent.shutdown()
            console.print("\n👋 Chat session ended. Goodbye!")
            
        except Exception as e:
            console.print(f"[red]❌ Chat failed: {e}[/red]")
            if debug:
                import traceback
                console.print(traceback.format_exc())
            raise typer.Exit(1)
    
    asyncio.run(run_chat())


if __name__ == "__main__":
    app()
