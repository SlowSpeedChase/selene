"""
Smart Tool Selector for SMS-38 Advanced Chat Features.

This module provides intelligent tool selection and parameter inference:
- Dynamic tool routing based on context and user patterns
- Smart parameter inference and validation
- Tool capability matching and optimization
- Adaptive tool selection based on success rates
- Contextual tool recommendation
"""

import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple
from collections import defaultdict, Counter
from datetime import datetime, timedelta

from loguru import logger

from ..nlp.enhanced_language_processor import EnhancedProcessingResult
from ..nlp.intent_classifier import Intent
from .base import BaseTool, ToolRegistry, ToolResult, ToolStatus


@dataclass
class ToolCapability:
    """Tool capability description."""
    tool_name: str
    intent_compatibility: List[Intent]
    required_parameters: Set[str]
    optional_parameters: Set[str]
    performance_score: float = 1.0
    context_requirements: Dict[str, Any] = field(default_factory=dict)
    

@dataclass
class ToolSelection:
    """Result of tool selection process."""
    selected_tool: str
    confidence: float
    inferred_parameters: Dict[str, Any]
    alternative_tools: List[Tuple[str, float]]
    selection_reason: str
    validation_errors: List[str]
    

class SmartToolSelector:
    """
    Intelligent tool selection system that:
    - Analyzes user intent and context to select optimal tools
    - Infers missing parameters using contextual clues
    - Learns from successful tool usage patterns
    - Provides fallback options when primary tools fail
    - Optimizes tool selection based on performance data
    """
    
    def __init__(self, tool_registry: ToolRegistry, vault_path: Optional[Path] = None):
        """
        Initialize smart tool selector.
        
        Args:
            tool_registry: Registry of available tools
            vault_path: Current vault path for context
        """
        self.tool_registry = tool_registry
        self.vault_path = vault_path
        
        # Tool capabilities mapping
        self.tool_capabilities = self._initialize_tool_capabilities()
        
        # Performance tracking
        self.tool_performance = defaultdict(lambda: {
            "success_count": 0,
            "total_attempts": 0,
            "avg_execution_time": 0.0,
            "error_patterns": Counter(),
            "success_contexts": [],
            "last_used": None
        })
        
        # Context-based selection patterns
        self.context_patterns = defaultdict(Counter)  # context -> tool preferences
        self.user_tool_preferences = defaultdict(Counter)  # user -> tool usage
        
        # Parameter inference patterns
        self.parameter_patterns = {
            "file_path_patterns": [
                r'\b([\w\-_]+\.md)\b',  # filename.md
                r'["\']([^"\']+)["\']',  # quoted strings
                r'\b(daily|weekly|monthly|notes?|journal|todo|ideas?|meeting|project)\b'  # common note types
            ],
            "query_patterns": [
                r'(?:search|find|look for|about)\s+(.+)',
                r'(?:containing|with|having)\s+(.+)',
                r'related to\s+(.+)'
            ],
            "task_patterns": {
                "summarize": ["summary", "summarize", "sum up", "brief"],
                "enhance": ["improve", "enhance", "better", "polish"],
                "extract_insights": ["insights", "key points", "important", "extract"],
                "questions": ["questions", "ask", "clarify", "explore"]
            }
        }
        
        # Selection statistics
        self.selection_stats = {
            "total_selections": 0,
            "successful_selections": 0,
            "parameter_inferences": 0,
            "fallback_uses": 0,
            "context_matches": 0
        }
        
    def select_tool(
        self, 
        processing_result: EnhancedProcessingResult,
        context: Dict[str, Any] = None,
        user_id: Optional[str] = None
    ) -> ToolSelection:
        """
        Select the best tool for the given processing result and context.
        
        Args:
            processing_result: Result from enhanced language processing
            context: Additional context information
            user_id: Optional user identifier for personalization
            
        Returns:
            Tool selection with inferred parameters
        """
        try:
            self.selection_stats["total_selections"] += 1
            
            # Get candidate tools for the intent
            candidates = self._get_candidate_tools(processing_result.intent)
            
            if not candidates:
                return self._create_fallback_selection(processing_result, "No compatible tools found")
                
            # Score each candidate tool
            scored_tools = []
            for tool_name in candidates:
                score = self._score_tool(tool_name, processing_result, context, user_id)
                scored_tools.append((tool_name, score))
                
            # Sort by score (descending)
            scored_tools.sort(key=lambda x: x[1], reverse=True)
            
            # Select the best tool
            selected_tool, best_score = scored_tools[0]
            alternatives = scored_tools[1:3]  # Top 2 alternatives
            
            # Infer parameters for selected tool
            inferred_params = self._infer_tool_parameters(
                selected_tool, processing_result, context
            )
            
            # Validate parameters
            validation_errors = self._validate_tool_parameters(selected_tool, inferred_params)
            
            # Calculate selection confidence
            confidence = self._calculate_selection_confidence(
                best_score, len(candidates), validation_errors
            )
            
            # Determine selection reason
            reason = self._get_selection_reason(selected_tool, best_score, processing_result)
            
            selection = ToolSelection(
                selected_tool=selected_tool,
                confidence=confidence,
                inferred_parameters=inferred_params,
                alternative_tools=alternatives,
                selection_reason=reason,
                validation_errors=validation_errors
            )
            
            # Update statistics and patterns
            self._update_selection_data(selection, processing_result, context, user_id)
            
            logger.debug(f"Selected tool: {selected_tool} (confidence: {confidence:.2f}, "
                        f"alternatives: {len(alternatives)})")
            
            return selection
            
        except Exception as e:
            logger.error(f"Tool selection failed: {e}")
            return self._create_fallback_selection(processing_result, f"Selection error: {e}")
            
    def _get_candidate_tools(self, intent: Intent) -> List[str]:
        """Get list of tools compatible with the given intent."""
        candidates = []
        
        for tool_name, capability in self.tool_capabilities.items():
            if intent in capability.intent_compatibility:
                # Check if tool is available and enabled
                if self.tool_registry.is_enabled(tool_name):
                    candidates.append(tool_name)
                    
        return candidates
        
    def _score_tool(
        self, 
        tool_name: str, 
        processing_result: EnhancedProcessingResult,
        context: Dict[str, Any],
        user_id: Optional[str]
    ) -> float:
        """Score a tool for selection based on multiple factors."""
        
        score = 0.0
        
        # Base compatibility score
        capability = self.tool_capabilities.get(tool_name)
        if capability:
            # Intent compatibility (primary factor)
            if processing_result.intent in capability.intent_compatibility:
                score += 0.4
                
            # Parameter availability score
            available_params = set(processing_result.parameters.keys())
            required_params = capability.required_parameters
            
            if required_params:
                param_coverage = len(available_params & required_params) / len(required_params)
                score += 0.3 * param_coverage
            else:
                score += 0.3  # No required params
                
            # Performance score
            perf_data = self.tool_performance[tool_name]
            if perf_data["total_attempts"] > 0:
                success_rate = perf_data["success_count"] / perf_data["total_attempts"]
                score += 0.2 * success_rate
            else:
                score += 0.1  # Neutral score for untried tools
                
        # Context compatibility
        if context:
            context_score = self._score_context_compatibility(tool_name, context)
            score += 0.1 * context_score
            
        # User preference score
        if user_id:
            pref_score = self._score_user_preference(tool_name, user_id, processing_result.intent)
            score += 0.1 * pref_score
            
        # Recency bonus (prefer recently successful tools)
        perf_data = self.tool_performance[tool_name]
        if perf_data["last_used"]:
            time_diff = datetime.now() - perf_data["last_used"]
            if time_diff < timedelta(hours=1):
                score += 0.05  # Small bonus for recent successful use
                
        return min(score, 1.0)  # Cap at 1.0
        
    def _infer_tool_parameters(
        self, 
        tool_name: str, 
        processing_result: EnhancedProcessingResult,
        context: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Infer missing parameters for the selected tool."""
        
        # Start with existing parameters
        inferred = processing_result.parameters.copy()
        inferred.update(processing_result.inferred_parameters)
        
        # Get tool requirements
        capability = self.tool_capabilities.get(tool_name)
        if not capability:
            return inferred
            
        required_params = capability.required_parameters
        
        # Infer missing required parameters
        for param in required_params:
            if param not in inferred:
                inferred_value = self._infer_parameter_value(
                    param, tool_name, processing_result, context
                )
                if inferred_value is not None:
                    inferred[param] = inferred_value
                    self.selection_stats["parameter_inferences"] += 1
                    
        return inferred
        
    def _infer_parameter_value(
        self, 
        param_name: str, 
        tool_name: str,
        processing_result: EnhancedProcessingResult,
        context: Dict[str, Any]
    ) -> Optional[Any]:
        """Infer value for a specific parameter."""
        
        original_message = getattr(processing_result, 'raw_text', '')
        
        # File path inference
        if param_name in ["note_path", "file_path"]:
            return self._infer_file_path(original_message, processing_result, context)
            
        # Query inference
        elif param_name == "query":
            return self._infer_search_query(original_message, processing_result)
            
        # Content inference
        elif param_name == "content":
            return self._infer_content(original_message, processing_result, context)
            
        # Task inference
        elif param_name == "task":
            return self._infer_task(original_message, processing_result)
            
        # Generic string inference
        elif param_name in ["title", "name", "description"]:
            return self._infer_string_parameter(param_name, original_message)
            
        return None
        
    def _infer_file_path(
        self, 
        message: str, 
        processing_result: EnhancedProcessingResult,
        context: Dict[str, Any]
    ) -> Optional[str]:
        """Infer file path from message and context."""
        
        # Check processing result file matches first
        if processing_result.file_matches:
            return processing_result.file_matches[0]
            
        # Extract from patterns
        for pattern in self.parameter_patterns["file_path_patterns"]:
            matches = re.findall(pattern, message, re.IGNORECASE)
            if matches:
                filename = matches[0]
                if not filename.endswith('.md'):
                    filename += '.md'
                return filename
                
        # Use context clues
        if context:
            recent_files = context.get("recent_files", [])
            if recent_files:
                return recent_files[0]
                
            # Check if vault path exists and try common patterns
            if self.vault_path and self.vault_path.exists():
                intent = processing_result.intent
                if intent == Intent.READ_NOTE:
                    # Look for common daily/weekly note patterns
                    today = datetime.now()
                    common_names = [
                        f"daily-{today.strftime('%Y-%m-%d')}.md",
                        f"{today.strftime('%Y-%m-%d')}.md",
                        "daily.md",
                        "today.md"
                    ]
                    for name in common_names:
                        if (self.vault_path / name).exists():
                            return name
                            
        return None
        
    def _infer_search_query(self, message: str, processing_result: EnhancedProcessingResult) -> Optional[str]:
        """Infer search query from message."""
        
        # Extract using patterns
        for pattern in self.parameter_patterns["query_patterns"]:
            match = re.search(pattern, message, re.IGNORECASE)
            if match:
                return match.group(1).strip()
                
        # Fallback: use entire message minus command words
        query_words = re.sub(r'\b(search|find|look|show|get|about|for|me|my)\b', '', message, flags=re.IGNORECASE)
        query = re.sub(r'\s+', ' ', query_words).strip()
        
        if len(query) > 2:  # At least 3 characters
            return query
            
        return None
        
    def _infer_content(
        self, 
        message: str, 
        processing_result: EnhancedProcessingResult,
        context: Dict[str, Any]
    ) -> Optional[str]:
        """Infer content parameter."""
        
        # For AI processing tools, try to get content from file
        if processing_result.intent in [Intent.SUMMARIZE, Intent.ENHANCE, Intent.EXTRACT_INSIGHTS]:
            # If we have a note_path, read its content
            note_path = processing_result.parameters.get('note_path')
            if note_path and self.vault_path:
                file_path = self.vault_path / note_path
                if file_path.exists():
                    try:
                        return file_path.read_text(encoding='utf-8')
                    except Exception as e:
                        logger.warning(f"Could not read file {file_path}: {e}")
                        
        # For write operations, extract content from quotes or after keywords
        if processing_result.intent == Intent.WRITE_NOTE:
            # Look for quoted content
            quoted = re.findall(r'["\']([^"\']{10,})["\']', message)
            if quoted:
                return quoted[0]
                
            # Look for content after "about", "containing", etc.
            content_patterns = [
                r'about\s+(.{10,})',
                r'containing\s+(.{10,})',
                r'with\s+(.{10,})'
            ]
            for pattern in content_patterns:
                match = re.search(pattern, message, re.IGNORECASE)
                if match:
                    return match.group(1).strip()
                    
        return None
        
    def _infer_task(self, message: str, processing_result: EnhancedProcessingResult) -> Optional[str]:
        """Infer AI processing task."""
        
        # Check intent first
        intent_task_map = {
            Intent.SUMMARIZE: "summarize",
            Intent.ENHANCE: "enhance",
            Intent.EXTRACT_INSIGHTS: "extract_insights",
            Intent.GENERATE_QUESTIONS: "questions"
        }
        
        if processing_result.intent in intent_task_map:
            return intent_task_map[processing_result.intent]
            
        # Check message for task keywords
        message_lower = message.lower()
        for task, keywords in self.parameter_patterns["task_patterns"].items():
            if any(keyword in message_lower for keyword in keywords):
                return task
                
        # Default to enhance for unknown AI tasks
        return "enhance"
        
    def _infer_string_parameter(self, param_name: str, message: str) -> Optional[str]:
        """Infer generic string parameter."""
        
        # Look for quoted strings
        quoted = re.findall(r'["\']([^"\']+)["\']', message)
        if quoted:
            return quoted[0]
            
        # Extract based on parameter name
        if param_name == "title":
            # Look for patterns like "called X", "named Y", "title Z"
            patterns = [
                r'(?:called|named|title)\s+(.+)',
                r'(?:create|make|new)\s+(.+?)(?:\s+(?:about|with|containing)|$)'
            ]
            for pattern in patterns:
                match = re.search(pattern, message, re.IGNORECASE)
                if match:
                    return match.group(1).strip()
                    
        return None
        
    def _validate_tool_parameters(self, tool_name: str, parameters: Dict[str, Any]) -> List[str]:
        """Validate tool parameters and return list of validation errors."""
        
        errors = []
        capability = self.tool_capabilities.get(tool_name)
        
        if not capability:
            errors.append(f"Unknown tool: {tool_name}")
            return errors
            
        # Check required parameters
        missing_required = capability.required_parameters - set(parameters.keys())
        for param in missing_required:
            errors.append(f"Missing required parameter: {param}")
            
        # Validate parameter values
        for param, value in parameters.items():
            if param == "note_path" and value:
                # Validate file path
                if not isinstance(value, str):
                    errors.append(f"note_path must be string, got {type(value)}")
                elif not value.endswith('.md'):
                    errors.append(f"note_path should end with .md: {value}")
                    
            elif param == "query" and value:
                if not isinstance(value, str) or len(value.strip()) < 2:
                    errors.append(f"query must be non-empty string: {value}")
                    
            elif param == "content" and value:
                if not isinstance(value, str):
                    errors.append(f"content must be string, got {type(value)}")
                    
        return errors
        
    def _calculate_selection_confidence(
        self, 
        best_score: float, 
        candidate_count: int, 
        validation_errors: List[str]
    ) -> float:
        """Calculate confidence in tool selection."""
        
        confidence = best_score
        
        # Reduce confidence if there are validation errors
        if validation_errors:
            confidence *= 0.7
            
        # Reduce confidence if best score is low
        if best_score < 0.5:
            confidence *= 0.8
            
        # Boost confidence if there are few candidates (less ambiguity)
        if candidate_count == 1:
            confidence = min(1.0, confidence + 0.1)
        elif candidate_count > 5:
            confidence *= 0.9
            
        return confidence
        
    def _get_selection_reason(
        self, 
        tool_name: str, 
        score: float, 
        processing_result: EnhancedProcessingResult
    ) -> str:
        """Get human-readable reason for tool selection."""
        
        reasons = []
        
        # Intent compatibility
        capability = self.tool_capabilities.get(tool_name)
        if capability and processing_result.intent in capability.intent_compatibility:
            reasons.append(f"compatible with {processing_result.intent.value}")
            
        # Performance
        perf_data = self.tool_performance[tool_name]
        if perf_data["total_attempts"] > 0:
            success_rate = perf_data["success_count"] / perf_data["total_attempts"]
            if success_rate > 0.8:
                reasons.append("high success rate")
            elif success_rate > 0.5:
                reasons.append("good performance")
                
        # Parameter coverage
        if set(processing_result.parameters.keys()) & capability.required_parameters:
            reasons.append("required parameters available")
            
        if not reasons:
            reasons.append("best available option")
            
        return f"Selected {tool_name}: {', '.join(reasons)}"
        
    def _score_context_compatibility(self, tool_name: str, context: Dict[str, Any]) -> float:
        """Score tool compatibility with current context."""
        
        score = 0.5  # Neutral baseline
        
        # Check context patterns
        context_key = self._extract_context_key(context)
        if context_key in self.context_patterns:
            tool_usage = self.context_patterns[context_key]
            if tool_name in tool_usage:
                # Normalize usage count to 0-1 range
                max_usage = max(tool_usage.values()) if tool_usage else 1
                score = tool_usage[tool_name] / max_usage
                
        return score
        
    def _score_user_preference(self, tool_name: str, user_id: str, intent: Intent) -> float:
        """Score tool based on user preferences and patterns."""
        
        # Get user's tool usage for this intent
        user_prefs = self.user_tool_preferences[user_id]
        intent_key = f"{intent.value}:{tool_name}"
        
        if intent_key in user_prefs:
            # Normalize to 0-1 range
            max_usage = max(user_prefs.values()) if user_prefs else 1
            return user_prefs[intent_key] / max_usage
            
        return 0.5  # Neutral for unknown preferences
        
    def _extract_context_key(self, context: Dict[str, Any]) -> str:
        """Extract key from context for pattern matching."""
        
        # Create a simple context signature
        vault_type = context.get("vault_type", "unknown")
        time_of_day = context.get("time_of_day", "unknown")
        
        return f"{vault_type}:{time_of_day}"
        
    def _update_selection_data(
        self, 
        selection: ToolSelection,
        processing_result: EnhancedProcessingResult,
        context: Dict[str, Any],
        user_id: Optional[str]
    ) -> None:
        """Update selection patterns and statistics."""
        
        # Update context patterns
        if context:
            context_key = self._extract_context_key(context)
            self.context_patterns[context_key][selection.selected_tool] += 1
            
        # Update user preferences
        if user_id:
            intent_key = f"{processing_result.intent.value}:{selection.selected_tool}"
            self.user_tool_preferences[user_id][intent_key] += 1
            
        # Update statistics
        if selection.confidence > 0.7:
            self.selection_stats["successful_selections"] += 1
            
        if context:
            self.selection_stats["context_matches"] += 1
            
    def record_tool_execution_result(
        self, 
        tool_name: str, 
        success: bool, 
        execution_time: float = 0.0,
        error_message: Optional[str] = None,
        context: Dict[str, Any] = None
    ) -> None:
        """Record the result of tool execution for performance tracking."""
        
        perf_data = self.tool_performance[tool_name]
        perf_data["total_attempts"] += 1
        perf_data["last_used"] = datetime.now()
        
        if success:
            perf_data["success_count"] += 1
            
            # Update average execution time
            if execution_time > 0:
                current_avg = perf_data["avg_execution_time"]
                total_success = perf_data["success_count"]
                perf_data["avg_execution_time"] = (current_avg * (total_success - 1) + execution_time) / total_success
                
            # Record successful context
            if context:
                context_key = self._extract_context_key(context)
                perf_data["success_contexts"].append(context_key)
                # Keep only recent contexts
                perf_data["success_contexts"] = perf_data["success_contexts"][-10:]
                
        else:
            # Track error patterns
            if error_message:
                error_type = self._categorize_error(error_message)
                perf_data["error_patterns"][error_type] += 1
                
    def _categorize_error(self, error_message: str) -> str:
        """Categorize error message for pattern tracking."""
        
        error_lower = error_message.lower()
        
        if "not found" in error_lower or "does not exist" in error_lower:
            return "file_not_found"
        elif "permission" in error_lower or "access" in error_lower:
            return "permission_denied"
        elif "timeout" in error_lower:
            return "timeout"
        elif "parameter" in error_lower or "argument" in error_lower:
            return "parameter_error"
        else:
            return "unknown_error"
            
    def _create_fallback_selection(self, processing_result: EnhancedProcessingResult, reason: str) -> ToolSelection:
        """Create fallback tool selection."""
        
        self.selection_stats["fallback_uses"] += 1
        
        # Try to find any available tool as fallback
        fallback_tool = "read_note"  # Default safe option
        available_tools = self.tool_registry.list_tools()
        
        if available_tools:
            fallback_tool = available_tools[0]
            
        return ToolSelection(
            selected_tool=fallback_tool,
            confidence=0.1,
            inferred_parameters={},
            alternative_tools=[],
            selection_reason=f"Fallback selection: {reason}",
            validation_errors=[reason]
        )
        
    def _initialize_tool_capabilities(self) -> Dict[str, ToolCapability]:
        """Initialize tool capability mappings."""
        
        return {
            "read_note": ToolCapability(
                tool_name="read_note",
                intent_compatibility=[Intent.READ_NOTE],
                required_parameters={"note_path"},
                optional_parameters=set()
            ),
            "write_note": ToolCapability(
                tool_name="write_note",
                intent_compatibility=[Intent.WRITE_NOTE],
                required_parameters={"note_path", "content"},
                optional_parameters={"overwrite"}
            ),
            "update_note": ToolCapability(
                tool_name="update_note",
                intent_compatibility=[Intent.UPDATE_NOTE],
                required_parameters={"note_path"},
                optional_parameters={"content", "append"}
            ),
            "search_notes": ToolCapability(
                tool_name="search_notes",
                intent_compatibility=[Intent.SEARCH_NOTES],
                required_parameters={"query"},
                optional_parameters={"case_sensitive", "max_results"}
            ),
            "vector_search": ToolCapability(
                tool_name="vector_search",
                intent_compatibility=[Intent.VECTOR_SEARCH, Intent.SEARCH_NOTES],
                required_parameters={"query"},
                optional_parameters={"max_results", "similarity_threshold"}
            ),
            "list_notes": ToolCapability(
                tool_name="list_notes",
                intent_compatibility=[Intent.LIST_NOTES],
                required_parameters=set(),
                optional_parameters={"max_results", "sort_by"}
            ),
            "ai_process": ToolCapability(
                tool_name="ai_process",
                intent_compatibility=[
                    Intent.SUMMARIZE, Intent.ENHANCE, 
                    Intent.EXTRACT_INSIGHTS, Intent.GENERATE_QUESTIONS
                ],
                required_parameters={"content", "task"},
                optional_parameters={"model", "template_id"}
            )
        }
        
    def get_tool_performance_stats(self) -> Dict[str, Any]:
        """Get tool performance statistics."""
        
        stats = {}
        for tool_name, perf_data in self.tool_performance.items():
            if perf_data["total_attempts"] > 0:
                success_rate = perf_data["success_count"] / perf_data["total_attempts"]
                stats[tool_name] = {
                    "success_rate": success_rate,
                    "total_attempts": perf_data["total_attempts"],
                    "avg_execution_time": perf_data["avg_execution_time"],
                    "common_errors": dict(perf_data["error_patterns"].most_common(3))
                }
                
        return stats
        
    def get_selection_stats(self) -> Dict[str, Any]:
        """Get tool selection statistics."""
        return self.selection_stats.copy()
        
    def reset_performance_data(self, tool_name: Optional[str] = None) -> None:
        """Reset performance data for a specific tool or all tools."""
        
        if tool_name:
            if tool_name in self.tool_performance:
                del self.tool_performance[tool_name]
                logger.debug(f"Reset performance data for {tool_name}")
        else:
            self.tool_performance.clear()
            logger.debug("Reset all tool performance data")
            
    def export_learning_data(self) -> Dict[str, Any]:
        """Export learned patterns and performance data."""
        
        return {
            "tool_performance": dict(self.tool_performance),
            "context_patterns": dict(self.context_patterns),
            "user_preferences": dict(self.user_tool_preferences),
            "selection_stats": self.selection_stats,
            "export_timestamp": datetime.now().isoformat()
        }