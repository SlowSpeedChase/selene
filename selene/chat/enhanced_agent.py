"""
Enhanced Chat Agent for SMS-38 Advanced Chat Features.

This is the enhanced version of the chat agent that integrates all
advanced features including smart tool selection, context-aware responses,
conversation flows, and intelligent suggestions.
"""

import asyncio
import json
import uuid
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
from .nlp.enhanced_language_processor import EnhancedLanguageProcessor, EnhancedProcessingResult
from .response.context_aware_generator import (
    ContextAwareResponseGenerator, 
    GeneratedResponse, 
    ResponseContext
)
from .tools.smart_tool_selector import SmartToolSelector, ToolSelection
from .flow.conversation_flow_manager import (
    ConversationFlowManager, 
    FlowExecution, 
    FlowState
)


class EnhancedChatAgent:
    """
    Enhanced conversational AI agent with advanced chat features.
    
    Key improvements over the base agent:
    - Enhanced natural language processing with fuzzy matching
    - Smart tool selection and parameter inference
    - Context-aware response generation with personalization
    - Multi-turn conversation workflows
    - Advanced suggestions and clarifications
    - Learning from user patterns
    """
    
    def __init__(self, config: Optional[ChatConfig] = None):
        """
        Initialize the enhanced chat agent.
        
        Args:
            config: Chat configuration. If None, loads from default location.
        """
        self.config = config or ChatConfig.from_file()
        self.console = Console() if self.config.rich_formatting else None
        
        # Core components (enhanced versions)
        self.tool_registry = ToolRegistry()
        self.conversation_state = ConversationState(self.config)
        self.ai_processor = None
        
        # Enhanced components
        self.language_processor = None
        self.response_generator = None
        self.tool_selector = None
        self.flow_manager = None
        
        # Agent state
        self._initialized = False
        self._current_vault_path: Optional[Path] = None
        self._current_user_id: Optional[str] = None
        self._active_flow_id: Optional[str] = None
        
        # Feature flags
        self.features = {
            "enhanced_nlp": True,
            "smart_tool_selection": True,
            "context_aware_responses": True,
            "conversation_flows": True,
            "learning_enabled": True,
            "advanced_suggestions": True
        }
        
        # Performance tracking
        self.session_stats = {
            "messages_processed": 0,
            "tools_executed": 0,
            "flows_started": 0,
            "successful_responses": 0,
            "clarification_requests": 0,
            "session_start": datetime.now()
        }
        
    async def initialize(self, user_id: Optional[str] = None) -> bool:
        """
        Initialize the enhanced agent and all its components.
        
        Args:
            user_id: Optional user identifier for personalization
            
        Returns:
            True if initialization successful, False otherwise.
        """
        logger.info("🚀 Initializing Enhanced SELENE Chat Agent...")
        
        try:
            # Store user ID
            self._current_user_id = user_id
            
            # Validate configuration
            config_issues = self.config.validate()
            if config_issues:
                logger.error(f"Configuration issues: {'; '.join(config_issues)}")
                return False
                
            # Initialize AI processor
            self.ai_processor = OllamaProcessor()
            logger.debug("AI processor initialized")
            
            # Initialize enhanced language processor
            self.language_processor = EnhancedLanguageProcessor()
            logger.debug("Enhanced language processor initialized")
            
            # Initialize conversation state
            if self.config.conversation_memory:
                await self.conversation_state.initialize()
                logger.debug("Conversation memory initialized")
                
            # Set up vault path
            vault_path = await self._setup_vault_path()
            if vault_path:
                self._current_vault_path = vault_path
                self.language_processor.set_vault_path(vault_path)
                
            # Initialize response generator
            self.response_generator = ContextAwareResponseGenerator(self._current_vault_path)
            logger.debug("Context-aware response generator initialized")
            
            # Load and enable tools
            await self._load_tools()
            
            # Initialize smart tool selector
            self.tool_selector = SmartToolSelector(self.tool_registry, self._current_vault_path)
            logger.debug("Smart tool selector initialized")
            
            # Initialize conversation flow manager
            self.flow_manager = ConversationFlowManager(self._current_vault_path)
            logger.debug("Conversation flow manager initialized")
            
            self._initialized = True
            logger.info("✅ Enhanced chat agent initialized successfully")
            
            # Show initialization summary
            if self.console:
                self._show_enhanced_initialization_summary()
                
            return True
            
        except Exception as e:
            logger.error(f"Failed to initialize enhanced chat agent: {e}")
            return False
            
    async def chat(self, message: str) -> str:
        """
        Process a chat message with enhanced capabilities.
        
        Args:
            message: User message
            
        Returns:
            Agent's response
        """
        if not self._initialized:
            return "❌ Enhanced agent not initialized. Please run initialize() first."
            
        try:
            self.session_stats["messages_processed"] += 1
            
            # Add user message to conversation
            await self.conversation_state.add_message("user", message)
            
            # Check for active conversation flow first
            if self._active_flow_id:
                response = await self._process_flow_message(message)
            else:
                # Regular enhanced processing
                response = await self._process_enhanced_message(message)
                
            # Add agent response to conversation
            await self.conversation_state.add_message("assistant", response)
            
            return response
            
        except Exception as e:
            error_msg = f"Error processing message: {e}"
            logger.error(error_msg)
            return f"❌ {error_msg}"
            
    async def _process_enhanced_message(self, message: str) -> str:
        """Process message with full enhanced capabilities."""
        
        # Step 1: Enhanced language processing
        processing_result = self.language_processor.process_message(
            message, user_id=self._current_user_id
        )
        
        # Check for special commands first
        special_response = self._handle_special_commands(message, processing_result)
        if special_response:
            return special_response
            
        # Step 2: Check if we should start a conversation flow
        flow_response = await self._check_flow_initiation(processing_result, message)
        if flow_response:
            return flow_response
            
        # Step 3: Smart tool selection (if not handled by flow)
        if processing_result.is_executable or processing_result.tool_name:
            tool_selection = self.tool_selector.select_tool(
                processing_result,
                context=await self._build_context(),
                user_id=self._current_user_id
            )
            
            # Execute tool if selection is confident
            if tool_selection.confidence > 0.6 and not tool_selection.validation_errors:
                response = await self._execute_selected_tool(tool_selection, processing_result)
                if response:
                    return response
                    
        # Step 4: Generate context-aware response
        context = await self._build_response_context()
        generated_response = self.response_generator.generate_response(
            processing_result, context
        )
        
        # Step 5: Format and return response
        return self._format_enhanced_response(generated_response, processing_result)
        
    async def _process_flow_message(self, message: str) -> str:
        """Process message within an active conversation flow."""
        
        if not self._active_flow_id:
            return "❌ No active flow to process"
            
        try:
            # Get enhanced processing for flow input
            processing_result = self.language_processor.process_message(
                message, user_id=self._current_user_id
            )
            
            # Process through flow manager
            success, response, next_action = self.flow_manager.process_flow_input(
                self._active_flow_id, message, processing_result
            )
            
            # Handle flow actions
            if next_action:
                if next_action == "advance_step":
                    self.flow_manager.advance_flow(self._active_flow_id)
                elif next_action == "cancel_flow":
                    self.flow_manager.cancel_flow(self._active_flow_id, "user_cancelled")
                    self._active_flow_id = None
                elif next_action.startswith("advance_to:"):
                    next_step = next_action.split(":", 1)[1]
                    self.flow_manager.advance_flow(self._active_flow_id, next_step)
                elif next_action == "flow_error":
                    self.flow_manager.cancel_flow(self._active_flow_id, "error")
                    self._active_flow_id = None
                    
            # Check if flow completed
            execution = self.flow_manager.active_executions.get(self._active_flow_id)
            if execution and execution.state == FlowState.COMPLETED:
                self._active_flow_id = None
                
            # Return response
            if response:
                return response.content
            else:
                return "✅ Flow step processed successfully."
                
        except Exception as e:
            logger.error(f"Error processing flow message: {e}")
            self.flow_manager.cancel_flow(self._active_flow_id, f"error: {e}")
            self._active_flow_id = None
            return f"❌ Flow processing error: {e}"
            
    async def _check_flow_initiation(
        self, 
        processing_result: EnhancedProcessingResult, 
        message: str
    ) -> Optional[str]:
        """Check if message should initiate a conversation flow."""
        
        # Check for flow trigger patterns
        message_lower = message.lower()
        
        # Note creation flow
        if any(phrase in message_lower for phrase in [
            "create a note", "new note", "make a note", "write a note"
        ]) and "guide" in message_lower or "help" in message_lower:
            execution = self.flow_manager.start_flow(
                "create_note_flow", 
                user_id=self._current_user_id,
                initial_context={"trigger_message": message}
            )
            if execution:
                self._active_flow_id = execution.execution_id
                self.session_stats["flows_started"] += 1
                return "🚀 Starting guided note creation! What should we call your new note?"
                
        # Research flow
        elif any(phrase in message_lower for phrase in [
            "research", "investigate", "study", "explore"
        ]) and any(phrase in message_lower for phrase in ["help", "guide", "assist"]):
            execution = self.flow_manager.start_flow(
                "research_flow",
                user_id=self._current_user_id,
                initial_context={"trigger_message": message}
            )
            if execution:
                self._active_flow_id = execution.execution_id
                self.session_stats["flows_started"] += 1
                return "🔍 Starting research assistant! What topic would you like to research?"
                
        return None
        
    async def _execute_selected_tool(
        self, 
        selection: ToolSelection, 
        processing_result: EnhancedProcessingResult
    ) -> Optional[str]:
        """Execute the selected tool with enhanced error handling."""
        
        try:
            start_time = datetime.now()
            
            # Merge parameters from selection and processing result
            final_params = {**processing_result.parameters, **selection.inferred_parameters}
            
            # Execute tool
            result = await self.tool_registry.execute_tool(selection.selected_tool, **final_params)
            
            # Calculate execution time
            execution_time = (datetime.now() - start_time).total_seconds()
            
            # Record tool performance
            self.tool_selector.record_tool_execution_result(
                selection.selected_tool,
                result.is_success,
                execution_time,
                result.error_message if hasattr(result, 'error_message') else None,
                await self._build_context()
            )
            
            # Update session stats
            self.session_stats["tools_executed"] += 1
            if result.is_success:
                self.session_stats["successful_responses"] += 1
                
            # Generate enhanced response
            context = await self._build_response_context()
            generated_response = self.response_generator.generate_response(
                processing_result, context, result
            )
            
            return self._format_enhanced_response(generated_response, processing_result)
            
        except Exception as e:
            logger.error(f"Tool execution failed: {e}")
            
            # Record failure
            self.tool_selector.record_tool_execution_result(
                selection.selected_tool, False, 0.0, str(e)
            )
            
            return f"❌ Error executing {selection.selected_tool}: {e}"
            
    async def _build_context(self) -> Dict[str, Any]:
        """Build context information for tool selection."""
        
        context = {
            "vault_path": str(self._current_vault_path) if self._current_vault_path else None,
            "user_id": self._current_user_id,
            "session_stats": self.session_stats
        }
        
        # Add vault information
        if self._current_vault_path and self._current_vault_path.exists():
            md_files = list(self._current_vault_path.glob("**/*.md"))
            context.update({
                "total_notes": len(md_files),
                "recent_files": [f.name for f in sorted(md_files, key=lambda x: x.stat().st_mtime, reverse=True)[:5]],
                "vault_type": "obsidian" if (self._current_vault_path / ".obsidian").exists() else "markdown"
            })
            
        # Add time context
        now = datetime.now()
        context["time_context"] = {
            "hour": now.hour,
            "time_of_day": "morning" if 6 <= now.hour < 12 else 
                          "afternoon" if 12 <= now.hour < 18 else 
                          "evening" if 18 <= now.hour < 22 else "night",
            "timestamp": now.isoformat()
        }
        
        return context
        
    async def _build_response_context(self) -> ResponseContext:
        """Build response context for enhanced response generation."""
        
        # Get conversation history
        history = []
        if self.config.conversation_memory:
            recent_messages = await self.conversation_state.get_recent_messages(5)
            history = [
                {
                    "role": msg.get("role", "unknown"),
                    "content": msg.get("content", ""),
                    "timestamp": msg.get("timestamp", ""),
                    "intent": msg.get("metadata", {}).get("intent")
                }
                for msg in recent_messages
            ]
            
        # Get vault info
        vault_info = {}
        if self._current_vault_path:
            vault_info = await self._get_vault_info()
            
        # Get user preferences (from learning data)
        user_preferences = {}
        if self._current_user_id and hasattr(self.tool_selector, 'user_tool_preferences'):
            user_prefs = self.tool_selector.user_tool_preferences.get(self._current_user_id, {})
            user_preferences = dict(user_prefs.most_common(10))
            
        # Get recent actions
        recent_actions = []
        # This could be enhanced to track recent tool executions
        
        # Get time context
        time_context = (await self._build_context())["time_context"]
        
        return ResponseContext(
            user_id=self._current_user_id,
            conversation_history=history,
            current_vault_info=vault_info,
            user_preferences=user_preferences,
            recent_actions=recent_actions,
            time_context=time_context
        )
        
    async def _get_vault_info(self) -> Dict[str, Any]:
        """Get current vault information."""
        
        if not self._current_vault_path or not self._current_vault_path.exists():
            return {}
            
        try:
            md_files = list(self._current_vault_path.glob("**/*.md"))
            recent_files = sorted(md_files, key=lambda x: x.stat().st_mtime, reverse=True)[:5]
            
            return {
                "path": str(self._current_vault_path),
                "note_count": len(md_files),
                "recent_files": [f.name for f in recent_files],
                "is_obsidian": (self._current_vault_path / ".obsidian").exists(),
                "total_size": sum(f.stat().st_size for f in md_files if f.exists())
            }
            
        except Exception as e:
            logger.warning(f"Error getting vault info: {e}")
            return {}
            
    def _handle_special_commands(
        self, 
        message: str, 
        processing_result: EnhancedProcessingResult
    ) -> Optional[str]:
        """Handle special commands with enhanced features."""
        
        message_lower = message.lower().strip()
        
        # Enhanced help command
        if message_lower in ["help", "/help", "?"]:
            return self._generate_enhanced_help()
            
        # Flow management commands
        elif message_lower in ["flows", "/flows"]:
            return self._generate_flows_info()
            
        # Statistics command
        elif message_lower in ["stats", "/stats", "statistics"]:
            return self._generate_statistics()
            
        # Feature status command
        elif message_lower in ["features", "/features"]:
            return self._generate_features_status()
            
        # Learning data command
        elif message_lower in ["patterns", "/patterns", "learning"]:
            return self._generate_learning_info()
            
        # Reset conversation
        elif message_lower in ["reset", "/reset", "clear"]:
            return self._reset_conversation()
            
        return None
        
    def _format_enhanced_response(
        self, 
        response: GeneratedResponse, 
        processing_result: EnhancedProcessingResult
    ) -> str:
        """Format enhanced response with rich features."""
        
        if not self.console:
            # Plain text formatting
            formatted = response.content
            if response.suggestions:
                formatted += f"\n\n💡 Suggestions:\n"
                for suggestion in response.suggestions:
                    formatted += f"• {suggestion}\n"
            return formatted
            
        # Rich formatting
        try:
            # Main content
            if response.response_type == "success":
                panel_style = "green"
                title = "✅ Success"
            elif response.response_type == "error":
                panel_style = "red"
                title = "❌ Error"
            elif response.response_type == "clarification":
                panel_style = "yellow"
                title = "❓ Clarification Needed"
            else:
                panel_style = "blue"
                title = "ℹ️ Information"
                
            # Create main panel
            main_panel = Panel(
                response.content,
                title=title,
                border_style=panel_style
            )
            
            # Capture main content
            with self.console.capture() as capture:
                self.console.print(main_panel)
                
                # Add suggestions if available
                if response.suggestions:
                    suggestions_text = "\n".join([f"• {s}" for s in response.suggestions])
                    suggestions_panel = Panel(
                        suggestions_text,
                        title="💡 Suggestions",
                        border_style="dim"
                    )
                    self.console.print(suggestions_panel)
                    
                # Add alternatives if available from processing result
                if (hasattr(processing_result, 'alternative_interpretations') and 
                    processing_result.alternative_interpretations):
                    
                    alts_text = "\n".join([
                        f"• {intent.value.replace('_', ' ')} (confidence: {conf:.1%})"
                        for intent, conf in processing_result.alternative_interpretations
                    ])
                    alt_panel = Panel(
                        alts_text,
                        title="🔄 Alternative Interpretations",
                        border_style="dim"
                    )
                    self.console.print(alt_panel)
                    
            return capture.get()
            
        except Exception as e:
            logger.warning(f"Rich formatting failed: {e}")
            return response.content
            
    def _generate_enhanced_help(self) -> str:
        """Generate enhanced help message."""
        
        help_content = """# 🚀 Enhanced SELENE Chat Agent

## Natural Language Commands
Talk to me naturally! I understand context and can help with:

**Reading & Writing:**
- "Show me my daily notes" or "Read the meeting summary"
- "Create a note about project planning"
- "Update my todo list with new tasks"

**Searching & Exploring:**
- "Find notes about machine learning"
- "Search for anything related to meetings"
- "What notes contain the word 'deadline'?"

**AI Processing:**
- "Summarize my research notes"
- "Extract key insights from this brainstorm"
- "Generate questions about this topic"

## Advanced Features
- **Smart Suggestions**: I learn your patterns and suggest relevant actions
- **Context Awareness**: I remember our conversation and your preferences
- **Multi-step Workflows**: Start guided processes with "help me create..." or "guide me through..."
- **Fuzzy Matching**: I can find files even with partial or approximate names

## Special Commands
- `help` - This help message
- `flows` - Show available conversation flows
- `stats` - Show session statistics and performance
- `features` - Show enabled advanced features
- `patterns` - Show learned patterns and preferences
- `reset` - Clear conversation and start fresh

## Example Conversations
Try saying:
- "Help me create a comprehensive research note"
- "I want to organize my project notes better"
- "Find everything related to my current work"
- "Summarize all my meeting notes from this week"
"""

        if self.console:
            return Markdown(help_content).markup
        return help_content
        
    def _generate_flows_info(self) -> str:
        """Generate information about available flows."""
        
        available_flows = self.flow_manager.get_available_flows()
        active_flows = self.flow_manager.get_active_flows(self._current_user_id)
        
        info = "# 🔄 Conversation Flows\n\n"
        
        if available_flows:
            info += "## Available Flows\n"
            for flow in available_flows:
                info += f"- **{flow['name']}**: {flow['description']} ({flow['steps_count']} steps)\n"
                
        if active_flows:
            info += "\n## Active Flows\n"
            for flow in active_flows:
                info += f"- {flow['flow_name']}: Step {flow['current_step']} ({flow['progress']:.0%} complete)\n"
        else:
            info += "\n*No active flows*\n"
            
        info += "\n**Tip**: Say things like 'help me create a note' or 'guide me through research' to start flows."
        
        return info
        
    def _generate_statistics(self) -> str:
        """Generate session and performance statistics."""
        
        session_duration = datetime.now() - self.session_stats["session_start"]
        
        stats_content = f"""# 📊 Session Statistics

**Current Session:**
- Messages processed: {self.session_stats['messages_processed']}
- Tools executed: {self.session_stats['tools_executed']}
- Successful responses: {self.session_stats['successful_responses']}
- Flows started: {self.session_stats['flows_started']}
- Session duration: {session_duration.total_seconds() / 60:.1f} minutes

**Enhanced Features:**
"""

        # Add tool selection stats
        if self.tool_selector:
            selection_stats = self.tool_selector.get_selection_stats()
            stats_content += f"- Tool selections: {selection_stats.get('total_selections', 0)}\n"
            stats_content += f"- Parameter inferences: {selection_stats.get('parameter_inferences', 0)}\n"
            
        # Add language processing stats
        if self.language_processor:
            processing_stats = self.language_processor.get_enhanced_stats()
            stats_content += f"- Fuzzy file matches: {processing_stats.get('fuzzy_matches', 0)}\n"
            stats_content += f"- Learning updates: {processing_stats.get('learning_updates', 0)}\n"
            
        # Add flow stats
        if self.flow_manager:
            flow_stats = self.flow_manager.get_flow_statistics()
            stats_content += f"- Active flows: {flow_stats.get('active_flows', 0)}\n"
            stats_content += f"- Completed flows: {flow_stats.get('total_flows_completed', 0)}\n"
            
        return stats_content
        
    def _generate_features_status(self) -> str:
        """Generate status of enhanced features."""
        
        features_content = "# 🎛️ Enhanced Features Status\n\n"
        
        for feature, enabled in self.features.items():
            status = "✅ Enabled" if enabled else "❌ Disabled"
            feature_name = feature.replace('_', ' ').title()
            features_content += f"- **{feature_name}**: {status}\n"
            
        features_content += "\n**Components Initialized:**\n"
        features_content += f"- Enhanced Language Processor: {'✅' if self.language_processor else '❌'}\n"
        features_content += f"- Context-Aware Response Generator: {'✅' if self.response_generator else '❌'}\n"
        features_content += f"- Smart Tool Selector: {'✅' if self.tool_selector else '❌'}\n"
        features_content += f"- Conversation Flow Manager: {'✅' if self.flow_manager else '❌'}\n"
        
        return features_content
        
    def _generate_learning_info(self) -> str:
        """Generate information about learned patterns."""
        
        if not self._current_user_id:
            return "ℹ️ No user ID set - learning data not available."
            
        info = "# 🧠 Learning & Patterns\n\n"
        
        # Tool preferences
        if self.tool_selector and hasattr(self.tool_selector, 'user_tool_preferences'):
            prefs = self.tool_selector.user_tool_preferences.get(self._current_user_id, {})
            if prefs:
                info += "**Tool Usage Patterns:**\n"
                for tool_intent, count in prefs.most_common(5):
                    info += f"- {tool_intent}: {count} times\n"
            else:
                info += "*No tool usage patterns learned yet*\n"
                
        # Language patterns
        if self.language_processor and hasattr(self.language_processor, 'user_patterns'):
            patterns = self.language_processor.get_user_patterns(self._current_user_id)
            if patterns:
                info += "\n**Language Patterns:**\n"
                for pattern, count in Counter(patterns).most_common(5):
                    info += f"- {pattern}: {count} times\n"
            else:
                info += "\n*No language patterns learned yet*\n"
                
        info += "\n**Note**: The agent learns from your interactions to provide better suggestions and responses."
        
        return info
        
    def _reset_conversation(self) -> str:
        """Reset conversation state and learning data."""
        
        try:
            # Reset conversation state
            if self.conversation_state:
                asyncio.create_task(self.conversation_state.clear_history())
                
            # Cancel active flows
            if self._active_flow_id:
                self.flow_manager.cancel_flow(self._active_flow_id, "user_reset")
                self._active_flow_id = None
                
            # Reset session stats
            self.session_stats = {
                "messages_processed": 0,
                "tools_executed": 0,
                "flows_started": 0,
                "successful_responses": 0,
                "clarification_requests": 0,
                "session_start": datetime.now()
            }
            
            return "🔄 Conversation reset successfully. Starting fresh!"
            
        except Exception as e:
            logger.error(f"Error resetting conversation: {e}")
            return f"❌ Error resetting conversation: {e}"
            
    async def _setup_vault_path(self) -> Optional[Path]:
        """Setup and validate vault path."""
        
        # Use configured path if available
        if self.config.vault_path:
            vault_path = self.config.get_vault_path()
            if vault_path and vault_path.exists():
                return vault_path
            else:
                logger.warning(f"Configured vault path does not exist: {self.config.vault_path}")
                
        # Auto-discover vaults if enabled
        if self.config.auto_discover_vaults:
            discovered = self.config.discover_vaults()
            if discovered:
                return discovered[0]
                
        return None
        
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
        
    def _show_enhanced_initialization_summary(self) -> None:
        """Show enhanced initialization summary."""
        
        if not self.console:
            return
            
        # Create enhanced summary table
        table = Table(title="🚀 Enhanced SELENE Chat Agent - Ready")
        table.add_column("Component", style="cyan")
        table.add_column("Status", style="green")
        table.add_column("Details", style="dim")
        
        # Add rows
        table.add_row(
            "Vault", 
            "✅ Ready" if self._current_vault_path else "⚠️ Not configured", 
            str(self._current_vault_path) if self._current_vault_path else "No vault configured"
        )
        table.add_row(
            "Enhanced NLP", 
            "✅ Active", 
            "Fuzzy matching, parameter inference, pattern learning"
        )
        table.add_row(
            "Smart Tools", 
            "✅ Active", 
            f"{len(self.tool_registry.list_tools())} tools with intelligent selection"
        )
        table.add_row(
            "Context Responses", 
            "✅ Active", 
            "Personalized, context-aware response generation"
        )
        table.add_row(
            "Conversation Flows", 
            "✅ Active", 
            f"{len(self.flow_manager.get_available_flows())} workflow templates available"
        )
        table.add_row(
            "User Learning", 
            "✅ Active" if self._current_user_id else "⏸️ No User ID", 
            "Pattern learning and personalization"
        )
        
        self.console.print(table)
        self.console.print("\n🎯 Enhanced Features:")
        self.console.print("• Natural language understanding with context")
        self.console.print("• Smart suggestions and clarifications")
        self.console.print("• Multi-turn conversation workflows")
        self.console.print("• Learning from your interaction patterns")
        self.console.print("\n💬 Try: 'help me create a comprehensive note' or 'guide me through research'")
        self.console.print("🔧 Type 'features' to see all enhanced capabilities\n")
        
    async def set_vault(self, vault_path: str) -> bool:
        """Set the active vault path with enhanced validation."""
        
        path = Path(vault_path).expanduser().resolve()
        
        if not self.config.is_valid_vault(str(path)):
            logger.error(f"Invalid vault path: {path}")
            return False
            
        # Update all components with new vault path
        self._current_vault_path = path
        
        if self.language_processor:
            self.language_processor.set_vault_path(path)
            
        if self.response_generator:
            self.response_generator.vault_path = path
            
        if self.tool_selector:
            self.tool_selector.vault_path = path
            
        if self.flow_manager:
            self.flow_manager.vault_path = path
            
        # Reload tools with new vault path
        await self._load_tools()
        
        logger.info(f"Enhanced agent vault set to: {path}")
        return True
        
    def get_enhanced_status(self) -> Dict[str, Any]:
        """Get comprehensive status of enhanced agent."""
        
        return {
            "initialized": self._initialized,
            "vault_path": str(self._current_vault_path) if self._current_vault_path else None,
            "user_id": self._current_user_id,
            "active_flow": self._active_flow_id,
            "features": self.features,
            "session_stats": self.session_stats,
            "components": {
                "language_processor": bool(self.language_processor),
                "response_generator": bool(self.response_generator),
                "tool_selector": bool(self.tool_selector),
                "flow_manager": bool(self.flow_manager)
            }
        }
        
    async def shutdown(self) -> None:
        """Shutdown enhanced agent and clean up resources."""
        
        logger.info("🔄 Shutting down enhanced chat agent...")
        
        # Cancel active flows
        if self._active_flow_id:
            self.flow_manager.cancel_flow(self._active_flow_id, "shutdown")
            
        # Save conversation state
        if self.conversation_state and self.config.auto_save_conversations:
            await self.conversation_state.save()
            
        # Clean up flow manager
        if self.flow_manager:
            self.flow_manager.cleanup_expired_flows()
            
        self._initialized = False
        logger.info("✅ Enhanced chat agent shutdown complete")