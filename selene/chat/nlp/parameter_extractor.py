"""
Parameter Extraction for SELENE chatbot.

This module extracts specific parameters from user messages
for tool execution, with advanced natural language understanding.
"""

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Union

from loguru import logger

from .intent_classifier import Intent, IntentResult


@dataclass
class ParameterResult:
    """Result of parameter extraction."""
    parameters: Dict[str, Any]
    confidence: float
    missing_required: List[str]
    
    @property
    def is_complete(self) -> bool:
        """Check if all required parameters are present."""
        return len(self.missing_required) == 0
        
    @property
    def is_confident(self) -> bool:
        """Check if extraction is confident."""
        return self.confidence > 0.7


class ParameterExtractor:
    """
    Extract tool parameters from natural language messages.
    
    This extractor uses:
    1. Pattern matching for structured extraction
    2. Context-aware parameter inference
    3. Default value handling
    4. Validation and normalization
    """
    
    def __init__(self, vault_path: Optional[Path] = None):
        """
        Initialize parameter extractor.
        
        Args:
            vault_path: Current vault path for file resolution
        """
        self.vault_path = vault_path
        self._setup_extractors()
        
    def _setup_extractors(self) -> None:
        """Set up parameter extraction patterns."""
        # Tool parameter requirements
        self.tool_parameters = {
            "read_note": {"required": ["note_path"], "optional": []},
            "write_note": {"required": ["note_path", "content"], "optional": []},
            "update_note": {"required": ["note_path", "content"], "optional": ["append"]},
            "search_notes": {"required": ["query"], "optional": ["limit"]},
            "vector_search": {"required": ["query"], "optional": ["results", "min_score"]},
            "list_notes": {"required": [], "optional": ["pattern", "limit"]},
            "ai_process": {"required": ["content", "task"], "optional": ["model", "template_id"]},
        }
        
        # File path extraction patterns
        self.file_patterns = [
            r'(?:note|file)\s+(?:called\s+)?["\']([^"\']+)["\']',
            r'(?:note|file)\s+(?:called\s+)?(\w+(?:\s+\w+)*)',
            r'["\']([^"\']+\.md)["\']',
            r'\b(\w+\.md)\b',
            r'(?:in|from|to)\s+["\']([^"\']+)["\']',
            r'(?:in|from|to)\s+(\w+(?:\s+\w+)*)',
        ]
        
        # Content extraction patterns
        self.content_patterns = [
            r'(?:write|add|append|insert)[\s\S]*?["\']([^"\']+)["\']',
            r'(?:content|text|body)[:\s]+["\']([^"\']+)["\']',
            r'saying\s+["\']([^"\']+)["\']',
            r'with\s+["\']([^"\']+)["\']',
            r'(?:write|add|append|insert)[\s\S]*?:\s*(.+?)(?:\s*$|\s*\.|$)',
            r'(?:content|text|body)[:\s]+(.+?)(?:\s*$|\s*\.|$)',
        ]
        
        # Query extraction patterns
        self.query_patterns = [
            r'(?:search|find|look)\s+(?:for\s+)?["\']([^"\']+)["\']',
            r'(?:about|containing|with)\s+["\']([^"\']+)["\']',
            r'(?:search|find|look)\s+(?:for\s+)?(\w+(?:\s+\w+)*)',
            r'(?:about|containing|with)\s+(\w+(?:\s+\w+)*)',
        ]
        
    def extract_parameters(self, intent_result: IntentResult) -> ParameterResult:
        """
        Extract parameters for tool execution from intent result.
        
        Args:
            intent_result: Classified intent with entities
            
        Returns:
            ParameterResult with extracted parameters
        """
        intent = intent_result.intent
        text = intent_result.raw_text
        entities = intent_result.entities
        
        # Get tool name from intent
        tool_name = self._intent_to_tool_name(intent)
        if not tool_name:
            return ParameterResult(
                parameters={},
                confidence=0.0,
                missing_required=[]
            )
            
        # Extract parameters based on tool requirements
        parameters = {}
        confidence = 0.0
        
        if tool_name in self.tool_parameters:
            parameters, confidence = self._extract_tool_parameters(
                text, intent, entities, tool_name
            )
            
        # Check for missing required parameters
        required_params = self.tool_parameters.get(tool_name, {}).get("required", [])
        missing_required = [p for p in required_params if p not in parameters]
        
        return ParameterResult(
            parameters=parameters,
            confidence=confidence,
            missing_required=missing_required
        )
        
    def _intent_to_tool_name(self, intent: Intent) -> Optional[str]:
        """Convert intent to tool name."""
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
        
    def _extract_tool_parameters(self, text: str, intent: Intent, entities: Dict[str, Any], tool_name: str) -> tuple[Dict[str, Any], float]:
        """Extract parameters for specific tool."""
        parameters = {}
        confidence_scores = []
        
        if tool_name == "read_note":
            note_path, conf = self._extract_note_path(text, entities)
            if note_path:
                parameters["note_path"] = note_path
                confidence_scores.append(conf)
                
        elif tool_name == "write_note":
            note_path, conf1 = self._extract_note_path(text, entities)
            content, conf2 = self._extract_content(text, entities)
            
            if note_path:
                parameters["note_path"] = note_path
                confidence_scores.append(conf1)
                
            if content:
                parameters["content"] = content
                confidence_scores.append(conf2)
            else:
                # Default content for new notes
                parameters["content"] = f"# {Path(note_path).stem if note_path else 'New Note'}\n\nCreated from chat.\n\n"
                confidence_scores.append(0.5)
                
        elif tool_name == "update_note":
            note_path, conf1 = self._extract_note_path(text, entities)
            content, conf2 = self._extract_content(text, entities)
            
            if note_path:
                parameters["note_path"] = note_path
                confidence_scores.append(conf1)
                
            if content:
                parameters["content"] = content
                confidence_scores.append(conf2)
                
            # Check for append vs replace
            if any(word in text.lower() for word in ["append", "add to", "add at end"]):
                parameters["append"] = True
                
        elif tool_name in ["search_notes", "vector_search"]:
            query, conf = self._extract_query(text, entities)
            if query:
                parameters["query"] = query
                confidence_scores.append(conf)
                
            # Extract optional parameters
            if tool_name == "vector_search":
                results = self._extract_number(text, ["results", "limit", "max"], default=5)
                if results:
                    parameters["results"] = results
                    
        elif tool_name == "list_notes":
            # Extract optional pattern
            pattern = self._extract_pattern(text)
            if pattern:
                parameters["pattern"] = pattern
                
        elif tool_name == "ai_process":
            # Extract content (note path) and task
            note_path, conf1 = self._extract_note_path(text, entities)
            task, conf2 = self._extract_ai_task(intent)
            
            if note_path:
                parameters["note_path"] = note_path  # Will be converted to content by tool
                confidence_scores.append(conf1)
                
            if task:
                parameters["task"] = task
                confidence_scores.append(conf2)
                
        # Calculate overall confidence
        if confidence_scores:
            confidence = sum(confidence_scores) / len(confidence_scores)
        else:
            confidence = 0.0
            
        return parameters, confidence
        
    def _extract_note_path(self, text: str, entities: Dict[str, Any]) -> tuple[Optional[str], float]:
        """Extract note path from text."""
        # Check entities first (high confidence)
        if "note_path" in entities:
            note_path = entities["note_path"]
            return self._normalize_note_path(note_path), 0.9
            
        # Try file patterns
        for pattern in self.file_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                note_path = match.group(1)
                return self._normalize_note_path(note_path), 0.8
                
        return None, 0.0
        
    def _extract_content(self, text: str, entities: Dict[str, Any]) -> tuple[Optional[str], float]:
        """Extract content from text."""
        # Try content patterns
        for pattern in self.content_patterns:
            match = re.search(pattern, text, re.IGNORECASE | re.DOTALL)
            if match:
                content = match.group(1).strip()
                return content, 0.8
                
        # Look for content after common phrases
        content_phrases = [
            r'(?:write|add|append|insert)[\s\S]*?:\s*(.+)',
            r'(?:content|text|body)[\s\S]*?:\s*(.+)',
            r'saying\s+(.+)',
            r'with\s+(.+)',
        ]
        
        for pattern in content_phrases:
            match = re.search(pattern, text, re.IGNORECASE | re.DOTALL)
            if match:
                content = match.group(1).strip()
                # Remove trailing punctuation and quotes
                content = re.sub(r'["\']$', '', content)
                return content, 0.6
                
        return None, 0.0
        
    def _extract_query(self, text: str, entities: Dict[str, Any]) -> tuple[Optional[str], float]:
        """Extract search query from text."""
        # Check entities first
        if "query" in entities:
            return entities["query"], 0.9
            
        # Try query patterns
        for pattern in self.query_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                query = match.group(1).strip()
                return query, 0.8
                
        return None, 0.0
        
    def _extract_pattern(self, text: str) -> Optional[str]:
        """Extract file pattern from text."""
        # Look for file patterns
        pattern_matches = re.findall(r'\*\.\w+|\*\w+\*|\w+\*', text)
        if pattern_matches:
            return pattern_matches[0]
            
        return None
        
    def _extract_number(self, text: str, keywords: List[str], default: Optional[int] = None) -> Optional[int]:
        """Extract number following specific keywords."""
        for keyword in keywords:
            pattern = rf'\b{keyword}\s+(\d+)\b'
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                return int(match.group(1))
                
        return default
        
    def _extract_ai_task(self, intent: Intent) -> tuple[Optional[str], float]:
        """Extract AI processing task from intent."""
        intent_to_task = {
            Intent.SUMMARIZE: "summarize",
            Intent.ENHANCE: "enhance",
            Intent.EXTRACT_INSIGHTS: "extract_insights",
            Intent.GENERATE_QUESTIONS: "questions",
        }
        
        task = intent_to_task.get(intent)
        if task:
            return task, 1.0
            
        return None, 0.0
        
    def _normalize_note_path(self, note_path: str) -> str:
        """Normalize note path to standard format."""
        # Remove quotes
        note_path = note_path.strip('\'"')
        
        # Add .md extension if missing
        if not note_path.endswith('.md'):
            note_path += '.md'
            
        # Handle relative paths
        if self.vault_path and not Path(note_path).is_absolute():
            full_path = self.vault_path / note_path
            if full_path.exists():
                return str(full_path)
                
        return note_path
        
    def set_vault_path(self, vault_path: Optional[Path]) -> None:
        """Set the vault path for file resolution."""
        self.vault_path = vault_path
        
    def get_parameter_suggestions(self, tool_name: str, current_params: Dict[str, Any]) -> List[str]:
        """Get suggestions for missing parameters."""
        suggestions = []
        
        if tool_name not in self.tool_parameters:
            return suggestions
            
        required = self.tool_parameters[tool_name]["required"]
        
        for param in required:
            if param not in current_params:
                if param == "note_path":
                    suggestions.append("Please specify the note name or path")
                elif param == "content":
                    suggestions.append("Please specify the content to write")
                elif param == "query":
                    suggestions.append("Please specify what to search for")
                else:
                    suggestions.append(f"Please specify {param}")
                    
        return suggestions