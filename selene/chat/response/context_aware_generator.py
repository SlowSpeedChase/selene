"""
Context-Aware Response Generator for SMS-38 Advanced Chat Features.

This module generates intelligent, context-aware responses that:
- Adapt to conversation history and user patterns
- Provide personalized suggestions and help
- Generate natural, conversational responses
- Handle complex multi-turn dialogues
- Learn from interaction patterns
"""

import json
import re
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from collections import defaultdict, deque

from loguru import logger

from ..nlp.enhanced_language_processor import EnhancedProcessingResult
from ..nlp.intent_classifier import Intent


@dataclass
class ResponseContext:
    """Context information for response generation."""
    user_id: Optional[str]
    conversation_history: List[Dict[str, Any]]
    current_vault_info: Dict[str, Any]
    user_preferences: Dict[str, Any]
    recent_actions: List[Dict[str, Any]]
    time_context: Dict[str, Any]
    

@dataclass
class GeneratedResponse:
    """Generated response with metadata."""
    content: str
    response_type: str  # informational, confirmation, error, success, clarification
    suggestions: List[str]
    follow_up_actions: List[str]
    requires_input: bool
    confidence: float
    metadata: Dict[str, Any]


class ContextAwareResponseGenerator:
    """
    Context-aware response generator that creates intelligent, personalized responses.
    
    Features:
    - Conversation history awareness
    - User pattern learning
    - Personalized suggestions
    - Natural language generation
    - Multi-turn dialogue support
    """
    
    def __init__(self, vault_path: Optional[Path] = None):
        """
        Initialize context-aware response generator.
        
        Args:
            vault_path: Current vault path for context
        """
        self.vault_path = vault_path
        
        # Response templates organized by type and context
        self.response_templates = self._load_response_templates()
        
        # User context tracking
        self.user_contexts = defaultdict(lambda: {
            "preferences": {},
            "patterns": defaultdict(int),
            "recent_history": deque(maxlen=50),
            "successful_actions": [],
            "common_files": defaultdict(int),
            "conversation_style": "helpful"  # helpful, concise, detailed
        })
        
        # Response personalization
        self.personalization_enabled = True
        self.learning_rate = 0.1
        
        # Statistics
        self.response_stats = {
            "total_responses": 0,
            "personalized_responses": 0,
            "clarification_responses": 0,
            "error_responses": 0,
            "success_responses": 0
        }
        
    def generate_response(
        self, 
        processing_result: EnhancedProcessingResult,
        context: ResponseContext,
        tool_result: Optional[Any] = None
    ) -> GeneratedResponse:
        """
        Generate a context-aware response based on processing result and context.
        
        Args:
            processing_result: Result from enhanced language processing
            context: Current conversation context
            tool_result: Optional result from tool execution
            
        Returns:
            Generated response with metadata
        """
        try:
            self.response_stats["total_responses"] += 1
            
            # Determine response type
            response_type = self._determine_response_type(processing_result, tool_result)
            
            # Generate base response
            if response_type == "clarification":
                response = self._generate_clarification_response(processing_result, context)
            elif response_type == "confirmation":
                response = self._generate_confirmation_response(processing_result, context)
            elif response_type == "success":
                response = self._generate_success_response(processing_result, context, tool_result)
            elif response_type == "error":
                response = self._generate_error_response(processing_result, context, tool_result)
            else:
                response = self._generate_informational_response(processing_result, context)
                
            # Enhance with personalization
            if self.personalization_enabled and context.user_id:
                response = self._personalize_response(response, context)
                self.response_stats["personalized_responses"] += 1
                
            # Add contextual suggestions
            response.suggestions.extend(self._generate_contextual_suggestions(processing_result, context))
            
            # Add follow-up actions
            response.follow_up_actions = self._generate_follow_up_actions(processing_result, context)
            
            # Update user context
            if context.user_id:
                self._update_user_context(context.user_id, processing_result, response)
                
            # Update statistics
            self.response_stats[f"{response_type}_responses"] += 1
            
            logger.debug(f"Generated {response_type} response with {len(response.suggestions)} suggestions")
            
            return response
            
        except Exception as e:
            logger.error(f"Response generation failed: {e}")
            return self._create_fallback_response(str(e))
            
    def _determine_response_type(
        self, 
        processing_result: EnhancedProcessingResult, 
        tool_result: Optional[Any]
    ) -> str:
        """Determine the type of response to generate."""
        
        if processing_result.needs_clarification:
            return "clarification"
        elif processing_result.needs_confirmation:
            return "confirmation"
        elif tool_result is not None:
            if hasattr(tool_result, 'is_success') and tool_result.is_success:
                return "success"
            else:
                return "error"
        elif processing_result.confidence < 0.5:
            return "clarification"
        else:
            return "informational"
            
    def _generate_clarification_response(
        self, 
        processing_result: EnhancedProcessingResult, 
        context: ResponseContext
    ) -> GeneratedResponse:
        """Generate clarification response."""
        
        # Use provided clarification question if available
        if processing_result.clarification_question:
            content = processing_result.clarification_question
        else:
            # Generate dynamic clarification
            if processing_result.has_alternatives:
                alts = [alt[0].value.replace('_', ' ') for alt in processing_result.alternative_interpretations[:2]]
                content = f"I'm not sure what you want to do. Did you mean to {' or '.join(alts)}?"
            elif processing_result.missing_parameters:
                missing = ', '.join(processing_result.missing_parameters)
                content = f"I need more information to help you. Could you specify: {missing}?"
            else:
                content = "I'm not sure what you want to do. Could you please rephrase your request?"
                
        # Add contextual help
        suggestions = []
        if processing_result.file_matches:
            suggestions.append(f"Available files: {', '.join(processing_result.file_matches[:3])}")
            
        if processing_result.suggested_completions:
            suggestions.extend(processing_result.suggested_completions[:2])
            
        return GeneratedResponse(
            content=content,
            response_type="clarification",
            suggestions=suggestions,
            follow_up_actions=[],
            requires_input=True,
            confidence=0.8,
            metadata={"clarification_type": "parameter_missing"}
        )
        
    def _generate_confirmation_response(
        self, 
        processing_result: EnhancedProcessingResult, 
        context: ResponseContext
    ) -> GeneratedResponse:
        """Generate confirmation response for destructive actions."""
        
        action = self._get_action_description(processing_result)
        
        content = f"⚠️ I want to {action}. This will modify your vault.\n\n"
        content += "Parameters:\n"
        for key, value in processing_result.parameters.items():
            if isinstance(value, str) and len(value) > 50:
                value = value[:47] + "..."
            content += f"• {key}: {value}\n"
            
        content += "\nDo you want to proceed? (yes/no)"
        
        return GeneratedResponse(
            content=content,
            response_type="confirmation",
            suggestions=["Type 'yes' to proceed", "Type 'no' to cancel"],
            follow_up_actions=["await_confirmation"],
            requires_input=True,
            confidence=0.9,
            metadata={"action": action, "parameters": processing_result.parameters}
        )
        
    def _generate_success_response(
        self, 
        processing_result: EnhancedProcessingResult, 
        context: ResponseContext,
        tool_result: Any
    ) -> GeneratedResponse:
        """Generate success response after tool execution."""
        
        action = self._get_action_description(processing_result)
        
        # Base success message
        content = f"✅ {action} completed successfully!"
        
        # Add result details if available
        if hasattr(tool_result, 'content') and tool_result.content:
            if isinstance(tool_result.content, list):
                if len(tool_result.content) > 0:
                    content += f"\n\nFound {len(tool_result.content)} items:"
                    for item in tool_result.content[:5]:  # Show first 5
                        content += f"\n• {item}"
                    if len(tool_result.content) > 5:
                        content += f"\n... and {len(tool_result.content) - 5} more"
            elif isinstance(tool_result.content, str):
                if len(tool_result.content) > 200:
                    content += f"\n\n{tool_result.content[:197]}..."
                else:
                    content += f"\n\n{tool_result.content}"
                    
        # Generate contextual suggestions
        suggestions = []
        if processing_result.intent == Intent.READ_NOTE:
            suggestions.extend([
                "Would you like me to summarize this note?",
                "Ask me questions about the content"
            ])
        elif processing_result.intent in [Intent.SEARCH_NOTES, Intent.VECTOR_SEARCH]:
            suggestions.extend([
                "Would you like to read any of these notes?",
                "Try a different search term"
            ])
        elif processing_result.intent == Intent.WRITE_NOTE:
            suggestions.extend([
                "Would you like to enhance this note with AI?",
                "Add more content to the note"
            ])
            
        return GeneratedResponse(
            content=content,
            response_type="success",
            suggestions=suggestions,
            follow_up_actions=[],
            requires_input=False,
            confidence=0.95,
            metadata={"action": action, "result_type": type(tool_result).__name__}
        )
        
    def _generate_error_response(
        self, 
        processing_result: EnhancedProcessingResult, 
        context: ResponseContext,
        tool_result: Any
    ) -> GeneratedResponse:
        """Generate error response with helpful suggestions."""
        
        action = self._get_action_description(processing_result)
        
        # Extract error message
        error_msg = "An error occurred"
        if hasattr(tool_result, 'error_message') and tool_result.error_message:
            error_msg = tool_result.error_message
        elif hasattr(tool_result, 'content') and tool_result.content:
            error_msg = str(tool_result.content)
            
        content = f"❌ Failed to {action.lower()}: {error_msg}"
        
        # Generate helpful suggestions based on error type
        suggestions = []
        if "not found" in error_msg.lower():
            if processing_result.file_matches:
                suggestions.append(f"Did you mean: {', '.join(processing_result.file_matches[:3])}?")
            suggestions.append("Check the file path and try again")
            suggestions.append("Use 'list notes' to see available files")
        elif "permission" in error_msg.lower():
            suggestions.extend([
                "Check file permissions",
                "Make sure the vault is accessible"
            ])
        else:
            suggestions.extend([
                "Try rephrasing your request",
                "Check that all required information is provided"
            ])
            
        return GeneratedResponse(
            content=content,
            response_type="error",
            suggestions=suggestions,
            follow_up_actions=["suggest_alternatives"],
            requires_input=False,
            confidence=0.8,
            metadata={"error": error_msg, "action": action}
        )
        
    def _generate_informational_response(
        self, 
        processing_result: EnhancedProcessingResult, 
        context: ResponseContext
    ) -> GeneratedResponse:
        """Generate informational response for general queries."""
        
        # Default informational content
        content = "I understand you want to work with your notes. Let me help you with that."
        
        # Customize based on intent
        if processing_result.intent == Intent.UNKNOWN:
            content = "I'm here to help you manage your notes and vault. What would you like to do?"
        elif processing_result.is_executable:
            action = self._get_action_description(processing_result)
            content = f"I'll {action.lower()} for you."
        else:
            content = "I need a bit more information to help you effectively."
            
        suggestions = processing_result.suggestions.copy()
        
        # Add general suggestions if none provided
        if not suggestions:
            suggestions.extend([
                "Try: 'read my daily notes'",
                "Try: 'search for project ideas'", 
                "Try: 'create a new note about X'"
            ])
            
        return GeneratedResponse(
            content=content,
            response_type="informational",
            suggestions=suggestions,
            follow_up_actions=[],
            requires_input=True,
            confidence=processing_result.confidence,
            metadata={"intent": processing_result.intent.value}
        )
        
    def _personalize_response(self, response: GeneratedResponse, context: ResponseContext) -> GeneratedResponse:
        """Personalize response based on user context and patterns."""
        
        if not context.user_id:
            return response
            
        user_ctx = self.user_contexts[context.user_id]
        
        # Adapt to conversation style preference
        style = user_ctx["conversation_style"]
        if style == "concise":
            response.content = self._make_concise(response.content)
        elif style == "detailed":
            response.content = self._add_details(response.content, context)
            
        # Add personalized suggestions based on patterns
        common_files = user_ctx["common_files"]
        if common_files and response.response_type in ["clarification", "informational"]:
            top_files = sorted(common_files.items(), key=lambda x: x[1], reverse=True)[:3]
            if top_files:
                file_suggestion = f"Your frequently accessed files: {', '.join([f[0] for f in top_files])}"
                if file_suggestion not in response.suggestions:
                    response.suggestions.insert(0, file_suggestion)
                    
        # Add time-based context
        if context.time_context:
            time_suggestions = self._generate_time_based_suggestions(context.time_context, user_ctx)
            response.suggestions.extend(time_suggestions)
            
        response.metadata["personalized"] = True
        return response
        
    def _generate_contextual_suggestions(
        self, 
        processing_result: EnhancedProcessingResult, 
        context: ResponseContext
    ) -> List[str]:
        """Generate contextual suggestions based on vault state and history."""
        
        suggestions = []
        
        # Vault-specific suggestions
        if context.current_vault_info:
            recent_files = context.current_vault_info.get("recent_files", [])
            if recent_files and processing_result.intent == Intent.READ_NOTE:
                suggestions.append(f"Recent files: {', '.join(recent_files[:3])}")
                
        # History-based suggestions
        if context.conversation_history:
            recent_intents = [turn.get("intent") for turn in context.conversation_history[-3:]]
            if Intent.SEARCH_NOTES.value in recent_intents and processing_result.intent == Intent.READ_NOTE:
                suggestions.append("Would you like to read one of the search results?")
                
        # Time-based suggestions
        if context.time_context:
            time_of_day = context.time_context.get("time_of_day")
            if time_of_day == "morning":
                suggestions.append("Good morning! Check your daily notes?")
            elif time_of_day == "evening":
                suggestions.append("Evening review: summarize today's notes?")
                
        return suggestions
        
    def _generate_follow_up_actions(
        self, 
        processing_result: EnhancedProcessingResult, 
        context: ResponseContext
    ) -> List[str]:
        """Generate suggested follow-up actions."""
        
        actions = []
        
        # Intent-specific follow-ups
        if processing_result.intent == Intent.READ_NOTE:
            actions.extend(["summarize", "ask_questions", "enhance"])
        elif processing_result.intent in [Intent.SEARCH_NOTES, Intent.VECTOR_SEARCH]:
            actions.extend(["read_result", "refine_search", "create_note"])
        elif processing_result.intent == Intent.WRITE_NOTE:
            actions.extend(["enhance_note", "add_tags", "link_notes"])
            
        # Context-based follow-ups
        if context.conversation_history:
            last_action = context.conversation_history[-1].get("action") if context.conversation_history else None
            if last_action == "search" and processing_result.intent != Intent.READ_NOTE:
                actions.append("read_search_result")
                
        return actions
        
    def _get_action_description(self, processing_result: EnhancedProcessingResult) -> str:
        """Get human-readable action description."""
        
        action_map = {
            Intent.READ_NOTE: "Read note",
            Intent.WRITE_NOTE: "Create note", 
            Intent.UPDATE_NOTE: "Update note",
            Intent.SEARCH_NOTES: "Search notes",
            Intent.VECTOR_SEARCH: "Search semantically",
            Intent.LIST_NOTES: "List notes",
            Intent.SUMMARIZE: "Summarize content",
            Intent.ENHANCE: "Enhance content",
            Intent.EXTRACT_INSIGHTS: "Extract insights",
            Intent.GENERATE_QUESTIONS: "Generate questions"
        }
        
        base_action = action_map.get(processing_result.intent, "Process request")
        
        # Add parameter context
        if 'note_path' in processing_result.parameters:
            note_path = processing_result.parameters['note_path']
            base_action += f" '{note_path}'"
        elif 'query' in processing_result.parameters:
            query = processing_result.parameters['query']
            base_action += f" for '{query}'"
            
        return base_action
        
    def _update_user_context(
        self, 
        user_id: str, 
        processing_result: EnhancedProcessingResult, 
        response: GeneratedResponse
    ) -> None:
        """Update user context with current interaction."""
        
        user_ctx = self.user_contexts[user_id]
        
        # Track successful actions
        if response.response_type == "success":
            action_key = f"{processing_result.intent.value}:{response.metadata.get('action', 'unknown')}"
            user_ctx["successful_actions"].append(action_key)
            
        # Track file usage
        if 'note_path' in processing_result.parameters:
            file_path = processing_result.parameters['note_path']
            user_ctx["common_files"][file_path] += 1
            
        # Update conversation style based on response feedback
        if response.confidence > 0.9:
            # Successful interaction - reinforce current style
            pass
        elif response.confidence < 0.5:
            # Low confidence - might need style adjustment
            pass
            
        # Add to recent history
        user_ctx["recent_history"].append({
            "timestamp": datetime.now().isoformat(),
            "intent": processing_result.intent.value,
            "response_type": response.response_type,
            "confidence": response.confidence
        })
        
    def _make_concise(self, content: str) -> str:
        """Make response more concise."""
        # Remove redundant phrases and shorten
        content = re.sub(r'\b(please|kindly|would you like to)\b', '', content, flags=re.IGNORECASE)
        content = re.sub(r'\s+', ' ', content).strip()
        
        # Shorten if too long
        if len(content) > 100:
            sentences = content.split('. ')
            if len(sentences) > 1:
                content = sentences[0] + '.'
                
        return content
        
    def _add_details(self, content: str, context: ResponseContext) -> str:
        """Add more details to response."""
        # Add contextual information
        if context.current_vault_info:
            note_count = context.current_vault_info.get("note_count", 0)
            content += f" Your vault contains {note_count} notes."
            
        return content
        
    def _generate_time_based_suggestions(
        self, 
        time_context: Dict[str, Any], 
        user_ctx: Dict[str, Any]
    ) -> List[str]:
        """Generate time-based suggestions."""
        
        suggestions = []
        current_hour = datetime.now().hour
        
        if 6 <= current_hour < 12:  # Morning
            suggestions.append("Start your day: review yesterday's notes?")
        elif 12 <= current_hour < 18:  # Afternoon
            suggestions.append("Midday check: create progress notes?")
        elif 18 <= current_hour < 22:  # Evening
            suggestions.append("End of day: summarize and plan tomorrow?")
            
        return suggestions
        
    def _create_fallback_response(self, error_msg: str) -> GeneratedResponse:
        """Create fallback response for errors."""
        return GeneratedResponse(
            content=f"I encountered an error while processing your request: {error_msg}",
            response_type="error",
            suggestions=["Try rephrasing your request", "Check your vault configuration"],
            follow_up_actions=[],
            requires_input=False,
            confidence=0.1,
            metadata={"error": error_msg, "fallback": True}
        )
        
    def _load_response_templates(self) -> Dict[str, List[str]]:
        """Load response templates for different situations."""
        return {
            "greeting": [
                "Hello! I'm here to help you manage your notes.",
                "Hi there! What would you like to do with your vault today?",
                "Welcome back! Ready to work with your notes?"
            ],
            "clarification": [
                "I need a bit more information to help you.",
                "Could you clarify what you'd like me to do?",
                "I'm not sure I understand. Could you rephrase that?"
            ],
            "success": [
                "Great! I've completed that for you.",
                "Done! The action was successful.",
                "Perfect! That worked as expected."
            ],
            "error": [
                "I ran into an issue while trying to do that.",
                "Something went wrong. Let me help you fix this.",
                "There was a problem with that request."
            ]
        }
        
    def get_response_stats(self) -> Dict[str, Any]:
        """Get response generation statistics."""
        return self.response_stats.copy()
        
    def reset_user_context(self, user_id: str) -> None:
        """Reset context for a specific user."""
        if user_id in self.user_contexts:
            del self.user_contexts[user_id]
            logger.debug(f"Reset context for user: {user_id}")
            
    def export_user_patterns(self, user_id: str) -> Dict[str, Any]:
        """Export learned patterns for a user."""
        if user_id not in self.user_contexts:
            return {}
            
        user_ctx = self.user_contexts[user_id]
        return {
            "preferences": user_ctx["preferences"],
            "patterns": dict(user_ctx["patterns"]),
            "common_files": dict(user_ctx["common_files"]),
            "conversation_style": user_ctx["conversation_style"],
            "total_interactions": len(user_ctx["recent_history"])
        }