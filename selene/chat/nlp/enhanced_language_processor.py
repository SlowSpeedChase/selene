"""
Enhanced Language Processor for SMS-38 Advanced Chat Features.

This module provides significant improvements over the base language processor:
- Fuzzy parameter matching and smart inference
- Multi-step conversation workflows  
- Context-aware command disambiguation
- Smart suggestion generation with learning
- Advanced natural language understanding
"""

import re
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Set
from difflib import SequenceMatcher
from collections import defaultdict, Counter

from loguru import logger

from .intent_classifier import Intent, IntentClassifier, IntentResult
from .parameter_extractor import ParameterExtractor, ParameterResult
from .conversation_context import ContextManager
from .language_processor import ProcessingResult


@dataclass
class EnhancedProcessingResult(ProcessingResult):
    """Enhanced processing result with additional capabilities."""
    alternative_interpretations: List[Tuple[Intent, float]] = field(default_factory=list)
    suggested_completions: List[str] = field(default_factory=list)
    file_matches: List[str] = field(default_factory=list)
    workflow_step: Optional[str] = None
    requires_clarification: bool = False
    clarification_question: Optional[str] = None
    inferred_parameters: Dict[str, Any] = field(default_factory=dict)
    user_learning_data: Dict[str, Any] = field(default_factory=dict)
    
    @property
    def has_alternatives(self) -> bool:
        """Check if there are alternative interpretations."""
        return len(self.alternative_interpretations) > 0
        
    @property
    def needs_clarification(self) -> bool:
        """Check if clarification is needed."""
        return self.requires_clarification or self.clarification_question is not None


@dataclass
class WorkflowState:
    """State for multi-step conversation workflows."""
    workflow_id: str
    current_step: str
    expected_parameters: Dict[str, Any]
    collected_parameters: Dict[str, Any]
    remaining_steps: List[str]
    workflow_data: Dict[str, Any] = field(default_factory=dict)
    

class EnhancedLanguageProcessor:
    """
    Enhanced language processor with advanced NLP capabilities.
    
    Key improvements:
    1. Fuzzy file matching and smart parameter inference
    2. Multi-step conversation workflows
    3. Learning from user patterns
    4. Context-aware disambiguation
    5. Advanced suggestion generation
    """
    
    def __init__(self, vault_path: Optional[Path] = None):
        """
        Initialize enhanced language processor.
        
        Args:
            vault_path: Current vault path for file resolution
        """
        self.vault_path = vault_path
        
        # Initialize base components
        self.intent_classifier = IntentClassifier()
        self.parameter_extractor = ParameterExtractor(vault_path)
        self.context_manager = ContextManager()
        
        # Enhanced components
        self.user_patterns = defaultdict(Counter)  # Learn user patterns
        self.file_cache = {}  # Cache for file lookups
        self.workflow_state: Optional[WorkflowState] = None
        
        # Smart suggestions
        self.recent_files = []
        self.common_queries = Counter()
        self.successful_patterns = []
        
        # Configuration
        self.fuzzy_threshold = 0.6
        self.learning_enabled = True
        self.max_alternatives = 3
        
        # Processing statistics
        self.enhanced_stats = {
            "fuzzy_matches": 0,
            "parameter_inferences": 0,
            "workflow_completions": 0,
            "clarification_requests": 0,
            "learning_updates": 0
        }
        
    def process_message(self, message: str, user_id: Optional[str] = None) -> EnhancedProcessingResult:
        """
        Process a user message with enhanced NLP capabilities.
        
        Args:
            message: User message text
            user_id: Optional user identifier for personalization
            
        Returns:
            Enhanced processing result
        """
        try:
            # Step 1: Check for active workflow
            if self.workflow_state:
                return self._process_workflow_message(message, user_id)
                
            # Step 2: Preprocess and classify
            preprocessed = self._enhanced_preprocess(message)
            intent_result = self.intent_classifier.classify(preprocessed)
            
            # Step 3: Generate alternative interpretations
            alternatives = self._generate_alternatives(preprocessed, intent_result)
            
            # Step 4: Enhanced parameter extraction with fuzzy matching
            parameter_result = self._enhanced_parameter_extraction(
                intent_result, preprocessed, alternatives
            )
            
            # Step 5: Smart parameter inference
            inferred_params = self._infer_missing_parameters(
                intent_result, parameter_result, message
            )
            
            # Step 6: File fuzzy matching
            file_matches = self._fuzzy_file_matching(parameter_result.parameters, inferred_params)
            
            # Step 7: Context enhancement
            enhanced_result = self.context_manager.enhance_intent_result(intent_result)
            
            # Step 8: Generate suggestions and completions
            suggestions = self._generate_smart_suggestions(enhanced_result, parameter_result, file_matches)
            completions = self._generate_completions(preprocessed, enhanced_result)
            
            # Step 9: Check for clarification needs
            clarification = self._check_clarification_needs(
                enhanced_result, parameter_result, alternatives, file_matches
            )
            
            # Step 10: Build enhanced result
            tool_name = self._get_tool_name(enhanced_result.intent)
            final_params = {**parameter_result.parameters, **inferred_params}
            
            result = EnhancedProcessingResult(
                intent=enhanced_result.intent,
                tool_name=tool_name,
                parameters=final_params,
                confidence=self._calculate_enhanced_confidence(enhanced_result, parameter_result, file_matches),
                missing_parameters=self._get_remaining_missing_params(tool_name, final_params),
                suggestions=suggestions,
                needs_confirmation=self._enhanced_confirmation_check(enhanced_result, parameter_result),
                context_used=enhanced_result.confidence > intent_result.confidence,
                alternative_interpretations=alternatives,
                suggested_completions=completions,
                file_matches=file_matches,
                inferred_parameters=inferred_params,
                requires_clarification=clarification[0],
                clarification_question=clarification[1] if clarification[0] else None
            )
            
            # Step 11: Learn from interaction
            if self.learning_enabled and user_id:
                self._update_user_patterns(user_id, message, result)
                
            # Update statistics
            self._update_enhanced_stats(result)
            
            logger.debug(f"Enhanced processing: intent={result.intent.value}, "
                        f"confidence={result.confidence:.2f}, "
                        f"alternatives={len(result.alternative_interpretations)}")
            
            return result
            
        except Exception as e:
            logger.error(f"Enhanced processing failed: {e}")
            return self._create_error_result(str(e))
            
    def start_workflow(self, workflow_id: str, steps: List[str], initial_params: Dict[str, Any] = None) -> bool:
        """
        Start a multi-step conversation workflow.
        
        Args:
            workflow_id: Unique workflow identifier
            steps: List of workflow steps
            initial_params: Initial parameters for workflow
            
        Returns:
            True if workflow started successfully
        """
        try:
            self.workflow_state = WorkflowState(
                workflow_id=workflow_id,
                current_step=steps[0] if steps else "unknown",
                expected_parameters={},
                collected_parameters=initial_params or {},
                remaining_steps=steps[1:] if len(steps) > 1 else [],
                workflow_data={}
            )
            
            logger.info(f"Started workflow: {workflow_id} with {len(steps)} steps")
            return True
            
        except Exception as e:
            logger.error(f"Failed to start workflow {workflow_id}: {e}")
            return False
            
    def _process_workflow_message(self, message: str, user_id: Optional[str]) -> EnhancedProcessingResult:
        """Process message within an active workflow."""
        if not self.workflow_state:
            return self._create_error_result("No active workflow")
            
        try:
            # Process message for current workflow step
            step = self.workflow_state.current_step
            
            # Step-specific processing logic
            if step == "collect_note_details":
                return self._process_note_creation_step(message)
            elif step == "confirm_search_params":
                return self._process_search_confirmation_step(message)
            elif step == "file_selection":
                return self._process_file_selection_step(message)
            else:
                # Generic step processing
                return self._process_generic_workflow_step(message)
                
        except Exception as e:
            logger.error(f"Workflow processing error: {e}")
            return self._create_error_result(f"Workflow error: {e}")
            
    def _enhanced_preprocess(self, message: str) -> str:
        """Enhanced preprocessing with pattern recognition."""
        # Base preprocessing
        normalized = re.sub(r'\s+', ' ', message).strip()
        
        # Smart expansions based on learned patterns
        if hasattr(self, 'common_expansions'):
            for pattern, expansion in self.common_expansions.items():
                normalized = re.sub(pattern, expansion, normalized, flags=re.IGNORECASE)
                
        # File extension inference
        if not re.search(r'\.\w+', normalized) and any(word in normalized.lower() for word in ['note', 'file', 'document']):
            # Likely referring to a markdown file
            normalized = re.sub(r'\b([\w\-_]+)\b(?=\s|$)', r'\1.md', normalized)
            
        return normalized
        
    def _generate_alternatives(self, message: str, intent_result: IntentResult) -> List[Tuple[Intent, float]]:
        """Generate alternative intent interpretations."""
        alternatives = []
        
        # Since classify_all doesn't exist, we'll generate alternatives by testing
        # different variations of the message for other possible intents
        
        # Test other common intents with slightly modified queries
        test_intents = [
            (Intent.SEARCH_NOTES, "search"),
            (Intent.READ_NOTE, "read"),
            (Intent.VECTOR_SEARCH, "find"),
            (Intent.LIST_NOTES, "list"),
            (Intent.WRITE_NOTE, "write"),
            (Intent.SUMMARIZE, "summarize"),
            (Intent.ENHANCE, "enhance")
        ]
        
        for test_intent, keyword in test_intents:
            if test_intent != intent_result.intent:
                # Create a test message that might trigger this intent
                test_message = f"{keyword} {message}"
                test_result = self.intent_classifier.classify(test_message)
                
                if test_result.intent == test_intent and test_result.confidence > 0.3:
                    alternatives.append((test_intent, test_result.confidence * 0.8))  # Reduce confidence since it's alternative
                
        # Sort by confidence and take top N
        alternatives.sort(key=lambda x: x[1], reverse=True)
        return alternatives[:self.max_alternatives]
        
    def _enhanced_parameter_extraction(
        self, 
        intent_result: IntentResult, 
        message: str, 
        alternatives: List[Tuple[Intent, float]]
    ) -> ParameterResult:
        """Enhanced parameter extraction with fuzzy matching."""
        # Primary extraction
        primary_result = self.parameter_extractor.extract_parameters(intent_result)
        
        # Try alternatives if primary extraction is incomplete
        if not primary_result.is_complete and alternatives:
            for alt_intent, _ in alternatives:
                alt_intent_result = IntentResult(
                    intent=alt_intent,
                    confidence=intent_result.confidence,
                    entities=intent_result.entities,
                    raw_text=message
                )
                alt_result = self.parameter_extractor.extract_parameters(alt_intent_result)
                
                # Merge useful parameters
                if alt_result.is_complete or len(alt_result.parameters) > len(primary_result.parameters):
                    primary_result = alt_result
                    break
                    
        return primary_result
        
    def _infer_missing_parameters(
        self, 
        intent_result: IntentResult, 
        parameter_result: ParameterResult, 
        message: str
    ) -> Dict[str, Any]:
        """Smart parameter inference using context and patterns."""
        inferred = {}
        
        # File path inference
        if 'note_path' in parameter_result.missing_required:
            inferred_path = self._infer_file_path(message, intent_result)
            if inferred_path:
                inferred['note_path'] = inferred_path
                self.enhanced_stats["parameter_inferences"] += 1
                
        # Task inference for AI processing
        if intent_result in [Intent.SUMMARIZE, Intent.ENHANCE, Intent.EXTRACT_INSIGHTS]:
            task_map = {
                Intent.SUMMARIZE: "summarize",
                Intent.ENHANCE: "enhance", 
                Intent.EXTRACT_INSIGHTS: "extract_insights",
                Intent.GENERATE_QUESTIONS: "questions"
            }
            inferred['task'] = task_map.get(intent_result, "enhance")
            
        # Query inference for search
        if 'query' in parameter_result.missing_required and intent_result in [Intent.SEARCH_NOTES, Intent.VECTOR_SEARCH]:
            query = self._extract_search_query(message)
            if query:
                inferred['query'] = query
                
        return inferred
        
    def _infer_file_path(self, message: str, intent: Intent) -> Optional[str]:
        """Infer file path from message context."""
        # Extract potential filenames (exact .md files)
        potential_files = re.findall(r'\b([\w\-_\.]+\.md)\b', message)
        if potential_files:
            return potential_files[0]
            
        # Look for quoted strings
        quoted = re.findall(r'["\']([^"\']+)["\']', message)
        if quoted:
            filename = quoted[0]
            if not filename.endswith('.md'):
                filename += '.md'
            return filename
            
        # Smart inference from message content
        # Look for keywords that suggest filenames
        keywords = []
        
        # Extract meaningful words (skip common words)
        words = re.findall(r'\b\w+\b', message.lower())
        skip_words = {'read', 'my', 'the', 'show', 'me', 'get', 'open', 'file', 'note', 'notes'}
        keywords = [word for word in words if word not in skip_words and len(word) > 2]
        
        # Try to match against actual files if vault exists
        if self.vault_path and self.vault_path.exists() and keywords:
            md_files = list(self.vault_path.glob("**/*.md"))
            
            # First try: exact keyword match
            for keyword in keywords:
                for file_path in md_files:
                    if keyword.lower() in file_path.name.lower():
                        return file_path.name
                        
            # Second try: construct filename from keywords
            if keywords:
                # Common patterns: daily-notes, meeting-notes, etc.
                constructed_name = '-'.join(keywords[:2]) + '.md'  # Use first 2 keywords
                return constructed_name
                
        # Use recent files context
        if hasattr(self, 'recent_files') and self.recent_files and intent == Intent.READ_NOTE:
            return self.recent_files[0]
            
        return None
        
    def _fuzzy_file_matching(self, parameters: Dict[str, Any], inferred: Dict[str, Any]) -> List[str]:
        """Perform fuzzy matching against available files."""
        if not self.vault_path or not self.vault_path.exists():
            return []
            
        matches = []
        target_file = parameters.get('note_path') or inferred.get('note_path')
        
        if target_file:
            # Get all markdown files
            md_files = list(self.vault_path.glob("**/*.md"))
            file_names = [f.name for f in md_files]
            
            # Fuzzy match against filenames
            for filename in file_names:
                similarity = SequenceMatcher(None, target_file.lower(), filename.lower()).ratio()
                if similarity > self.fuzzy_threshold:
                    matches.append(filename)
                    self.enhanced_stats["fuzzy_matches"] += 1
                    
            # Sort by similarity
            matches.sort(key=lambda f: SequenceMatcher(None, target_file.lower(), f.lower()).ratio(), reverse=True)
            
        return matches[:5]  # Return top 5 matches
        
    def _generate_smart_suggestions(
        self, 
        intent_result: IntentResult, 
        parameter_result: ParameterResult, 
        file_matches: List[str]
    ) -> List[str]:
        """Generate intelligent suggestions based on context."""
        suggestions = []
        
        # File-based suggestions
        if file_matches:
            suggestions.append(f"Did you mean: {', '.join(file_matches[:3])}?")
            
        # Recent activity suggestions
        if self.recent_files and intent_result.intent == Intent.READ_NOTE:
            suggestions.append(f"Recent notes: {', '.join(self.recent_files[:3])}")
            
        # Common query suggestions
        if intent_result.intent in [Intent.SEARCH_NOTES, Intent.VECTOR_SEARCH]:
            common = [query for query, count in self.common_queries.most_common(3)]
            if common:
                suggestions.append(f"Common searches: {', '.join(common)}")
                
        # Intent-specific suggestions
        if intent_result.intent == Intent.UNKNOWN:
            suggestions.extend([
                "Try: 'read my daily notes', 'search for AI research', or 'create a todo list'",
                "Use quotes for exact filenames: 'read \"meeting notes.md\"'"
            ])
            
        return suggestions
        
    def _generate_completions(self, message: str, intent_result: IntentResult) -> List[str]:
        """Generate smart command completions."""
        completions = []
        
        # Partial command completions
        if len(message.split()) < 3:  # Short commands
            if intent_result.intent == Intent.READ_NOTE:
                completions.extend([
                    f"{message} daily notes",
                    f"{message} meeting summary",
                    f"{message} project ideas"
                ])
            elif intent_result.intent == Intent.SEARCH_NOTES:
                completions.extend([
                    f"{message} about AI",
                    f"{message} containing todo",
                    f"{message} from this week"
                ])
                
        return completions[:3]
        
    def _check_clarification_needs(
        self, 
        intent_result: IntentResult, 
        parameter_result: ParameterResult, 
        alternatives: List[Tuple[Intent, float]],
        file_matches: List[str]
    ) -> Tuple[bool, Optional[str]]:
        """Check if clarification is needed and generate question."""
        
        # Ambiguous intent with close alternatives
        if alternatives and abs(intent_result.confidence - alternatives[0][1]) < 0.2:
            alt_intent = alternatives[0][0]
            question = f"Did you want to {intent_result.intent.value.replace('_', ' ')} or {alt_intent.value.replace('_', ' ')}?"
            return True, question
            
        # Multiple file matches
        if len(file_matches) > 1:
            question = f"Which file did you mean: {', '.join(file_matches[:3])}?"
            return True, question
            
        # Low confidence with critical missing parameters
        if intent_result.confidence < 0.5 and parameter_result.missing_required:
            missing = ', '.join(parameter_result.missing_required)
            question = f"I need more information. Could you specify: {missing}?"
            return True, question
            
        return False, None
        
    def _calculate_enhanced_confidence(
        self, 
        intent_result: IntentResult, 
        parameter_result: ParameterResult, 
        file_matches: List[str]
    ) -> float:
        """Calculate enhanced confidence score."""
        base_confidence = min(intent_result.confidence, parameter_result.confidence)
        
        # Boost for successful file matching
        if file_matches:
            base_confidence = min(1.0, base_confidence + 0.1)
            
        # Boost for complete parameters
        if parameter_result.is_complete:
            base_confidence = min(1.0, base_confidence + 0.05)
            
        return base_confidence
        
    def _enhanced_confirmation_check(
        self, 
        intent_result: IntentResult, 
        parameter_result: ParameterResult
    ) -> bool:
        """Enhanced confirmation logic."""
        destructive_intents = [Intent.WRITE_NOTE, Intent.UPDATE_NOTE, Intent.DELETE_NOTE]
        
        if intent_result.intent in destructive_intents:
            # Always confirm destructive actions with low confidence
            if intent_result.confidence < 0.8:
                return True
            # Confirm if inferring critical parameters
            if 'note_path' in parameter_result.missing_required:
                return True
                
        return False
        
    def _get_remaining_missing_params(self, tool_name: Optional[str], parameters: Dict[str, Any]) -> List[str]:
        """Get remaining missing parameters after inference."""
        if not tool_name:
            return []
            
        required_params = {
            "read_note": ["note_path"],
            "write_note": ["note_path", "content"],
            "update_note": ["note_path"],
            "search_notes": ["query"],
            "vector_search": ["query"],
            "list_notes": [],
            "ai_process": ["content", "task"]
        }
        
        required = required_params.get(tool_name, [])
        return [param for param in required if param not in parameters]
        
    def _update_user_patterns(self, user_id: str, message: str, result: EnhancedProcessingResult) -> None:
        """Learn from user interaction patterns."""
        try:
            # Track successful patterns
            if result.is_executable:
                pattern_key = f"{result.intent.value}:{len(message.split())}"
                self.user_patterns[user_id][pattern_key] += 1
                
            # Track file preferences
            if 'note_path' in result.parameters:
                file_key = f"file:{result.parameters['note_path']}"
                self.user_patterns[user_id][file_key] += 1
                
            # Update recent files
            if result.tool_name == "read_note" and 'note_path' in result.parameters:
                file_path = result.parameters['note_path']
                if file_path in self.recent_files:
                    self.recent_files.remove(file_path)
                self.recent_files.insert(0, file_path)
                self.recent_files = self.recent_files[:10]  # Keep last 10
                
            self.enhanced_stats["learning_updates"] += 1
            
        except Exception as e:
            logger.warning(f"Failed to update user patterns: {e}")
            
    def _update_enhanced_stats(self, result: EnhancedProcessingResult) -> None:
        """Update enhanced processing statistics."""
        if result.requires_clarification:
            self.enhanced_stats["clarification_requests"] += 1
            
        if result.workflow_step:
            self.enhanced_stats["workflow_completions"] += 1
            
    def _create_error_result(self, error_msg: str) -> EnhancedProcessingResult:
        """Create error result."""
        return EnhancedProcessingResult(
            intent=Intent.UNKNOWN,
            tool_name=None,
            parameters={},
            confidence=0.0,
            missing_parameters=[],
            suggestions=[f"Error: {error_msg}"],
            needs_confirmation=False,
            context_used=False
        )
        
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
        
    def _extract_search_query(self, message: str) -> Optional[str]:
        """Extract search query from message."""
        # Look for patterns like "search for X", "find X", "look for X"
        patterns = [
            r'search (?:for |about )?(.+)',
            r'find (?:notes? )?(?:about |containing )?(.+)',
            r'look for (.+)',
            r'show me (?:notes? )?(?:about |containing )?(.+)'
        ]
        
        for pattern in patterns:
            match = re.search(pattern, message.lower())
            if match:
                return match.group(1).strip()
                
        return None
        
    def get_enhanced_stats(self) -> Dict[str, Any]:
        """Get enhanced processing statistics."""
        base_stats = self.context_manager.get_context_stats()
        return {**base_stats, **self.enhanced_stats}
        
    def reset_workflow(self) -> None:
        """Reset current workflow state."""
        self.workflow_state = None
        logger.debug("Workflow state reset")
        
    def get_user_patterns(self, user_id: str) -> Dict[str, int]:
        """Get learned patterns for user."""
        return dict(self.user_patterns.get(user_id, {}))
        
    def set_vault_path(self, vault_path: Optional[Path]) -> None:
        """Update vault path for all components."""
        self.vault_path = vault_path
        if hasattr(self.parameter_extractor, 'set_vault_path'):
            self.parameter_extractor.set_vault_path(vault_path)