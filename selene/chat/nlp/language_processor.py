"""
Main Language Processor for SELENE chatbot.

This module orchestrates all NLP components to provide
comprehensive natural language understanding.
"""

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from loguru import logger

from .intent_classifier import Intent, IntentClassifier, IntentResult
from .parameter_extractor import ParameterExtractor, ParameterResult
from .conversation_context import ContextManager


@dataclass
class ProcessingResult:
    """Complete result of language processing."""
    intent: Intent
    tool_name: Optional[str]
    parameters: Dict[str, Any]
    confidence: float
    missing_parameters: List[str]
    suggestions: List[str]
    needs_confirmation: bool
    context_used: bool
    
    @property
    def is_executable(self) -> bool:
        """Check if result is ready for tool execution."""
        return (
            self.tool_name is not None and
            len(self.missing_parameters) == 0 and
            self.confidence > 0.6
        )
        
    @property
    def is_confident(self) -> bool:
        """Check if processing is confident."""
        return self.confidence > 0.7


class LanguageProcessor:
    """
    Main language processor that orchestrates all NLP components.
    
    This processor:
    1. Classifies user intent
    2. Extracts tool parameters
    3. Manages conversation context
    4. Provides suggestions and confirmations
    5. Handles ambiguous requests
    """
    
    def __init__(self, vault_path: Optional[Path] = None):
        """
        Initialize language processor.
        
        Args:
            vault_path: Current vault path for file resolution
        """
        self.vault_path = vault_path
        
        # Initialize components
        self.intent_classifier = IntentClassifier()
        self.parameter_extractor = ParameterExtractor(vault_path)
        self.context_manager = ContextManager()
        
        # Processing statistics
        self.processing_stats = {
            "total_processed": 0,
            "successful_classifications": 0,
            "context_enhancements": 0,
            "parameter_extractions": 0
        }
        
    def process_message(self, message: str, previous_result: Optional[ProcessingResult] = None) -> ProcessingResult:
        """
        Process a user message through the complete NLP pipeline.
        
        Args:
            message: User message text
            previous_result: Previous processing result for context
            
        Returns:
            Complete processing result
        """
        try:
            self.processing_stats["total_processed"] += 1
            
            # Step 1: Preprocess message
            preprocessed_message = self._preprocess_message(message)
            
            # Step 2: Classify intent
            intent_result = self.intent_classifier.classify(preprocessed_message)
            
            # Step 3: Enhance with context
            enhanced_result = self.context_manager.enhance_intent_result(intent_result)
            if enhanced_result.confidence > intent_result.confidence:
                self.processing_stats["context_enhancements"] += 1
                
            # Step 4: Extract parameters
            parameter_result = self.parameter_extractor.extract_parameters(enhanced_result)
            
            # Step 5: Generate suggestions
            suggestions = self._generate_suggestions(enhanced_result, parameter_result)
            
            # Step 6: Determine if confirmation is needed
            needs_confirmation = self._needs_confirmation(enhanced_result, parameter_result)
            
            # Step 7: Build final result
            tool_name = self._get_tool_name(enhanced_result.intent)
            
            result = ProcessingResult(
                intent=enhanced_result.intent,
                tool_name=tool_name,
                parameters=parameter_result.parameters,
                confidence=min(enhanced_result.confidence, parameter_result.confidence),
                missing_parameters=parameter_result.missing_required,
                suggestions=suggestions,
                needs_confirmation=needs_confirmation,
                context_used=enhanced_result.confidence > intent_result.confidence
            )
            
            # Update statistics
            if enhanced_result.confidence > 0.7:
                self.processing_stats["successful_classifications"] += 1
            if parameter_result.parameters:
                self.processing_stats["parameter_extractions"] += 1
                
            logger.debug(f"Processed message: intent={enhanced_result.intent.value}, confidence={result.confidence:.2f}")
            
            return result
            
        except Exception as e:
            logger.error(f"Error processing message: {e}")
            return ProcessingResult(
                intent=Intent.UNKNOWN,
                tool_name=None,
                parameters={},
                confidence=0.0,
                missing_parameters=[],
                suggestions=[f"Error processing message: {str(e)}"],
                needs_confirmation=False,
                context_used=False
            )
            
    def update_context(self, message: str, result: ProcessingResult, response: str, tool_calls: List[Dict[str, Any]] = None) -> None:
        """
        Update conversation context with processed turn.
        
        Args:
            message: Original user message
            result: Processing result
            response: Agent response
            tool_calls: List of tool calls made
        """
        # Convert ProcessingResult to IntentResult for context manager
        intent_result = IntentResult(
            intent=result.intent,
            confidence=result.confidence,
            entities=result.parameters,
            raw_text=message
        )
        
        self.context_manager.process_turn(
            user_message=message,
            intent_result=intent_result,
            agent_response=response,
            tool_calls=tool_calls or []
        )
        
    def _preprocess_message(self, message: str) -> str:
        """Preprocess message for better analysis."""
        # Resolve context references
        resolved_message = self.context_manager.resolve_references(message)
        
        # Normalize whitespace
        normalized = re.sub(r'\s+', ' ', resolved_message).strip()
        
        # Expand common contractions
        contractions = {
            "can't": "cannot",
            "won't": "will not",
            "n't": " not",
            "'ll": " will",
            "'ve": " have",
            "'re": " are",
            "'d": " would"
        }
        
        for contraction, expansion in contractions.items():
            normalized = normalized.replace(contraction, expansion)
            
        return normalized
        
    def _generate_suggestions(self, intent_result: IntentResult, parameter_result: ParameterResult) -> List[str]:
        """Generate helpful suggestions for the user."""
        suggestions = []
        
        # Add parameter suggestions
        if parameter_result.missing_required:
            tool_name = self._get_tool_name(intent_result.intent)
            if tool_name:
                param_suggestions = self.parameter_extractor.get_parameter_suggestions(
                    tool_name, parameter_result.parameters
                )
                suggestions.extend(param_suggestions)
                
        # Add context suggestions
        context_suggestions = self.context_manager.get_context_suggestions(intent_result.intent)
        if context_suggestions:
            if "recent_notes" in context_suggestions:
                suggestions.append(f"Recent notes: {', '.join(context_suggestions['recent_notes'])}")
            if "recent_queries" in context_suggestions:
                suggestions.append(f"Recent searches: {', '.join(context_suggestions['recent_queries'])}")
                
        # Add intent-specific suggestions
        if intent_result.intent == Intent.UNKNOWN:
            suggestions.append("Try phrases like 'read my notes', 'search for AI', or 'create a new note'")
        elif intent_result.confidence < 0.5:
            suggestions.append("Could you please rephrase your request more clearly?")
            
        return suggestions
        
    def _needs_confirmation(self, intent_result: IntentResult, parameter_result: ParameterResult) -> bool:
        """Determine if the action needs user confirmation."""
        # High-risk operations that modify data
        destructive_intents = [Intent.WRITE_NOTE, Intent.UPDATE_NOTE, Intent.DELETE_NOTE]
        
        if intent_result.intent in destructive_intents:
            # Confirm if confidence is low or parameters are incomplete
            if intent_result.confidence < 0.8 or not parameter_result.is_complete:
                return True
                
        return False
        
    def _get_tool_name(self, intent: Intent) -> Optional[str]:
        """Get tool name for intent."""
        intent_to_tool = {
            Intent.READ_NOTE: "read_note",
            Intent.WRITE_NOTE: "write_note", 
            Intent.UPDATE_NOTE: "update_note",
            Intent.SEARCH_NOTES: "search_notes",
            Intent.VECTOR_SEARCH: "vector_search",
            Intent.LIST_NOTES: "list_notes",
            Intent.SUMMARIZE: "ai_process",
            Intent.ENHANCE: "ai_process",
            Intent.EXTRACT_INSIGHTS: "ai_process",
            Intent.GENERATE_QUESTIONS: "ai_process",
        }
        return intent_to_tool.get(intent)
        
    def set_vault_path(self, vault_path: Optional[Path]) -> None:
        """Update vault path for all components."""
        self.vault_path = vault_path
        self.parameter_extractor.set_vault_path(vault_path)
        
    def reset_context(self) -> None:
        """Reset conversation context."""
        self.context_manager.reset_context()
        
    def get_processing_stats(self) -> Dict[str, Any]:
        """Get processing statistics."""
        stats = self.processing_stats.copy()
        
        # Add context statistics
        context_stats = self.context_manager.get_context_stats()
        stats.update(context_stats)
        
        # Calculate success rates
        if stats["total_processed"] > 0:
            stats["classification_success_rate"] = stats["successful_classifications"] / stats["total_processed"]
            stats["context_enhancement_rate"] = stats["context_enhancements"] / stats["total_processed"]
            stats["parameter_extraction_rate"] = stats["parameter_extractions"] / stats["total_processed"]
        else:
            stats["classification_success_rate"] = 0.0
            stats["context_enhancement_rate"] = 0.0
            stats["parameter_extraction_rate"] = 0.0
            
        return stats
        
    def get_conversation_context(self, window_size: int = 3) -> List[Dict[str, Any]]:
        """Get conversation context for AI processing."""
        return self.context_manager.get_conversation_context(window_size)
        
    def is_follow_up_question(self, intent: Intent) -> bool:
        """Check if this is a follow-up question."""
        return self.context_manager.is_follow_up(intent)
        
    def get_supported_intents(self) -> List[str]:
        """Get list of supported intents."""
        return [intent.value for intent in Intent if intent != Intent.UNKNOWN]
        
    def get_example_phrases(self) -> Dict[str, List[str]]:
        """Get example phrases for each intent."""
        return {
            "read_note": [
                "Show me the meeting notes",
                "Read the note called 'project ideas'",
                "Open research.md",
                "What's in my daily notes?"
            ],
            "write_note": [
                "Create a note called 'Weekly Planning'",
                "Write a new note about machine learning",
                "Make a note with my ideas",
                "Start a new file called progress.md"
            ],
            "search_notes": [
                "Search for notes about AI",
                "Find anything related to project management",
                "Look for notes containing 'meeting'",
                "Where are my research notes?"
            ],
            "ai_processing": [
                "Summarize my meeting notes",
                "Extract insights from my research",
                "Generate questions from this brainstorm",
                "Enhance my rough notes"
            ]
        }