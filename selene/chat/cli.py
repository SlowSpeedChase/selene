"""
Enhanced CLI Chat Interface

Provides a sophisticated command-line interface for interacting with SELENE
through natural language conversations. Includes command shortcuts, help system,
rich formatting, and session management.
"""

import os
import sys
import asyncio
import json
import uuid
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
import signal

from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.columns import Columns
from rich.markdown import Markdown
from rich.syntax import Syntax
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.prompt import Prompt, Confirm
from rich.text import Text
from rich.layout import Layout
from rich.live import Live
from loguru import logger

from .enhanced_agent import EnhancedChatAgent
from .config import ChatConfig


class CLIChatInterface:
    """Enhanced CLI chat interface with advanced features."""
    
    def __init__(self, config: ChatConfig, debug: bool = False):
        """Initialize CLI chat interface.
        
        Args:
            config: Chat configuration
            debug: Enable debug logging
        """
        self.config = config
        self.debug = debug
        self.console = Console()
        self.agent: Optional[EnhancedChatAgent] = None
        self.session_id = f"cli_session_{uuid.uuid4().hex[:8]}"
        self.user_id = f"cli_user_{uuid.uuid4().hex[:8]}"
        self.running = False
        
        # Command shortcuts and aliases
        self.shortcuts = {
            '/h': 'help',
            '/q': 'quit',
            '/exit': 'quit',
            '/clear': 'clear',
            '/status': 'status',
            '/stats': 'stats',
            '/features': 'features',
            '/commands': 'commands',
            '/history': 'history',
            '/save': 'save',
            '/load': 'load',
            '/debug': 'debug',
            '/vault': 'vault',
            '/search': 'search',
            '/connections': 'connections',
        }
        
        # Available commands
        self.available_commands = {
            'help': 'Show available commands and usage',
            'quit': 'Exit the chat session',
            'clear': 'Clear the console screen',
            'status': 'Show chat agent status',
            'stats': 'Show session statistics',
            'features': 'Show enhanced features status',
            'commands': 'List all available commands',
            'history': 'Show conversation history',
            'save': 'Save current session',
            'load': 'Load previous session',
            'debug': 'Toggle debug mode',
            'vault': 'Show vault information',
            'search': 'Search vault contents',
            'connections': 'Show note connections',
        }
        
        # Session data
        self.session_data = {
            'session_id': self.session_id,
            'user_id': self.user_id,
            'start_time': datetime.now().isoformat(),
            'messages': [],
            'statistics': {
                'total_messages': 0,
                'commands_used': 0,
                'response_times': []
            }
        }
        
        # Setup signal handlers
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
    
    def _signal_handler(self, signum, frame):
        """Handle interrupt signals gracefully."""
        self.console.print("\n🛑 Interrupt received. Shutting down gracefully...")
        self.running = False
        if self.agent:
            asyncio.create_task(self.agent.shutdown())
        sys.exit(0)
    
    async def initialize(self) -> bool:
        """Initialize the chat interface and agent.
        
        Returns:
            True if initialization successful, False otherwise
        """
        try:
            # Initialize enhanced agent
            self.agent = EnhancedChatAgent(self.config)
            
            if not await self.agent.initialize(user_id=self.user_id):
                self.console.print("[red]❌ Failed to initialize enhanced chat agent[/red]")
                return False
            
            # Load session history if available
            await self._load_session_history()
            
            return True
            
        except Exception as e:
            self.console.print(f"[red]❌ Initialization failed: {e}[/red]")
            if self.debug:
                import traceback
                self.console.print(traceback.format_exc())
            return False
    
    async def run(self) -> None:
        """Run the interactive chat interface."""
        if not await self.initialize():
            return
        
        self.running = True
        
        # Display welcome message
        self._display_welcome()
        
        # Main chat loop
        try:
            while self.running:
                try:
                    # Get user input with rich prompt
                    user_input = self._get_user_input()
                    
                    if not user_input:
                        continue
                    
                    # Process input
                    await self._process_input(user_input)
                    
                except (EOFError, KeyboardInterrupt):
                    break
                    
        except Exception as e:
            self.console.print(f"[red]❌ Chat error: {e}[/red]")
            if self.debug:
                import traceback
                self.console.print(traceback.format_exc())
        
        finally:
            await self._shutdown()
    
    def _display_welcome(self) -> None:
        """Display enhanced welcome message."""
        welcome_panel = Panel(
            "[bold cyan]🚀 SELENE Enhanced Chat Agent[/bold cyan]\n\n"
            "✨ [green]Advanced Features Active:[/green]\n"
            "  • Smart suggestions and context awareness\n"
            "  • Conversation flows and guided workflows\n"
            "  • Natural language understanding\n"
            "  • Command shortcuts and aliases\n"
            "  • Rich formatting and visualization\n\n"
            "[yellow]Quick Start:[/yellow]\n"
            "  • Type naturally to chat with SELENE\n"
            "  • Use [bold]/help[/bold] for commands\n"
            "  • Use [bold]/features[/bold] for capabilities\n"
            "  • Use [bold]/quit[/bold] to exit\n\n"
            f"[dim]Session ID: {self.session_id}[/dim]",
            title="🧠 Second Brain Assistant",
            border_style="cyan",
            padding=(1, 2)
        )
        
        self.console.print(welcome_panel)
        self.console.print()
    
    def _get_user_input(self) -> str:
        """Get user input with enhanced prompt."""
        try:
            # Show typing indicator briefly
            with self.console.status("[dim]Ready for input...[/dim]", spinner="dots"):
                pass
            
            # Get input
            prompt_text = Text()
            prompt_text.append("You", style="bold blue")
            prompt_text.append(": ", style="dim")
            
            user_input = Prompt.ask(prompt_text, console=self.console).strip()
            
            # Update session statistics
            self.session_data['statistics']['total_messages'] += 1
            
            return user_input
            
        except (EOFError, KeyboardInterrupt):
            return ""
    
    async def _process_input(self, user_input: str) -> None:
        """Process user input and generate response.
        
        Args:
            user_input: User input string
        """
        start_time = datetime.now()
        
        # Check for command shortcuts
        if user_input.startswith('/'):
            await self._handle_command(user_input)
            return
        
        # Check for command aliases
        if user_input.lower() in ['help', 'quit', 'exit', 'clear', 'status', 'stats', 'features', 'commands']:
            await self._handle_command(f"/{user_input}")
            return
        
        # Process as chat message
        try:
            # Show typing indicator
            with self.console.status("[dim]SELENE is thinking...[/dim]", spinner="dots"):
                response = await self.agent.chat(user_input)
            
            # Calculate response time
            response_time = (datetime.now() - start_time).total_seconds()
            self.session_data['statistics']['response_times'].append(response_time)
            
            # Store message in session
            self.session_data['messages'].append({
                'timestamp': start_time.isoformat(),
                'user': user_input,
                'selene': response,
                'response_time': response_time
            })
            
            # Display response with enhanced formatting
            self._display_response(response)
            
        except Exception as e:
            self.console.print(f"[red]❌ Processing failed: {e}[/red]")
            if self.debug:
                import traceback
                self.console.print(traceback.format_exc())
    
    async def _handle_command(self, command: str) -> None:
        """Handle special commands.
        
        Args:
            command: Command string (with / prefix)
        """
        # Remove / prefix and get command
        cmd = command[1:].lower().strip()
        
        # Map shortcuts to full commands
        if f"/{cmd}" in self.shortcuts:
            cmd = self.shortcuts[f"/{cmd}"]
        
        # Update statistics
        self.session_data['statistics']['commands_used'] += 1
        
        # Execute command
        if cmd == 'help':
            self._show_help()
        elif cmd == 'quit':
            self.running = False
        elif cmd == 'clear':
            self.console.clear()
        elif cmd == 'status':
            await self._show_status()
        elif cmd == 'stats':
            self._show_statistics()
        elif cmd == 'features':
            await self._show_features()
        elif cmd == 'commands':
            self._show_commands()
        elif cmd == 'history':
            self._show_history()
        elif cmd == 'save':
            await self._save_session()
        elif cmd == 'load':
            await self._load_session()
        elif cmd == 'debug':
            self._toggle_debug()
        elif cmd == 'vault':
            self._show_vault_info()
        elif cmd == 'search':
            await self._search_vault()
        elif cmd == 'connections':
            await self._show_connections()
        else:
            self.console.print(f"[red]❌ Unknown command: {cmd}[/red]")
            self.console.print("Type [bold]/help[/bold] for available commands")
    
    def _display_response(self, response: str) -> None:
        """Display agent response with enhanced formatting.
        
        Args:
            response: Response text to display
        """
        # Create response panel
        response_panel = Panel(
            response,
            title="🤖 SELENE",
            title_align="left",
            border_style="green",
            padding=(1, 2)
        )
        
        self.console.print(response_panel)
        self.console.print()
    
    def _show_help(self) -> None:
        """Show help information."""
        help_table = Table(title="🛠️ Available Commands", show_header=True)
        help_table.add_column("Command", style="cyan", width=15)
        help_table.add_column("Shortcut", style="yellow", width=10)
        help_table.add_column("Description", style="white")
        
        # Add commands with shortcuts
        for cmd, desc in self.available_commands.items():
            shortcut = ""
            for short, full in self.shortcuts.items():
                if full == cmd:
                    shortcut = short
                    break
            help_table.add_row(f"/{cmd}", shortcut, desc)
        
        self.console.print(help_table)
        self.console.print()
        
        # Show usage examples
        examples_panel = Panel(
            "[bold]Usage Examples:[/bold]\n\n"
            "• [cyan]Natural chat:[/cyan] \"Show me my daily notes\"\n"
            "• [cyan]Commands:[/cyan] /help, /status, /quit\n"
            "• [cyan]Shortcuts:[/cyan] /h (help), /q (quit), /s (status)\n"
            "• [cyan]Vault ops:[/cyan] /search, /connections, /vault\n"
            "• [cyan]Session:[/cyan] /save, /load, /history",
            title="💡 Quick Reference",
            border_style="blue"
        )
        
        self.console.print(examples_panel)
        self.console.print()
    
    async def _show_status(self) -> None:
        """Show chat agent status."""
        if not self.agent:
            self.console.print("[red]❌ Agent not initialized[/red]")
            return
        
        status_table = Table(title="🔍 Agent Status", show_header=True)
        status_table.add_column("Component", style="cyan")
        status_table.add_column("Status", style="green")
        status_table.add_column("Details", style="white")
        
        # Agent status
        status_table.add_row("Agent", "✅ Active", f"Enhanced features enabled")
        status_table.add_row("Vault", "✅ Connected", f"Path: {self.config.vault_path}")
        status_table.add_row("Memory", "✅ Enabled" if self.config.conversation_memory else "❌ Disabled", "Conversation context")
        status_table.add_row("Session", "✅ Active", f"ID: {self.session_id}")
        
        # Show tool status
        if hasattr(self.agent, 'tool_registry'):
            tool_count = len(self.agent.tool_registry.tools)
            status_table.add_row("Tools", f"✅ {tool_count} loaded", "Vault interaction tools")
        
        self.console.print(status_table)
        self.console.print()
    
    def _show_statistics(self) -> None:
        """Show session statistics."""
        stats = self.session_data['statistics']
        
        stats_table = Table(title="📊 Session Statistics", show_header=True)
        stats_table.add_column("Metric", style="cyan")
        stats_table.add_column("Value", style="green")
        
        # Basic stats
        stats_table.add_row("Total Messages", str(stats['total_messages']))
        stats_table.add_row("Commands Used", str(stats['commands_used']))
        stats_table.add_row("Session Duration", self._format_duration())
        
        # Response time stats
        if stats['response_times']:
            avg_time = sum(stats['response_times']) / len(stats['response_times'])
            stats_table.add_row("Avg Response Time", f"{avg_time:.2f}s")
            stats_table.add_row("Fastest Response", f"{min(stats['response_times']):.2f}s")
            stats_table.add_row("Slowest Response", f"{max(stats['response_times']):.2f}s")
        
        self.console.print(stats_table)
        self.console.print()
    
    async def _show_features(self) -> None:
        """Show enhanced features status."""
        if not self.agent:
            self.console.print("[red]❌ Agent not initialized[/red]")
            return
        
        features_table = Table(title="✨ Enhanced Features", show_header=True)
        features_table.add_column("Feature", style="cyan")
        features_table.add_column("Status", style="green")
        features_table.add_column("Description", style="white")
        
        # Check feature availability
        features_table.add_row("Smart Suggestions", "✅ Active", "Context-aware recommendations")
        features_table.add_row("Conversation Flows", "✅ Active", "Guided multi-step workflows")
        features_table.add_row("Pattern Learning", "✅ Active", "User behavior adaptation")
        features_table.add_row("Rich Formatting", "✅ Active", "Tables, panels, and syntax highlighting")
        features_table.add_row("Command Shortcuts", "✅ Active", "Quick command access")
        features_table.add_row("Session Persistence", "✅ Active", "Save/load conversations")
        
        self.console.print(features_table)
        self.console.print()
    
    def _show_commands(self) -> None:
        """Show available commands in a compact format."""
        commands_text = Text()
        commands_text.append("Available Commands:\n", style="bold cyan")
        
        for cmd, desc in self.available_commands.items():
            commands_text.append(f"/{cmd:<12}", style="yellow")
            commands_text.append(f" - {desc}\n", style="white")
        
        self.console.print(Panel(commands_text, title="📋 Command Reference", border_style="blue"))
        self.console.print()
    
    def _show_history(self) -> None:
        """Show conversation history."""
        if not self.session_data['messages']:
            self.console.print("[yellow]No conversation history yet[/yellow]")
            return
        
        history_panel = Panel(
            self._format_history(),
            title=f"📚 Conversation History ({len(self.session_data['messages'])} messages)",
            border_style="magenta"
        )
        
        self.console.print(history_panel)
        self.console.print()
    
    def _format_history(self) -> str:
        """Format conversation history for display."""
        history_text = ""
        for i, msg in enumerate(self.session_data['messages'][-5:], 1):  # Show last 5 messages
            timestamp = datetime.fromisoformat(msg['timestamp']).strftime("%H:%M:%S")
            history_text += f"[dim]{timestamp}[/dim] [bold blue]You:[/bold blue] {msg['user'][:50]}...\n"
            history_text += f"[dim]{timestamp}[/dim] [bold green]SELENE:[/bold green] {msg['selene'][:50]}...\n\n"
        
        return history_text
    
    async def _save_session(self) -> None:
        """Save current session to file."""
        try:
            # Create sessions directory
            sessions_dir = Path("sessions")
            sessions_dir.mkdir(exist_ok=True)
            
            # Save session data
            session_file = sessions_dir / f"session_{self.session_id}.json"
            with open(session_file, 'w') as f:
                json.dump(self.session_data, f, indent=2)
            
            self.console.print(f"[green]✅ Session saved to {session_file}[/green]")
            
        except Exception as e:
            self.console.print(f"[red]❌ Failed to save session: {e}[/red]")
    
    async def _load_session(self) -> None:
        """Load previous session from file."""
        try:
            sessions_dir = Path("sessions")
            if not sessions_dir.exists():
                self.console.print("[yellow]No saved sessions found[/yellow]")
                return
            
            # List available sessions
            session_files = list(sessions_dir.glob("session_*.json"))
            if not session_files:
                self.console.print("[yellow]No saved sessions found[/yellow]")
                return
            
            # Show available sessions
            self.console.print("Available sessions:")
            for i, session_file in enumerate(session_files, 1):
                self.console.print(f"{i}. {session_file.name}")
            
            # Get user choice
            choice = Prompt.ask("Select session to load", choices=[str(i) for i in range(1, len(session_files) + 1)])
            
            # Load selected session
            selected_file = session_files[int(choice) - 1]
            with open(selected_file, 'r') as f:
                loaded_data = json.load(f)
            
            # Merge with current session
            self.session_data['messages'].extend(loaded_data.get('messages', []))
            
            self.console.print(f"[green]✅ Loaded session from {selected_file.name}[/green]")
            
        except Exception as e:
            self.console.print(f"[red]❌ Failed to load session: {e}[/red]")
    
    async def _load_session_history(self) -> None:
        """Load session history if available."""
        try:
            sessions_dir = Path("sessions")
            if not sessions_dir.exists():
                return
            
            # Look for recent sessions
            session_files = list(sessions_dir.glob("session_*.json"))
            if not session_files:
                return
            
            # Load most recent session
            latest_session = max(session_files, key=lambda f: f.stat().st_mtime)
            
            # Only load if less than 24 hours old
            if (datetime.now().timestamp() - latest_session.stat().st_mtime) < 86400:
                with open(latest_session, 'r') as f:
                    loaded_data = json.load(f)
                
                # Restore some session data
                self.session_data['messages'] = loaded_data.get('messages', [])[-10:]  # Last 10 messages
                
        except Exception as e:
            logger.debug(f"Failed to load session history: {e}")
    
    def _toggle_debug(self) -> None:
        """Toggle debug mode."""
        self.debug = not self.debug
        status = "enabled" if self.debug else "disabled"
        self.console.print(f"[yellow]Debug mode {status}[/yellow]")
    
    def _show_vault_info(self) -> None:
        """Show vault information."""
        vault_table = Table(title="📁 Vault Information", show_header=True)
        vault_table.add_column("Property", style="cyan")
        vault_table.add_column("Value", style="green")
        
        vault_table.add_row("Vault Path", str(self.config.vault_path))
        vault_table.add_row("Exists", "✅ Yes" if Path(self.config.vault_path).exists() else "❌ No")
        
        if Path(self.config.vault_path).exists():
            # Count files
            vault_files = list(Path(self.config.vault_path).rglob("*.md"))
            vault_table.add_row("Markdown Files", str(len(vault_files)))
        
        self.console.print(vault_table)
        self.console.print()
    
    async def _search_vault(self) -> None:
        """Search vault contents."""
        if not self.agent:
            self.console.print("[red]❌ Agent not initialized[/red]")
            return
        
        query = Prompt.ask("Enter search query")
        if not query:
            return
        
        try:
            # Use agent to search
            with self.console.status(f"[dim]Searching for '{query}'...[/dim]", spinner="dots"):
                response = await self.agent.chat(f"search {query}")
            
            self._display_response(response)
            
        except Exception as e:
            self.console.print(f"[red]❌ Search failed: {e}[/red]")
    
    async def _show_connections(self) -> None:
        """Show note connections."""
        if not self.agent:
            self.console.print("[red]❌ Agent not initialized[/red]")
            return
        
        try:
            with self.console.status("[dim]Analyzing connections...[/dim]", spinner="dots"):
                response = await self.agent.chat("show connections")
            
            self._display_response(response)
            
        except Exception as e:
            self.console.print(f"[red]❌ Connection analysis failed: {e}[/red]")
    
    def _format_duration(self) -> str:
        """Format session duration."""
        start_time = datetime.fromisoformat(self.session_data['start_time'])
        duration = datetime.now() - start_time
        
        hours = duration.seconds // 3600
        minutes = (duration.seconds % 3600) // 60
        seconds = duration.seconds % 60
        
        if hours > 0:
            return f"{hours}h {minutes}m {seconds}s"
        elif minutes > 0:
            return f"{minutes}m {seconds}s"
        else:
            return f"{seconds}s"
    
    async def _shutdown(self) -> None:
        """Shutdown the chat interface."""
        try:
            # Save session
            await self._save_session()
            
            # Shutdown agent
            if self.agent:
                await self.agent.shutdown()
            
            # Display goodbye message
            goodbye_panel = Panel(
                f"[bold green]👋 Thanks for using SELENE![/bold green]\n\n"
                f"Session Summary:\n"
                f"• Messages: {self.session_data['statistics']['total_messages']}\n"
                f"• Commands: {self.session_data['statistics']['commands_used']}\n"
                f"• Duration: {self._format_duration()}\n\n"
                f"[dim]Session saved automatically[/dim]",
                title="🚪 Goodbye",
                border_style="cyan"
            )
            
            self.console.print(goodbye_panel)
            
        except Exception as e:
            self.console.print(f"[red]❌ Shutdown error: {e}[/red]")


async def run_cli_chat(vault: Optional[str] = None,
                      config_file: Optional[str] = None,
                      no_memory: bool = False,
                      debug: bool = False) -> None:
    """Run the enhanced CLI chat interface.
    
    Args:
        vault: Path to vault directory
        config_file: Path to configuration file
        no_memory: Disable conversation memory
        debug: Enable debug logging
    """
    try:
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
        
        # Create and run CLI interface
        cli = CLIChatInterface(config, debug=debug)
        await cli.run()
        
    except Exception as e:
        console = Console()
        console.print(f"[red]❌ CLI chat failed: {e}[/red]")
        if debug:
            import traceback
            console.print(traceback.format_exc())
        raise