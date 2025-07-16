"""
Main ChatAgent class for SELENE conversational AI agent.

This agent can interact with Obsidian vaults through natural language,
providing AI-powered note management and organization capabilities.
"""

import asyncio
import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from loguru import logger
from rich.console import Console
from rich.markdown import Markdown
from rich.panel import Panel
from rich.table import Table

from ..processors.ollama_processor import OllamaProcessor
from .config import ChatConfig
from .state import ConversationState
from .tools.base import BaseTool, ToolRegistry, ToolResult, ToolStatus


class ChatAgent:
    """
    SELENE Conversational AI Agent for Obsidian Vault Management.
    
    This agent provides natural language interaction with Obsidian vaults,
    similar to how Claude Code interacts with codebases.
    """
    
    def __init__(self, config: Optional[ChatConfig] = None):
        """
        Initialize the chat agent.
        
        Args:
            config: Chat configuration. If None, loads from default location.
        """
        self.config = config or ChatConfig.from_file()
        self.console = Console() if self.config.rich_formatting else None
        
        # Core components
        self.tool_registry = ToolRegistry()
        self.conversation_state = ConversationState(self.config)
        self.ai_processor = None
        
        # Agent state
        self._initialized = False
        self._current_vault_path: Optional[Path] = None
        
    async def initialize(self) -> bool:
        """
        Initialize the agent and all its components.
        
        Returns:
            True if initialization successful, False otherwise.
        """
        logger.info("🤖 Initializing SELENE Chat Agent...")
        
        try:
            # Validate configuration
            config_issues = self.config.validate()
            if config_issues:
                logger.error(f"Configuration issues: {'; '.join(config_issues)}")
                return False
                
            # Initialize AI processor
            self.ai_processor = OllamaProcessor()
            logger.debug("AI processor initialized")
            
            # Initialize conversation state
            if self.config.conversation_memory:
                await self.conversation_state.initialize()
                logger.debug("Conversation memory initialized")
                
            # Set up vault path
            if self.config.vault_path:
                vault_path = self.config.get_vault_path()
                if vault_path and vault_path.exists():
                    self._current_vault_path = vault_path
                    logger.info(f"Using configured vault: {vault_path}")
                else:
                    logger.warning(f"Configured vault path does not exist: {self.config.vault_path}")
                    
            # Auto-discover vaults if needed
            if not self._current_vault_path and self.config.auto_discover_vaults:
                discovered = self.config.discover_vaults()
                if discovered:
                    self._current_vault_path = discovered[0]
                    logger.info(f"Auto-discovered vault: {self._current_vault_path}")
                    
            # Load and enable tools
            await self._load_tools()
            
            self._initialized = True
            logger.info("✅ Chat agent initialized successfully")
            
            # Show initialization summary
            if self.console:
                self._show_initialization_summary()
                
            return True
            
        except Exception as e:
            logger.error(f"Failed to initialize chat agent: {e}")
            return False
            
    async def _load_tools(self) -> None:
        """Load and register all available tools."""
        # Import tools here to avoid circular imports
        from .tools.vault_tools import ReadNoteTool, WriteNoteTool, UpdateNoteTool, ListNotesTool
        from .tools.search_tools import SearchNotesTool, VectorSearchTool
        from .tools.ai_tools import ProcessNoteTool
        
        # Register all tools
        tools = [
            ReadNoteTool(self._current_vault_path),
            WriteNoteTool(self._current_vault_path),
            UpdateNoteTool(self._current_vault_path),
            ListNotesTool(self._current_vault_path),
            SearchNotesTool(self._current_vault_path),
            VectorSearchTool(),
            ProcessNoteTool()
        ]
        
        for tool in tools:
            self.tool_registry.register(tool)
            
        # Enable configured tools
        enabled_count = self.tool_registry.enable_tools(self.config.enabled_tools)
        logger.debug(f"Enabled {enabled_count}/{len(tools)} tools")
        
    def _show_initialization_summary(self) -> None:
        """Show initialization summary with rich formatting."""
        if not self.console:
            return
            
        # Create summary table
        table = Table(title="🤖 SELENE Chat Agent - Ready")
        table.add_column("Component", style="cyan")
        table.add_column("Status", style="green")
        table.add_column("Details", style="dim")
        
        # Add rows
        table.add_row("Vault", "✅ Ready", str(self._current_vault_path) if self._current_vault_path else "No vault configured")
        table.add_row("AI Processor", "✅ Ready", f"{self.config.default_processor} ({self.config.default_model})")
        table.add_row("Memory", "✅ Ready" if self.config.conversation_memory else "⏸️  Disabled", "Conversation history saved")
        table.add_row("Tools", "✅ Ready", f"{len(self.tool_registry.list_tools())} enabled")
        
        self.console.print(table)
        self.console.print("\n💬 You can now chat with your vault! Type 'help' for available commands.\n")
        
    async def chat(self, message: str) -> str:
        """
        Process a chat message and return the agent's response.
        
        Args:
            message: User message
            
        Returns:
            Agent's response
        """
        if not self._initialized:
            return "❌ Agent not initialized. Please run initialize() first."
            
        try:
            # Add user message to conversation
            await self.conversation_state.add_message("user", message)
            
            # Process the message
            response = await self._process_message(message)
            
            # Add agent response to conversation
            await self.conversation_state.add_message("assistant", response)
            
            return response
            
        except Exception as e:
            error_msg = f"Error processing message: {e}"
            logger.error(error_msg)
            return f"❌ {error_msg}"
            
    async def _process_message(self, message: str) -> str:
        """
        Process a user message and generate a response.
        
        Args:
            message: User message
            
        Returns:
            Agent response
        """
        # Check for special commands
        if message.lower().strip() in ["help", "/help"]:
            return self._generate_help_message()
        elif message.lower().strip() in ["tools", "/tools"]:
            return self._generate_tools_message()
        elif message.lower().strip() in ["vault", "/vault"]:
            return self._generate_vault_info()
        elif message.lower().strip() in ["exit", "quit", "/exit", "/quit"]:
            return "👋 Goodbye! Chat session ended."
            
        # Get conversation context
        context = await self.conversation_state.get_context(self.config.context_window_size)
        
        # Prepare AI prompt with tools and context
        system_prompt = self._build_system_prompt()
        user_prompt = self._build_user_prompt(message, context)
        
        # Get AI response with tool calling
        response = await self._get_ai_response(system_prompt, user_prompt)
        
        return response
        
    def _build_system_prompt(self) -> str:
        """Build system prompt with tool information."""
        vault_info = f"Current vault: {self._current_vault_path}" if self._current_vault_path else "No vault configured"
        
        tools_info = "Available tools:\n"
        for tool_name in self.tool_registry.list_tools():
            tool = self.tool_registry.get_tool(tool_name)
            tools_info += f"- {tool.name}: {tool.description}\n"
            
        return f"""You are SELENE, an AI assistant that helps manage Obsidian vaults through natural language conversation.

{vault_info}

You can help users:
- Read, write, and update notes
- Search through notes using keywords or semantic search
- Enhance notes with AI processing (summarize, extract insights, generate questions)
- Organize and manage vault structure
- Answer questions about note contents

{tools_info}

When users ask you to perform actions, use the appropriate tools. Always be helpful, accurate, and respectful of the user's content and vault organization.

If you need to modify files, explain what you're doing and ask for confirmation when appropriate."""

    def _build_user_prompt(self, message: str, context: List[Dict[str, Any]]) -> str:
        """Build user prompt with conversation context."""
        if not context:
            return message
            
        context_str = "\n".join([
            f"{msg['role']}: {msg['content']}" 
            for msg in context[-self.config.context_window_size:]
        ])
        
        return f"""Previous conversation:
{context_str}

Current message: {message}"""

    async def _get_ai_response(self, system_prompt: str, user_prompt: str) -> str:
        """
        Get AI response with tool calling support.
        
        Args:
            system_prompt: System prompt with instructions
            user_prompt: User prompt with message and context
            
        Returns:
            AI response
        """
        try:
            # For now, use simple AI processing without function calling
            # TODO: Implement proper function calling when Ollama supports it
            
            full_prompt = f"{system_prompt}\n\nUser: {user_prompt}\n\nAssistant:"
            
            # Check if the message contains tool requests
            tool_response = await self._detect_and_execute_tools(user_prompt)
            if tool_response:
                return tool_response
                
            # Otherwise, use AI for general conversation
            result = await self.ai_processor.process(
                content=full_prompt,
                task="enhance"  # Use enhance for general conversation
            )
            
            if result.success:
                return result.content
            else:
                return f"❌ AI processing failed: {result.error}"
                
        except Exception as e:
            logger.error(f"AI response generation failed: {e}")
            return f"❌ Sorry, I encountered an error processing your request: {e}"
            
    async def _detect_and_execute_tools(self, message: str) -> Optional[str]:
        """
        Detect tool usage in natural language and execute tools.
        
        Args:
            message: User message
            
        Returns:
            Tool execution result or None if no tools detected
        """
        message_lower = message.lower()
        
        # Simple pattern matching for tool detection
        # TODO: Replace with proper NLP/function calling
        
        if any(word in message_lower for word in ["read", "show", "open", "display"]) and any(word in message_lower for word in ["note", "file"]):
            # Extract note name/path
            note_pattern = r'"([^"]+)"|\b(\w+\.md)\b|note(?:\s+named?)?\s+([^\s,]+)'
            match = re.search(note_pattern, message, re.IGNORECASE)
            if match:
                note_name = match.group(1) or match.group(2) or match.group(3)
                result = await self.tool_registry.execute_tool("read_note", note_path=note_name)
                return self._format_tool_result(result, f"Reading note: {note_name}")
                
        elif any(word in message_lower for word in ["create", "write", "new"]) and "note" in message_lower:
            # Extract note name and content
            create_pattern = r'create.*note.*"([^"]+)"'
            match = re.search(create_pattern, message, re.IGNORECASE)
            if match:
                note_name = match.group(1)
                content = f"# {note_name}\n\nCreated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"
                result = await self.tool_registry.execute_tool("write_note", note_path=f"{note_name}.md", content=content)
                return self._format_tool_result(result, f"Creating note: {note_name}")
                
        elif any(word in message_lower for word in ["search", "find", "look for"]):
            # Extract search query
            search_patterns = [
                r'search for "([^"]+)"',
                r'find "([^"]+)"',
                r'look for "([^"]+)"',
                r'search\s+(.+?)(?:\s+in|\s*$)',
                r'find\s+(.+?)(?:\s+in|\s*$)'
            ]
            
            for pattern in search_patterns:
                match = re.search(pattern, message, re.IGNORECASE)
                if match:
                    query = match.group(1).strip()
                    result = await self.tool_registry.execute_tool("vector_search", query=query, results=5)
                    return self._format_tool_result(result, f"Searching for: {query}")
                    
        elif any(word in message_lower for word in ["list", "show all", "what notes"]):
            result = await self.tool_registry.execute_tool("list_notes")
            return self._format_tool_result(result, "Listing notes")
            
        return None
        
    def _format_tool_result(self, result: ToolResult, action: str) -> str:
        """Format tool execution result for display."""
        if result.is_success:
            if self.console:
                # Rich formatting for successful results
                if isinstance(result.content, list):
                    content = "\n".join([f"• {item}" for item in result.content])
                else:
                    content = str(result.content)
                    
                panel = Panel(
                    content,
                    title=f"✅ {action}",
                    border_style="green"
                )
                
                # Capture rich output as string
                with self.console.capture() as capture:
                    self.console.print(panel)
                return capture.get()
            else:
                return f"✅ {action}\n\n{result.content}"
                
        elif result.requires_confirmation:
            return f"⚠️ {action} requires confirmation:\n{result.content}"
            
        else:
            return f"❌ {action} failed: {result.error_message}"
            
    def _generate_help_message(self) -> str:
        """Generate help message with available commands."""
        help_text = """# 🤖 SELENE Chat Agent Help

## Natural Language Commands
You can interact with your vault using natural language. Examples:

**Reading Notes:**
- "Show me the meeting notes"
- "Read the note called 'project ideas'"
- "Open research.md"

**Creating Notes:**
- "Create a note called 'Weekly Planning'"
- "Write a new note about machine learning"

**Searching:**
- "Search for notes about AI"
- "Find anything related to project management"
- "Look for notes containing 'meeting'"

**Listing:**
- "List all my notes"
- "What notes do I have?"
- "Show all files"

## Special Commands
- `help` or `/help` - Show this help message
- `tools` or `/tools` - List available tools
- `vault` or `/vault` - Show vault information
- `exit` or `/quit` - End chat session

## AI Processing
Ask me to enhance, summarize, or analyze your notes:
- "Summarize my meeting notes"
- "Extract insights from my research"
- "Generate questions from this brainstorm"
"""
        
        if self.console:
            return Markdown(help_text).markup
        return help_text
        
    def _generate_tools_message(self) -> str:
        """Generate message showing available tools."""
        if not self.console:
            tools_info = "Available Tools:\n"
            for tool_name in self.tool_registry.list_tools():
                tool = self.tool_registry.get_tool(tool_name)
                tools_info += f"• {tool.name}: {tool.description}\n"
            return tools_info
            
        # Rich table for tools
        table = Table(title="🛠️ Available Tools")
        table.add_column("Tool", style="cyan")
        table.add_column("Description", style="white")
        table.add_column("Status", style="green")
        
        for tool_name in self.tool_registry.list_tools():
            tool = self.tool_registry.get_tool(tool_name)
            status = "✅ Enabled" if self.tool_registry.is_enabled(tool_name) else "⏸️ Disabled"
            table.add_row(tool.name, tool.description, status)
            
        with self.console.capture() as capture:
            self.console.print(table)
        return capture.get()
        
    def _generate_vault_info(self) -> str:
        """Generate vault information message."""
        if not self._current_vault_path:
            return "ℹ️ No vault is currently configured."
            
        vault_path = self._current_vault_path
        
        # Count files
        md_files = list(vault_path.glob("**/*.md"))
        total_files = len(md_files)
        
        # Check for .obsidian folder
        obsidian_folder = vault_path / ".obsidian"
        is_obsidian = obsidian_folder.exists()
        
        info = f"""# 📁 Vault Information

**Path:** `{vault_path}`
**Type:** {'Obsidian Vault' if is_obsidian else 'Markdown Folder'}
**Notes:** {total_files} markdown files
**Status:** ✅ Ready

## Recent Notes
"""

        # Add recent notes
        recent_notes = sorted(md_files, key=lambda f: f.stat().st_mtime, reverse=True)[:5]
        for note in recent_notes:
            rel_path = note.relative_to(vault_path)
            mod_time = datetime.fromtimestamp(note.stat().st_mtime).strftime('%Y-%m-%d %H:%M')
            info += f"• {rel_path} (modified {mod_time})\n"
            
        if self.console:
            return Markdown(info).markup
        return info
        
    async def set_vault(self, vault_path: str) -> bool:
        """
        Set the active vault path.
        
        Args:
            vault_path: Path to vault directory
            
        Returns:
            True if vault set successfully, False otherwise.
        """
        path = Path(vault_path).expanduser().resolve()
        
        if not self.config.is_valid_vault(str(path)):
            logger.error(f"Invalid vault path: {path}")
            return False
            
        self._current_vault_path = path
        
        # Reload tools with new vault path
        await self._load_tools()
        
        logger.info(f"Vault set to: {path}")
        return True
        
    def get_vault_path(self) -> Optional[Path]:
        """Get current vault path."""
        return self._current_vault_path
        
    def is_initialized(self) -> bool:
        """Check if agent is initialized."""
        return self._initialized
        
    async def shutdown(self) -> None:
        """Shutdown the agent and clean up resources."""
        logger.info("🔄 Shutting down chat agent...")
        
        if self.conversation_state and self.config.auto_save_conversations:
            await self.conversation_state.save()
            
        self._initialized = False
        logger.info("✅ Chat agent shutdown complete")