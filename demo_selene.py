#!/usr/bin/env python3
"""
Selene Second Brain Processing System - Interactive Demo

This script demonstrates all major features of Selene including:
- Local AI processing with Ollama
- Prompt template system (SMS-33)
- Vector database operations  
- Web interface
- File monitoring
- JIRA integration

Usage: python3 demo_selene.py
"""

import asyncio
import json
import os
import sys
import time
from pathlib import Path
from typing import Optional

try:
    from rich.console import Console
    from rich.panel import Panel
    from rich.progress import track
    from rich.prompt import Confirm, Prompt
    from rich.table import Table
    from rich.text import Text
except ImportError:
    print("❌ Missing required dependency: rich")
    print("Install with: pip install rich")
    sys.exit(1)

# Add selene to path
sys.path.insert(0, str(Path(__file__).parent))

try:
    from selene.processors.ollama_processor import OllamaProcessor
    from selene.processors.vector_processor import VectorProcessor
    from selene.prompts.manager import PromptTemplateManager
    from selene.prompts.builtin_templates import register_builtin_templates
    from selene.vector.chroma_store import ChromaStore
except ImportError as e:
    print(f"❌ Failed to import Selene modules: {e}")
    print("Make sure you're running from the Selene project directory")
    sys.exit(1)


class SeleneDemo:
    """Interactive demo of Selene Second Brain Processing System."""
    
    def __init__(self, interactive: bool = True):
        self.console = Console()
        self.interactive = interactive
        self.ollama_processor = None
        self.vector_processor = None
        self.prompt_manager = None
        self.demo_content = {
            "meeting_notes": """
            Team Meeting - Q4 Planning Session
            Date: July 15, 2025
            
            Key Discussion Points:
            - Review of Q3 performance metrics showed 23% growth
            - New AI features roadmap for local processing capabilities
            - Budget allocation for infrastructure upgrades ($150K approved)
            - Hiring plan: 3 engineers, 1 designer, 1 product manager
            
            Action Items:
            - Sarah: Complete market analysis by July 30th
            - Mike: Set up development environment for new team members
            - Lisa: Draft technical specifications for AI features
            - Team: Review and approve final Q4 roadmap by August 1st
            
            Next meeting: July 22nd, 2pm PST
            """,
            
            "research_notes": """
            Research: Local AI Processing Systems
            
            Current landscape shows increasing demand for privacy-focused AI solutions.
            Key trends:
            1. Edge computing adoption rising 40% year-over-year
            2. Data privacy regulations driving local processing requirements
            3. Open-source models achieving near-GPT performance locally
            
            Technical considerations:
            - Hardware requirements: 16GB+ RAM for optimal performance
            - Model options: Llama 3.2, Mistral 7B, CodeLlama for specialized tasks
            - Integration challenges: API compatibility, error handling, fallback mechanisms
            
            Competitive analysis shows gap in user-friendly local AI tools.
            Market opportunity estimated at $2.3B by 2027.
            """,
            
            "creative_writing": """
            The old lighthouse keeper had seen many storms, but none quite like this.
            The waves crashed against the rocky shore with unprecedented fury,
            and the wind howled through the night like a living thing.
            
            As he climbed the spiral stairs to tend the beacon, Marcus reflected
            on forty years of solitary service. Each storm had taught him something
            new about resilience, about the delicate balance between isolation
            and purpose.
            
            Tonight felt different. The storm seemed to whisper secrets
            of change, of endings and new beginnings.
            """
        }
    
    def show_header(self):
        """Display demo header."""
        title = Text("🧠 Selene Second Brain Processing System", style="bold blue")
        subtitle = Text("🚀 LOCAL-FIRST AI DEMO", style="bold green")
        
        panel = Panel.fit(
            f"{title}\n{subtitle}\n\nPrivacy-focused • Performance-optimized • Completely local",
            style="blue"
        )
        
        self.console.print()
        self.console.print(panel)
        self.console.print()
    
    def check_prerequisites(self) -> bool:
        """Check if required services are available."""
        self.console.print("🔍 [bold]Checking Prerequisites...[/bold]")
        
        checks = []
        
        # Check Ollama
        try:
            import httpx
            response = httpx.get("http://localhost:11434/api/tags", timeout=5.0)
            if response.status_code == 200:
                models = response.json().get("models", [])
                checks.append(("Ollama Service", True, f"{len(models)} models available"))
            else:
                checks.append(("Ollama Service", False, "Service not responding"))
        except Exception:
            checks.append(("Ollama Service", False, "Not available - install with: brew install ollama"))
        
        # Check Python dependencies
        try:
            import chromadb
            checks.append(("ChromaDB", True, "Vector database available"))
        except ImportError:
            checks.append(("ChromaDB", False, "Missing - install with: pip install chromadb"))
        
        # Check project structure
        project_files = [
            "selene/processors/ollama_processor.py",
            "selene/prompts/manager.py",
            "selene/vector/chroma_store.py"
        ]
        
        all_files_exist = all(Path(f).exists() for f in project_files)
        checks.append(("Selene Modules", all_files_exist, "Core modules available" if all_files_exist else "Missing modules"))
        
        # Display results
        table = Table(title="System Prerequisites")
        table.add_column("Component", style="cyan")
        table.add_column("Status", style="bold")
        table.add_column("Details", style="dim")
        
        all_good = True
        for name, status, details in checks:
            status_text = "✅ Ready" if status else "❌ Missing"
            table.add_row(name, status_text, details)
            if not status:
                all_good = False
        
        self.console.print(table)
        self.console.print()
        
        if not all_good:
            self.console.print("❌ [red]Some prerequisites are missing. Please install them before continuing.[/red]")
            self.console.print("\n📖 Quick setup:")
            self.console.print("  • Install Ollama: brew install ollama")
            self.console.print("  • Pull a model: ollama pull llama3.2")
            self.console.print("  • Install deps: pip install -r requirements.txt")
            return False
        
        self.console.print("✅ [green]All prerequisites met! Ready to demo.[/green]")
        return True
    
    async def initialize_systems(self):
        """Initialize Selene systems for demo."""
        self.console.print("🚀 [bold]Initializing Selene Systems...[/bold]")
        
        # Initialize processors
        try:
            self.ollama_processor = OllamaProcessor({
                "base_url": "http://localhost:11434",
                "model": "llama3.2:1b",
                "validate_on_init": False
            })
            self.console.print("  ✅ Ollama processor initialized")
        except Exception as e:
            self.console.print(f"  ❌ Ollama processor failed: {e}")
            return False
        
        try:
            self.vector_processor = VectorProcessor({
                "db_path": "./demo_chroma_db",
                "collection_name": "selene_demo"
            })
            self.console.print("  ✅ Vector processor initialized")
        except Exception as e:
            self.console.print(f"  ❌ Vector processor failed: {e}")
            return False
        
        # Initialize prompt template system
        try:
            self.prompt_manager = PromptTemplateManager(storage_path="demo_prompt_templates")
            count = register_builtin_templates(self.prompt_manager)
            self.console.print(f"  ✅ Prompt template system initialized ({count} templates)")
        except Exception as e:
            self.console.print(f"  ❌ Prompt template system failed: {e}")
            return False
        
        self.console.print("✅ [green]All systems initialized successfully![/green]\n")
        return True
    
    def demo_prompt_templates(self):
        """Demonstrate the prompt template system (SMS-33)."""
        self.console.print(Panel.fit("🎯 SMS-33: Prompt Template System Demo", style="bold magenta"))
        
        # List available templates
        templates = self.prompt_manager.list_templates()
        
        table = Table(title="Available Prompt Templates")
        table.add_column("Name", style="cyan")
        table.add_column("Category", style="green")
        table.add_column("Description", style="dim")
        
        for template in templates[:8]:  # Show first 8
            table.add_row(
                template.name,
                template.category.value,
                template.description[:60] + "..." if len(template.description) > 60 else template.description
            )
        
        self.console.print(table)
        self.console.print(f"\n📊 Total: {len(templates)} built-in templates available")
        
        # Demo template rendering
        template = self.prompt_manager.get_template_by_name("Basic Summary")
        if template:
            self.console.print("\n🔍 [bold]Template Rendering Demo:[/bold]")
            rendered = template.render({
                "content": self.demo_content["meeting_notes"],
                "max_length": "150"
            })
            
            self.console.print(Panel(
                rendered,
                title="Rendered Prompt (Basic Summary Template)",
                border_style="blue"
            ))
        
        # Show template analytics
        analytics = self.prompt_manager.get_stats()
        self.console.print(f"\n📈 Template Statistics:")
        self.console.print(f"  • Total templates: {analytics['total_templates']}")
        self.console.print(f"  • Categories: {', '.join(analytics['categories'].keys())}")
        
        if self.interactive:
            input("\n⏸️  Press Enter to continue...")
        else:
            self.console.print("\n⏸️  [Non-interactive mode] Continuing...")
    
    async def demo_ai_processing(self):
        """Demonstrate AI processing with different tasks."""
        self.console.print(Panel.fit("🤖 Local AI Processing Demo", style="bold green"))
        
        # Show available content
        self.console.print("📄 [bold]Available demo content:[/bold]")
        for i, (name, content) in enumerate(self.demo_content.items(), 1):
            preview = content.strip()[:100] + "..." if len(content.strip()) > 100 else content.strip()
            self.console.print(f"  {i}. {name.replace('_', ' ').title()}: {preview}")
        
        # Let user choose content
        if self.interactive:
            choice = Prompt.ask("\n🔢 Choose content to process", choices=["1", "2", "3"], default="1")
        else:
            choice = "1"  # Default to first option in non-interactive mode
            self.console.print("\n🔢 [Non-interactive mode] Using default content: Meeting Notes")
        
        content_names = list(self.demo_content.keys())
        chosen_content = self.demo_content[content_names[int(choice) - 1]]
        
        # Processing tasks to demo
        tasks = [
            ("summarize", "📝 Create Summary"),
            ("enhance", "✨ Enhance Content"),
            ("extract_insights", "💡 Extract Insights"),
            ("questions", "❓ Generate Questions")
        ]
        
        self.console.print(f"\n🎯 [bold]Processing with {len(tasks)} different AI tasks...[/bold]\n")
        
        for task, description in track(tasks, description="Processing..."):
            try:
                self.console.print(f"🔄 {description}")
                
                result = await self.ollama_processor.process(
                    chosen_content,
                    task=task
                )
                
                if result.success:
                    self.console.print(Panel(
                        result.content,
                        title=f"✅ {description} Result",
                        border_style="green"
                    ))
                    
                    # Show metadata
                    metadata_text = f"Model: {result.metadata.get('model', 'unknown')} | "
                    metadata_text += f"Time: {result.processing_time:.2f}s | "
                    metadata_text += f"Tokens: ~{result.metadata.get('estimated_tokens', 0)}"
                    self.console.print(f"📊 {metadata_text}\n")
                else:
                    self.console.print(f"❌ {description} failed: {result.error}")
                
            except Exception as e:
                self.console.print(f"❌ {description} error: {e}")
            
            if task != tasks[-1][0]:  # Don't pause after last task
                time.sleep(1)  # Brief pause between tasks
        
        self.console.print("✅ [green]AI processing demo complete![/green]")
        if self.interactive:
            input("\n⏸️  Press Enter to continue...")
        else:
            self.console.print("\n⏸️  [Non-interactive mode] Continuing...")
    
    async def demo_vector_database(self):
        """Demonstrate vector database operations."""
        self.console.print(Panel.fit("🗄️ Vector Database Demo", style="bold purple"))
        
        # Store demo content in vector database
        self.console.print("📥 [bold]Storing content in vector database...[/bold]")
        
        stored_docs = []
        for name, content in track(self.demo_content.items(), description="Storing..."):
            try:
                result = await self.vector_processor.process(
                    content,
                    operation="store",
                    metadata={"type": name, "source": "demo"}
                )
                
                if result.success:
                    stored_docs.append(name)
                    self.console.print(f"  ✅ Stored: {name}")
                else:
                    self.console.print(f"  ❌ Failed to store: {name}")
                    
            except Exception as e:
                self.console.print(f"  ❌ Error storing {name}: {e}")
        
        self.console.print(f"\n📊 Successfully stored {len(stored_docs)} documents")
        
        # Demonstrate vector search
        search_queries = [
            "meeting action items and deadlines",
            "AI research and market trends",
            "lighthouse and storms"
        ]
        
        self.console.print("\n🔍 [bold]Demonstrating vector search...[/bold]")
        
        for query in search_queries:
            self.console.print(f"\n🔎 Searching for: '{query}'")
            
            try:
                result = await self.vector_processor.process(
                    query,
                    task="search",
                    n_results=2
                )
                
                if result.success and result.metadata.get('results'):
                    results = result.metadata['results']
                    
                    table = Table(title=f"Search Results for '{query}'")
                    table.add_column("Rank", style="cyan")
                    table.add_column("Score", style="green")
                    table.add_column("Content Preview", style="white")
                    table.add_column("Metadata", style="dim")
                    
                    for res in results:
                        rank = str(res.get('rank', 0))
                        score = f"{res.get('similarity_score', 0):.3f}"
                        content_preview = res.get('content_preview', '')[:60] + "..."
                        metadata = str(res.get('metadata', {}))
                        table.add_row(rank, score, content_preview, metadata)
                    
                    self.console.print(table)
                    self.console.print(f"  ✅ Found {len(results)} results")
                else:
                    self.console.print("  ❌ No results found")
                    
            except Exception as e:
                self.console.print(f"  ❌ Search error: {e}")
        
        self.console.print("\n✅ [green]Vector database demo complete![/green]")
        if self.interactive:
            input("\n⏸️  Press Enter to continue...")
        else:
            self.console.print("\n⏸️  [Non-interactive mode] Continuing...")
    
    def demo_web_interface_info(self):
        """Show information about the web interface."""
        self.console.print(Panel.fit("🌐 Web Interface Demo", style="bold cyan"))
        
        self.console.print("🚀 [bold]Selene Web Interface Features:[/bold]\n")
        
        features = [
            ("📊 Dashboard", "Real-time system monitoring and statistics"),
            ("🤖 Content Processing", "Web-based AI content processing with all tasks"),
            ("🔍 Vector Search", "Interactive search interface for knowledge base"),
            ("📁 File Monitoring", "Web control for file monitoring system"),
            ("⚙️ Configuration", "Add/remove watched directories via web UI"),
            ("🎯 Template Management", "Full CRUD operations for prompt templates"),
            ("📈 Analytics", "Template usage statistics and performance metrics")
        ]
        
        for feature, description in features:
            self.console.print(f"  {feature}: {description}")
        
        self.console.print("\n🔧 [bold]To start the web interface:[/bold]")
        self.console.print("  selene web")
        self.console.print("  # Then visit: http://127.0.0.1:8000")
        
        self.console.print("\n📖 [bold]API Documentation:[/bold]")
        self.console.print("  http://127.0.0.1:8000/api/docs")
        
        if self.interactive:
            if Confirm.ask("\n🚀 Would you like to see a template management example?"):
                self.demo_template_api_example()
        else:
            self.console.print("\n🚀 [Non-interactive mode] Showing template management example...")
            self.demo_template_api_example()
        
        if self.interactive:
            input("\n⏸️  Press Enter to continue...")
        else:
            self.console.print("\n⏸️  [Non-interactive mode] Continuing...")
    
    def demo_template_api_example(self):
        """Show example of template API usage."""
        self.console.print("\n🎯 [bold]Template API Example:[/bold]")
        
        # Show how to create a custom template
        example_template = {
            "name": "Code Review Template",
            "description": "Template for code review analysis",
            "category": "analysis", 
            "template": """Please review the following code:

{code}

Review Requirements:
- Check for {focus_areas}
- Provide specific feedback
- Suggest improvements
- Rate overall quality (1-10)

Code Review:""",
            "variables": [
                {
                    "name": "code",
                    "description": "Code to review",
                    "required": True
                },
                {
                    "name": "focus_areas",
                    "description": "Areas to focus review on",
                    "required": False,
                    "default_value": "security, performance, and maintainability"
                }
            ],
            "tags": ["code", "review", "development"],
            "author": "Demo User"
        }
        
        self.console.print(Panel(
            json.dumps(example_template, indent=2),
            title="POST /api/templates - Create Custom Template",
            border_style="green"
        ))
        
        # Show template rendering example
        render_request = {
            "template_id": "template-uuid-here",
            "variables": {
                "code": "def process_data(data): return data.upper()",
                "focus_areas": "error handling and input validation"
            }
        }
        
        self.console.print(Panel(
            json.dumps(render_request, indent=2),
            title="POST /api/templates/render - Render Template",
            border_style="blue"
        ))
    
    def show_feature_summary(self):
        """Show comprehensive feature summary."""
        self.console.print(Panel.fit("🎯 Selene Feature Summary", style="bold yellow"))
        
        features = {
            "🤖 AI Processing": [
                "Local Ollama integration (privacy-first)",
                "OpenAI fallback support",
                "Multiple processing tasks (summarize, enhance, analyze)",
                "Template-based prompts with variables"
            ],
            "🎯 Prompt Templates (SMS-33)": [
                "11 built-in professional templates",
                "Custom template creation and management",
                "Variable system with validation",
                "Usage analytics and optimization"
            ],
            "🗄️ Vector Database": [
                "Local ChromaDB storage",
                "Semantic search capabilities", 
                "Document embedding and retrieval",
                "Metadata filtering and organization"
            ],
            "🌐 Web Interface": [
                "Modern responsive dashboard",
                "Complete REST API",
                "Real-time monitoring",
                "Template management UI"
            ],
            "📁 File Monitoring": [
                "Automatic file processing",
                "Configurable watch directories",
                "Processing queue management",
                "Background task execution"
            ],
            "🔧 Integration": [
                "JIRA project management",
                "Git workflow automation",
                "CLI and web interfaces",
                "Extensible processor architecture"
            ]
        }
        
        for category, items in features.items():
            self.console.print(f"\n{category}")
            for item in items:
                self.console.print(f"  ✅ {item}")
        
        self.console.print(f"\n🏆 [bold green]Selene: Your Complete Local-First AI Second Brain![/bold green]")
    
    def cleanup(self):
        """Clean up demo files."""
        import shutil
        
        self.console.print("\n🧹 [bold]Cleaning up demo files...[/bold]")
        
        cleanup_paths = [
            "demo_chroma_db",
            "demo_prompt_templates"
        ]
        
        for path in cleanup_paths:
            if Path(path).exists():
                if Path(path).is_dir():
                    shutil.rmtree(path)
                else:
                    Path(path).unlink()
                self.console.print(f"  🗑️ Removed: {path}")
        
        self.console.print("✅ Cleanup complete!")
    
    async def run_demo(self):
        """Run the complete Selene demo."""
        self.show_header()
        
        # Check prerequisites
        if not self.check_prerequisites():
            return
        
        # Initialize systems
        if not await self.initialize_systems():
            return
        
        # Run demo sections
        try:
            self.demo_prompt_templates()
            await self.demo_ai_processing()
            await self.demo_vector_database()
            self.demo_web_interface_info()
            self.show_feature_summary()
            
        except KeyboardInterrupt:
            self.console.print("\n\n⏹️ Demo interrupted by user")
        except Exception as e:
            self.console.print(f"\n\n❌ Demo error: {e}")
        finally:
            if self.interactive:
                if Confirm.ask("\n🧹 Clean up demo files?", default=True):
                    self.cleanup()
            else:
                self.console.print("\n🧹 [Non-interactive mode] Cleaning up demo files...")
                self.cleanup()
        
        # Final message
        self.console.print("\n" + "="*60)
        self.console.print("🎉 [bold green]Selene Demo Complete![/bold green]")
        self.console.print("\n🚀 Next steps:")
        self.console.print("  • Start web interface: selene web")
        self.console.print("  • Process your content: selene process --file your_file.txt")
        self.console.print("  • Explore templates: Check the web interface at /api/docs")
        self.console.print("\n📖 Documentation: Check CLAUDE.md for full usage guide")
        self.console.print("="*60)


def main():
    """Main demo entry point."""
    if len(sys.argv) > 1 and sys.argv[1] in ["-h", "--help", "help"]:
        print(__doc__)
        return
    
    # Check for non-interactive mode
    interactive = not ("--non-interactive" in sys.argv or os.getenv("SELENE_DEMO_NON_INTERACTIVE"))
    demo = SeleneDemo(interactive=interactive)
    
    try:
        asyncio.run(demo.run_demo())
    except KeyboardInterrupt:
        print("\n\nDemo interrupted. Goodbye! 👋")
    except Exception as e:
        print(f"Demo failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()