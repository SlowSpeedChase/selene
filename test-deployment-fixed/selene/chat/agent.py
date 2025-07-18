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
from .nlp.language_processor import LanguageProcessor


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
        self.language_processor = None
        
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
            
            # Initialize language processor
            self.language_processor = LanguageProcessor()
            logger.debug("Language processor initialized")
            
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
                    
            # Update language processor with vault path
            self.language_processor.set_vault_path(self._current_vault_path)
                    
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
            
        # Process message with enhanced NLP
        processing_result = self.language_processor.process_message(message)
        
        # Handle the processing result
        response = await self._handle_processing_result(processing_result, message)
        
        # Update conversation context
        self.language_processor.update_context(message, processing_result, response)
        
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

    async def _handle_processing_result(self, processing_result, message: str) -> str:
        """
        Handle the NLP processing result and execute appropriate actions.
        
        Args:
            processing_result: Result from language processor
            message: Original user message
            
        Returns:
            Agent response
        """
        try:
            # Check if we can execute the tool directly
            if processing_result.is_executable:
                return await self._execute_tool_from_result(processing_result)
                
            # Check if we need confirmation
            elif processing_result.needs_confirmation:
                return await self._request_confirmation(processing_result)
                
            # Check if we have missing parameters
            elif processing_result.missing_parameters:
                return self._request_missing_parameters(processing_result)
                
            # Check if confidence is too low
            elif not processing_result.is_confident:
                return self._handle_low_confidence(processing_result, message)
                
            # Fall back to AI conversation
            else:
                return await self._get_ai_response(processing_result, message)
                
        except Exception as e:
            logger.error(f"Error handling processing result: {e}")
            return f"❌ Sorry, I encountered an error processing your request: {e}"
            
    async def _execute_tool_from_result(self, processing_result) -> str:
        """Execute tool from processing result."""
        tool_name = processing_result.tool_name
        parameters = processing_result.parameters
        
        # Handle special case for AI processing tools
        if tool_name == "ai_process" and "note_path" in parameters:
            # Read note content first
            note_path = parameters["note_path"]
            read_result = await self.tool_registry.execute_tool("read_note", note_path=note_path)
            if read_result.is_success:
                # Replace note_path with actual content
                parameters["content"] = read_result.content
                del parameters["note_path"]
            else:
                return self._format_tool_result(read_result, f"Reading note: {note_path}")
        
        # Execute the tool
        result = await self.tool_registry.execute_tool(tool_name, **parameters)
        
        # Format and return result
        action_description = self._get_action_description(tool_name, parameters)
        return self._format_tool_result(result, action_description)
        
    async def _request_confirmation(self, processing_result) -> str:
        """Request user confirmation for the action."""
        tool_name = processing_result.tool_name
        parameters = processing_result.parameters
        
        action_description = self._get_action_description(tool_name, parameters)
        
        confirmation_msg = f"⚠️ I want to {action_description.lower()}. This will modify your vault.\n\n"
        confirmation_msg += "Parameters:\n"
        for key, value in parameters.items():
            confirmation_msg += f"• {key}: {value}\n"
        confirmation_msg += "\nDo you want to proceed? (yes/no)"
        
        return confirmation_msg
        
    def _request_missing_parameters(self, processing_result) -> str:
        """Request missing parameters from user."""
        missing = processing_result.missing_parameters
        suggestions = processing_result.suggestions
        
        msg = f"❓ I need more information to proceed:\n\n"
        
        for param in missing:
            msg += f"• Missing: {param}\n"
            
        if suggestions:
            msg += f"\n💡 Suggestions:\n"
            for suggestion in suggestions:
                msg += f"• {suggestion}\n"
                
        msg += "\nPlease provide the missing information and try again."
        
        return msg
        
    def _handle_low_confidence(self, processing_result, message: str) -> str:
        """Handle low confidence processing results."""
        intent = processing_result.intent
        confidence = processing_result.confidence
        suggestions = processing_result.suggestions
        
        msg = f"🤔 I'm not sure what you want to do (confidence: {confidence:.1%}).\n\n"
        
        if intent.value != "unknown":
            msg += f"I think you want to: {intent.value.replace('_', ' ')}\n\n"
            
        if suggestions:
            msg += "💡 Suggestions:\n"
            for suggestion in suggestions:
                msg += f"• {suggestion}\n"
        else:
            msg += "Try rephrasing your request or use commands like:\n"
            msg += "• 'read my notes about X'\n"
            msg += "• 'create a note called Y'\n"
            msg += "• 'search for Z'\n"
            
        return msg
        
    async def _get_ai_response(self, processing_result, message: str) -> str:
        """Get AI response for general conversation."""
        try:
            # Get conversation context
            context = self.language_processor.get_conversation_context(3)
            
            # Build prompt with context
            system_prompt = self._build_system_prompt()
            user_prompt = self._build_user_prompt(message, context)
            
            full_prompt = f"{system_prompt}\n\nUser: {user_prompt}\n\nAssistant:"
            
            # Use AI for general conversation
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
            
    def _get_action_description(self, tool_name: str, parameters: Dict[str, Any]) -> str:
        """Get human-readable description of the action."""
        if tool_name == "read_note":
            return f"Reading note: {parameters.get('note_path', 'unknown')}"
        elif tool_name == "write_note":
            return f"Creating note: {parameters.get('note_path', 'unknown')}"
        elif tool_name == "update_note":
            return f"Updating note: {parameters.get('note_path', 'unknown')}"
        elif tool_name == "search_notes":
            return f"Searching for: {parameters.get('query', 'unknown')}"
        elif tool_name == "vector_search":
            return f"Semantic search for: {parameters.get('query', 'unknown')}"
        elif tool_name == "list_notes":
            return "Listing notes"
        elif tool_name == "ai_process":
            task = parameters.get('task', 'processing')
            return f"AI {task.replace('_', ' ')}"
        else:
            return f"Executing {tool_name}"
        
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
        
        # Update language processor with new vault path
        if self.language_processor:
            self.language_processor.set_vault_path(path)
        
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