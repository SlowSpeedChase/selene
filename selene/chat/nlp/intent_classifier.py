"""
Intent Classification for SELENE chatbot.

This module provides intent recognition capabilities to understand
what the user wants to do with their vault.
"""

import re
from dataclasses import dataclass
from enum import Enum
from typing import Dict, List, Optional, Tuple, Any

from loguru import logger


class Intent(Enum):
    """Possible user intents."""
    # File operations
    READ_NOTE = "read_note"
    WRITE_NOTE = "write_note"
    UPDATE_NOTE = "update_note"
    DELETE_NOTE = "delete_note"
    
    # Search operations
    SEARCH_NOTES = "search_notes"
    VECTOR_SEARCH = "vector_search"
    LIST_NOTES = "list_notes"
    
    # AI operations
    SUMMARIZE = "summarize"
    ENHANCE = "enhance"
    EXTRACT_INSIGHTS = "extract_insights"
    GENERATE_QUESTIONS = "generate_questions"
    
    # Vault operations
    VAULT_INFO = "vault_info"
    VAULT_STATS = "vault_stats"
    
    # General
    HELP = "help"
    GREETING = "greeting"
    UNKNOWN = "unknown"


@dataclass
class IntentResult:
    """Result of intent classification."""
    intent: Intent
    confidence: float
    entities: Dict[str, Any]
    raw_text: str
    
    @property
    def is_confident(self) -> bool:
        """Check if classification is confident (>0.7)."""
        return self.confidence > 0.7


class IntentClassifier:
    """
    Intent classification using pattern matching and keywords.
    
    This classifier uses a combination of:
    1. Keyword matching
    2. Pattern recognition
    3. Context analysis
    4. Confidence scoring
    """
    
    def __init__(self):
        """Initialize the intent classifier."""
        self._setup_patterns()
        
    def _setup_patterns(self) -> None:
        """Set up intent recognition patterns."""
        self.intent_patterns = {
            Intent.READ_NOTE: [
                # Direct reading patterns
                r'\b(read|show|open|display|view)\s+(?:the\s+)?(?:note|file)\s+(?:called\s+)?["\']?([^"\']+)["\']?',
                r'\b(read|show|open|display|view)\s+["\']?([^"\']+\.md)["\']?',
                r'\bshow\s+me\s+(?:the\s+)?(?:note|file)\s+(?:called\s+)?["\']?([^"\']+)["\']?',
                r'\bwhat(?:\'s|\s+is)\s+in\s+(?:the\s+)?(?:note|file)\s+["\']?([^"\']+)["\']?',
                r'\bcontents?\s+of\s+(?:the\s+)?(?:note|file)\s+["\']?([^"\']+)["\']?',
            ],
            
            Intent.WRITE_NOTE: [
                r'\b(create|write|make|new)\s+(?:a\s+)?(?:note|file)\s+(?:called\s+)?["\']?([^"\']+)["\']?',
                r'\b(create|write|make|new)\s+["\']?([^"\']+\.md)["\']?',
                r'\bstart\s+(?:a\s+)?(?:new\s+)?(?:note|file)\s+(?:called\s+)?["\']?([^"\']+)["\']?',
                r'\badd\s+(?:a\s+)?(?:note|file)\s+(?:called\s+)?["\']?([^"\']+)["\']?',
            ],
            
            Intent.UPDATE_NOTE: [
                r'\b(update|edit|modify|change)\s+(?:the\s+)?(?:note|file)\s+(?:called\s+)?["\']?([^"\']+)["\']?',
                r'\b(append|add)\s+(?:to\s+)?(?:the\s+)?(?:note|file)\s+["\']?([^"\']+)["\']?',
                r'\bmodify\s+(?:the\s+)?(?:note|file)\s+["\']?([^"\']+)["\']?',
            ],
            
            Intent.SEARCH_NOTES: [
                r'\b(search|find|look)\s+(?:for\s+)?(?:notes?\s+)?(?:about\s+|containing\s+|with\s+)?["\']?([^"\']+)["\']?',
                r'\bfind\s+(?:all\s+)?(?:notes?\s+)?(?:about\s+|containing\s+|with\s+)?["\']?([^"\']+)["\']?',
                r'\bwhere\s+(?:are\s+)?(?:notes?\s+)?(?:about\s+|containing\s+|with\s+)?["\']?([^"\']+)["\']?',
                r'\bshow\s+(?:me\s+)?(?:all\s+)?(?:notes?\s+)?(?:about\s+|containing\s+|with\s+)?["\']?([^"\']+)["\']?',
            ],
            
            Intent.VECTOR_SEARCH: [
                r'\b(semantic\s+search|vector\s+search|similar\s+to)\s+["\']?([^"\']+)["\']?',
                r'\bfind\s+(?:notes?\s+)?(?:similar\s+to|related\s+to)\s+["\']?([^"\']+)["\']?',
                r'\bsearch\s+(?:semantically|by\s+meaning)\s+(?:for\s+)?["\']?([^"\']+)["\']?',
            ],
            
            Intent.LIST_NOTES: [
                r'\b(list|show)\s+(?:all\s+)?(?:my\s+)?(?:notes?|files?)',
                r'\bwhat\s+(?:notes?|files?)\s+(?:do\s+I\s+have|are\s+there)',
                r'\bshow\s+(?:me\s+)?(?:all\s+)?(?:my\s+)?(?:notes?|files?)',
                r'\b(?:all\s+)?(?:my\s+)?(?:notes?|files?)\s+(?:list|please)',
            ],
            
            Intent.SUMMARIZE: [
                r'\b(summarize|summary)\s+(?:the\s+)?(?:note|file)\s+["\']?([^"\']+)["\']?',
                r'\bmake\s+(?:a\s+)?(?:summary|overview)\s+of\s+(?:the\s+)?(?:note|file)\s+["\']?([^"\']+)["\']?',
                r'\bwhat\s+(?:are\s+)?(?:the\s+)?(?:main\s+)?(?:points|ideas)\s+(?:in\s+)?(?:the\s+)?(?:note|file)\s+["\']?([^"\']+)["\']?',
            ],
            
            Intent.ENHANCE: [
                r'\b(enhance|improve|polish)\s+(?:the\s+)?(?:note|file)\s+["\']?([^"\']+)["\']?',
                r'\bmake\s+(?:the\s+)?(?:note|file)\s+["\']?([^"\']+)["\']?\s+(?:better|clearer)',
                r'\bclean\s+up\s+(?:the\s+)?(?:note|file)\s+["\']?([^"\']+)["\']?',
            ],
            
            Intent.EXTRACT_INSIGHTS: [
                r'\b(insights?|key\s+points?|important\s+ideas?)\s+(?:from\s+)?(?:the\s+)?(?:note|file)\s+["\']?([^"\']+)["\']?',
                r'\bextract\s+(?:key\s+)?(?:insights?|ideas?|points?)\s+(?:from\s+)?(?:the\s+)?(?:note|file)\s+["\']?([^"\']+)["\']?',
                r'\bwhat\s+(?:are\s+)?(?:the\s+)?(?:key\s+)?(?:insights?|takeaways?)\s+(?:from\s+)?(?:the\s+)?(?:note|file)\s+["\']?([^"\']+)["\']?',
            ],
            
            Intent.GENERATE_QUESTIONS: [
                r'\b(questions?|queries?)\s+(?:about\s+)?(?:the\s+)?(?:note|file)\s+["\']?([^"\']+)["\']?',
                r'\bgenerate\s+(?:some\s+)?(?:questions?|queries?)\s+(?:about\s+)?(?:the\s+)?(?:note|file)\s+["\']?([^"\']+)["\']?',
                r'\bwhat\s+(?:questions?|queries?)\s+(?:could\s+I\s+ask|should\s+I\s+think)\s+(?:about\s+)?(?:the\s+)?(?:note|file)\s+["\']?([^"\']+)["\']?',
            ],
            
            Intent.VAULT_INFO: [
                r'\b(vault|repository)\s+(?:info|information|details|stats)',
                r'\bwhat\s+(?:vault|repository)\s+(?:am\s+I\s+in|is\s+this)',
                r'\bshow\s+(?:me\s+)?(?:vault|repository)\s+(?:info|information|details)',
                r'\btell\s+me\s+about\s+(?:this\s+)?(?:vault|repository)',
            ],
            
            Intent.HELP: [
                r'\b(help|usage|how\s+to|what\s+can\s+you\s+do)',
                r'\bshow\s+(?:me\s+)?(?:help|commands)',
                r'\bwhat\s+(?:can\s+you\s+do|commands\s+are\s+available)',
            ],
            
            Intent.GREETING: [
                r'\b(hello|hi|hey|good\s+morning|good\s+afternoon|good\s+evening)',
                r'\bwhat\'s\s+up',
                r'\bhow\s+are\s+you',
            ],
        }
        
        # Intent keywords for confidence scoring
        self.intent_keywords = {
            Intent.READ_NOTE: ["read", "show", "open", "display", "view", "contents"],
            Intent.WRITE_NOTE: ["create", "write", "make", "new", "start", "add"],
            Intent.UPDATE_NOTE: ["update", "edit", "modify", "change", "append"],
            Intent.SEARCH_NOTES: ["search", "find", "look", "where", "containing"],
            Intent.VECTOR_SEARCH: ["semantic", "vector", "similar", "related", "meaning"],
            Intent.LIST_NOTES: ["list", "show", "all", "notes", "files"],
            Intent.SUMMARIZE: ["summarize", "summary", "overview", "main", "points"],
            Intent.ENHANCE: ["enhance", "improve", "polish", "better", "cleaner"],
            Intent.EXTRACT_INSIGHTS: ["insights", "key", "important", "extract", "takeaways"],
            Intent.GENERATE_QUESTIONS: ["questions", "queries", "generate", "ask"],
            Intent.VAULT_INFO: ["vault", "repository", "info", "information", "details"],
            Intent.HELP: ["help", "usage", "commands", "how"],
            Intent.GREETING: ["hello", "hi", "hey", "morning", "afternoon", "evening"],
        }
        
    def classify(self, text: str) -> IntentResult:
        """
        Classify user intent from text.
        
        Args:
            text: User message text
            
        Returns:
            IntentResult with classified intent and confidence
        """
        text_lower = text.lower().strip()
        
        # Check for direct matches first
        direct_intent = self._check_direct_patterns(text_lower)
        if direct_intent:
            return direct_intent
            
        # Fall back to keyword-based classification
        keyword_intent = self._classify_by_keywords(text_lower)
        if keyword_intent:
            return keyword_intent
            
        # Default to unknown
        return IntentResult(
            intent=Intent.UNKNOWN,
            confidence=0.0,
            entities={},
            raw_text=text
        )
        
    def _check_direct_patterns(self, text: str) -> Optional[IntentResult]:
        """Check for direct pattern matches."""
        for intent, patterns in self.intent_patterns.items():
            for pattern in patterns:
                match = re.search(pattern, text, re.IGNORECASE)
                if match:
                    entities = {}
                    
                    # Extract entities based on pattern groups
                    if match.groups():
                        try:
                            # Common entity extraction - find the last non-empty group
                            last_group = None
                            for i in range(len(match.groups()), 0, -1):
                                group_val = match.group(i)
                                if group_val and group_val.strip():
                                    last_group = group_val.strip()
                                    break
                            
                            if last_group:
                                if intent in [Intent.READ_NOTE, Intent.WRITE_NOTE, Intent.UPDATE_NOTE]:
                                    entities['note_path'] = last_group
                                elif intent in [Intent.SEARCH_NOTES, Intent.VECTOR_SEARCH]:
                                    entities['query'] = last_group
                                elif intent in [Intent.SUMMARIZE, Intent.ENHANCE, Intent.EXTRACT_INSIGHTS, Intent.GENERATE_QUESTIONS]:
                                    entities['note_path'] = last_group
                        except IndexError:
                            # Skip entity extraction if group access fails
                            pass
                            
                    return IntentResult(
                        intent=intent,
                        confidence=0.9,  # High confidence for direct pattern matches
                        entities=entities,
                        raw_text=text
                    )
                    
        return None
        
    def _classify_by_keywords(self, text: str) -> Optional[IntentResult]:
        """Classify intent by keyword matching."""
        intent_scores = {}
        
        for intent, keywords in self.intent_keywords.items():
            score = 0
            for keyword in keywords:
                if keyword in text:
                    score += 1
                    
            if score > 0:
                # Normalize score by number of keywords
                normalized_score = score / len(keywords)
                intent_scores[intent] = normalized_score
                
        if not intent_scores:
            return None
            
        # Get best scoring intent
        best_intent = max(intent_scores, key=intent_scores.get)
        confidence = intent_scores[best_intent]
        
        # Extract basic entities for keyword-based classification
        entities = self._extract_basic_entities(text, best_intent)
        
        return IntentResult(
            intent=best_intent,
            confidence=confidence,
            entities=entities,
            raw_text=text
        )
        
    def _extract_basic_entities(self, text: str, intent: Intent) -> Dict[str, Any]:
        """Extract basic entities from text based on intent."""
        entities = {}
        
        # Extract quoted strings as potential note names or queries
        quoted_matches = re.findall(r'["\']([^"\']+)["\']', text)
        if quoted_matches:
            if intent in [Intent.READ_NOTE, Intent.WRITE_NOTE, Intent.UPDATE_NOTE]:
                entities['note_path'] = quoted_matches[0]
            elif intent in [Intent.SEARCH_NOTES, Intent.VECTOR_SEARCH]:
                entities['query'] = quoted_matches[0]
                
        # Extract .md file patterns
        md_matches = re.findall(r'\b(\w+\.md)\b', text)
        if md_matches and intent in [Intent.READ_NOTE, Intent.WRITE_NOTE, Intent.UPDATE_NOTE]:
            entities['note_path'] = md_matches[0]
            
        # Extract search terms after common prepositions
        search_patterns = [
            r'\b(?:for|about|containing|with)\s+(.+?)(?:\s+in|\s*$)',
            r'\bfind\s+(.+?)(?:\s+in|\s*$)',
            r'\bsearch\s+(.+?)(?:\s+in|\s*$)'
        ]
        
        if intent in [Intent.SEARCH_NOTES, Intent.VECTOR_SEARCH]:
            for pattern in search_patterns:
                match = re.search(pattern, text, re.IGNORECASE)
                if match:
                    entities['query'] = match.group(1).strip()
                    break
                    
        return entities
        
    def get_confidence_threshold(self) -> float:
        """Get the confidence threshold for reliable classification."""
        return 0.7
        
    def is_confident(self, result: IntentResult) -> bool:
        """Check if classification result is confident."""
        return result.confidence >= self.get_confidence_threshold()