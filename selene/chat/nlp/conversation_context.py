"""
Conversation Context Management for SELENE chatbot.

This module manages conversation context and state to enable
more natural, context-aware interactions.
"""

import re
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Dict, List, Optional, Set

from loguru import logger

from .intent_classifier import Intent, IntentResult


@dataclass
class ConversationTurn:
    """Represents a single turn in the conversation."""
    timestamp: datetime
    user_message: str
    intent: Intent
    entities: Dict[str, Any]
    agent_response: str
    tool_calls: List[Dict[str, Any]] = field(default_factory=list)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for storage."""
        return {
            "timestamp": self.timestamp.isoformat(),
            "user_message": self.user_message,
            "intent": self.intent.value,
            "entities": self.entities,
            "agent_response": self.agent_response,
            "tool_calls": self.tool_calls
        }


@dataclass
class ConversationContext:
    """Manages conversation context and state."""
    current_note: Optional[str] = None
    current_query: Optional[str] = None
    recent_notes: List[str] = field(default_factory=list)
    recent_queries: List[str] = field(default_factory=list)
    conversation_turns: List[ConversationTurn] = field(default_factory=list)
    user_preferences: Dict[str, Any] = field(default_factory=dict)
    
    def add_turn(self, turn: ConversationTurn) -> None:
        """Add a conversation turn and update context."""
        self.conversation_turns.append(turn)
        self._update_context_from_turn(turn)
        
        # Keep only recent turns (last 10)
        if len(self.conversation_turns) > 10:
            self.conversation_turns = self.conversation_turns[-10:]
            
    def _update_context_from_turn(self, turn: ConversationTurn) -> None:
        """Update context state from a conversation turn."""
        # Update current note
        if "note_path" in turn.entities:
            note_path = turn.entities["note_path"]
            self.current_note = note_path
            
            # Add to recent notes
            if note_path not in self.recent_notes:
                self.recent_notes.append(note_path)
                
            # Keep only recent notes (last 5)
            if len(self.recent_notes) > 5:
                self.recent_notes = self.recent_notes[-5:]
                
        # Update current query
        if "query" in turn.entities:
            query = turn.entities["query"]
            self.current_query = query
            
            # Add to recent queries
            if query not in self.recent_queries:
                self.recent_queries.append(query)
                
            # Keep only recent queries (last 5)
            if len(self.recent_queries) > 5:
                self.recent_queries = self.recent_queries[-5:]
                
    def get_context_suggestions(self, intent: Intent) -> Dict[str, Any]:
        """Get context-based suggestions for the current intent."""
        suggestions = {}
        
        # Note-based suggestions
        if intent in [Intent.READ_NOTE, Intent.UPDATE_NOTE, Intent.SUMMARIZE, Intent.ENHANCE, Intent.EXTRACT_INSIGHTS, Intent.GENERATE_QUESTIONS]:
            if self.current_note:
                suggestions["note_path"] = self.current_note
            elif self.recent_notes:
                suggestions["recent_notes"] = self.recent_notes
                
        # Query-based suggestions
        elif intent in [Intent.SEARCH_NOTES, Intent.VECTOR_SEARCH]:
            if self.current_query:
                suggestions["query"] = self.current_query
            elif self.recent_queries:
                suggestions["recent_queries"] = self.recent_queries
                
        return suggestions
        
    def resolve_pronouns(self, text: str) -> str:
        """Resolve pronouns and context references in text."""
        resolved_text = text
        
        # Common pronoun patterns
        pronoun_patterns = [
            (r'\bit\b', self.current_note),
            (r'\bthat\s+(?:note|file)\b', self.current_note),
            (r'\bthis\s+(?:note|file)\b', self.current_note),
            (r'\bthe\s+(?:note|file)\b', self.current_note),
            (r'\bthat\s+(?:search|query)\b', self.current_query),
            (r'\bthis\s+(?:search|query)\b', self.current_query),
            (r'\bthe\s+(?:search|query)\b', self.current_query),
        ]
        
        for pattern, replacement in pronoun_patterns:
            if replacement:
                resolved_text = re.sub(pattern, replacement, resolved_text, flags=re.IGNORECASE)
                
        return resolved_text
        
    def get_context_for_ai(self, window_size: int = 3) -> List[Dict[str, Any]]:
        """Get conversation context for AI processing."""
        recent_turns = self.conversation_turns[-window_size:]
        
        context = []
        for turn in recent_turns:
            context.append({
                "role": "user",
                "content": turn.user_message,
                "intent": turn.intent.value,
                "entities": turn.entities
            })
            context.append({
                "role": "assistant", 
                "content": turn.agent_response,
                "tool_calls": turn.tool_calls
            })
            
        return context
        
    def get_current_topic(self) -> Optional[str]:
        """Get the current conversation topic."""
        if not self.conversation_turns:
            return None
            
        # Look at recent intents to determine topic
        recent_intents = [turn.intent for turn in self.conversation_turns[-3:]]
        
        # Topic classification based on intent patterns
        if any(intent in [Intent.READ_NOTE, Intent.WRITE_NOTE, Intent.UPDATE_NOTE] for intent in recent_intents):
            return "note_management"
        elif any(intent in [Intent.SEARCH_NOTES, Intent.VECTOR_SEARCH] for intent in recent_intents):
            return "search"
        elif any(intent in [Intent.SUMMARIZE, Intent.ENHANCE, Intent.EXTRACT_INSIGHTS, Intent.GENERATE_QUESTIONS] for intent in recent_intents):
            return "ai_processing"
        else:
            return "general"
            
    def is_follow_up_question(self, intent: Intent) -> bool:
        """Check if current intent is a follow-up to previous conversation."""
        if not self.conversation_turns:
            return False
            
        last_turn = self.conversation_turns[-1]
        
        # Follow-up patterns
        follow_up_patterns = [
            # Same intent type
            (intent == last_turn.intent),
            # Related intents
            (intent in [Intent.ENHANCE, Intent.SUMMARIZE] and last_turn.intent in [Intent.READ_NOTE, Intent.WRITE_NOTE]),
            (intent in [Intent.EXTRACT_INSIGHTS, Intent.GENERATE_QUESTIONS] and last_turn.intent in [Intent.SUMMARIZE, Intent.ENHANCE]),
            (intent == Intent.VECTOR_SEARCH and last_turn.intent == Intent.SEARCH_NOTES),
        ]
        
        return any(follow_up_patterns)
        
    def get_implicit_parameters(self, intent: Intent) -> Dict[str, Any]:
        """Get implicit parameters from conversation context."""
        implicit_params = {}
        
        # Use current note for note-related operations
        if intent in [Intent.READ_NOTE, Intent.UPDATE_NOTE, Intent.SUMMARIZE, Intent.ENHANCE, Intent.EXTRACT_INSIGHTS, Intent.GENERATE_QUESTIONS]:
            if self.current_note:
                implicit_params["note_path"] = self.current_note
                
        # Use current query for search operations
        elif intent in [Intent.SEARCH_NOTES, Intent.VECTOR_SEARCH]:
            if self.current_query:
                implicit_params["query"] = self.current_query
                
        return implicit_params
        
    def clear_context(self) -> None:
        """Clear conversation context."""
        self.current_note = None
        self.current_query = None
        self.recent_notes.clear()
        self.recent_queries.clear()
        
    def get_statistics(self) -> Dict[str, Any]:
        """Get conversation statistics."""
        if not self.conversation_turns:
            return {
                "total_turns": 0,
                "most_common_intent": None,
                "unique_notes": 0,
                "unique_queries": 0
            }
            
        intent_counts = {}
        unique_notes = set()
        unique_queries = set()
        
        for turn in self.conversation_turns:
            # Count intents
            intent_counts[turn.intent] = intent_counts.get(turn.intent, 0) + 1
            
            # Collect unique notes and queries
            if "note_path" in turn.entities:
                unique_notes.add(turn.entities["note_path"])
            if "query" in turn.entities:
                unique_queries.add(turn.entities["query"])
                
        most_common_intent = max(intent_counts, key=intent_counts.get) if intent_counts else None
        
        return {
            "total_turns": len(self.conversation_turns),
            "most_common_intent": most_common_intent.value if most_common_intent else None,
            "unique_notes": len(unique_notes),
            "unique_queries": len(unique_queries),
            "intent_distribution": {intent.value: count for intent, count in intent_counts.items()}
        }


class ContextManager:
    """Manages conversation context across chat sessions."""
    
    def __init__(self):
        """Initialize context manager."""
        self.context = ConversationContext()
        
    def process_turn(self, user_message: str, intent_result: IntentResult, agent_response: str, tool_calls: List[Dict[str, Any]] = None) -> None:
        """Process a conversation turn and update context."""
        turn = ConversationTurn(
            timestamp=datetime.now(),
            user_message=user_message,
            intent=intent_result.intent,
            entities=intent_result.entities,
            agent_response=agent_response,
            tool_calls=tool_calls or []
        )
        
        self.context.add_turn(turn)
        logger.debug(f"Updated context with turn: {intent_result.intent.value}")
        
    def enhance_intent_result(self, intent_result: IntentResult) -> IntentResult:
        """Enhance intent result with context information."""
        # Add implicit parameters from context
        implicit_params = self.context.get_implicit_parameters(intent_result.intent)
        
        # Merge with existing entities, giving priority to explicit entities
        enhanced_entities = {**implicit_params, **intent_result.entities}
        
        # Increase confidence if context provides missing information
        confidence_boost = 0.0
        if implicit_params and not intent_result.entities:
            confidence_boost = 0.2
            
        return IntentResult(
            intent=intent_result.intent,
            confidence=min(1.0, intent_result.confidence + confidence_boost),
            entities=enhanced_entities,
            raw_text=intent_result.raw_text
        )
        
    def get_context_suggestions(self, intent: Intent) -> Dict[str, Any]:
        """Get context-based suggestions."""
        return self.context.get_context_suggestions(intent)
        
    def resolve_references(self, text: str) -> str:
        """Resolve pronouns and context references."""
        return self.context.resolve_pronouns(text)
        
    def is_follow_up(self, intent: Intent) -> bool:
        """Check if this is a follow-up question."""
        return self.context.is_follow_up_question(intent)
        
    def get_conversation_context(self, window_size: int = 3) -> List[Dict[str, Any]]:
        """Get conversation context for AI."""
        return self.context.get_context_for_ai(window_size)
        
    def reset_context(self) -> None:
        """Reset conversation context."""
        self.context.clear_context()
        
    def get_context_stats(self) -> Dict[str, Any]:
        """Get context statistics."""
        return self.context.get_statistics()