"""
Connection Analysis and Scoring

Provides advanced analysis and scoring algorithms for connections between notes.
Implements confidence scoring, connection quality assessment, and explanation generation.
"""

import math
import re
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple, Any, Set
from collections import Counter
import statistics

from .models import Connection, ConnectionType
from loguru import logger


class ConnectionAnalyzer:
    """Analyzes and scores connections between notes."""
    
    def __init__(self):
        """Initialize connection analyzer."""
        self.confidence_weights = {
            ConnectionType.SEMANTIC: 1.0,
            ConnectionType.REFERENCE: 0.95,
            ConnectionType.TOPICAL: 0.85,
            ConnectionType.TEMPORAL: 0.7,
            ConnectionType.CONCEPTUAL: 0.8,
            ConnectionType.CAUSAL: 0.9,
            ConnectionType.HIERARCHICAL: 0.9,
        }
    
    def analyze_connection(self, connection: Connection, 
                          source_content: str = "", 
                          target_content: str = "") -> Connection:
        """Analyze and enhance a connection with better scoring and explanation.
        
        Args:
            connection: Connection to analyze
            source_content: Content of source note
            target_content: Content of target note
            
        Returns:
            Enhanced connection with improved confidence and explanation
        """
        # Calculate enhanced confidence score
        enhanced_confidence = self._calculate_enhanced_confidence(
            connection, source_content, target_content
        )
        
        # Generate detailed explanation
        detailed_explanation = self._generate_detailed_explanation(
            connection, source_content, target_content
        )
        
        # Update connection
        connection.confidence = enhanced_confidence
        connection.explanation = detailed_explanation
        connection.updated_at = datetime.now()
        
        # Add analysis metadata
        connection.metadata.update({
            'analyzed_at': datetime.now().isoformat(),
            'analysis_version': '1.0',
            'original_confidence': connection.metadata.get('original_confidence', connection.confidence)
        })
        
        return connection
    
    def _calculate_enhanced_confidence(self, connection: Connection, 
                                     source_content: str, 
                                     target_content: str) -> float:
        """Calculate enhanced confidence score based on multiple factors."""
        base_confidence = connection.confidence
        
        # Apply connection type weight
        type_weight = self.confidence_weights.get(connection.connection_type, 1.0)
        weighted_confidence = base_confidence * type_weight
        
        # Content-based enhancements
        if source_content and target_content:
            content_boost = self._calculate_content_similarity_boost(
                source_content, target_content, connection.connection_type
            )
            weighted_confidence += content_boost
        
        # Metadata-based adjustments
        metadata_adjustment = self._calculate_metadata_adjustment(connection)
        weighted_confidence += metadata_adjustment
        
        # Ensure confidence stays within bounds
        return max(0.0, min(1.0, weighted_confidence))
    
    def _calculate_content_similarity_boost(self, source_content: str, 
                                          target_content: str, 
                                          connection_type: ConnectionType) -> float:
        """Calculate boost to confidence based on content similarity."""
        if not source_content or not target_content:
            return 0.0
        
        boost = 0.0
        
        # Shared vocabulary boost
        vocab_similarity = self._calculate_vocabulary_similarity(source_content, target_content)
        boost += vocab_similarity * 0.1
        
        # Shared concepts boost
        concept_similarity = self._calculate_concept_similarity(source_content, target_content)
        boost += concept_similarity * 0.15
        
        # Connection type specific boosts
        if connection_type == ConnectionType.SEMANTIC:
            # Extra boost for semantic connections with high content similarity
            boost += vocab_similarity * 0.1
        elif connection_type == ConnectionType.REFERENCE:
            # Extra boost if explicit references are found
            ref_boost = self._calculate_reference_boost(source_content, target_content)
            boost += ref_boost * 0.2
        elif connection_type == ConnectionType.TOPICAL:
            # Extra boost for shared topics
            topic_boost = self._calculate_topic_boost(source_content, target_content)
            boost += topic_boost * 0.15
        
        return min(0.3, boost)  # Cap boost at 0.3
    
    def _calculate_vocabulary_similarity(self, content1: str, content2: str) -> float:
        """Calculate vocabulary similarity between two texts."""
        # Simple word overlap calculation
        words1 = set(re.findall(r'\b\w+\b', content1.lower()))
        words2 = set(re.findall(r'\b\w+\b', content2.lower()))
        
        # Remove common stop words
        stop_words = {'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by', 'is', 'are', 'was', 'were', 'be', 'been', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could', 'should', 'this', 'that', 'these', 'those'}
        words1 = words1 - stop_words
        words2 = words2 - stop_words
        
        if not words1 or not words2:
            return 0.0
        
        # Jaccard similarity
        intersection = len(words1 & words2)
        union = len(words1 | words2)
        
        return intersection / union if union > 0 else 0.0
    
    def _calculate_concept_similarity(self, content1: str, content2: str) -> float:
        """Calculate concept similarity based on key phrases."""
        # Extract potential concepts (2-3 word phrases)
        concepts1 = self._extract_concepts(content1)
        concepts2 = self._extract_concepts(content2)
        
        if not concepts1 or not concepts2:
            return 0.0
        
        # Find shared concepts
        shared_concepts = concepts1 & concepts2
        total_concepts = concepts1 | concepts2
        
        return len(shared_concepts) / len(total_concepts) if total_concepts else 0.0
    
    def _extract_concepts(self, content: str) -> Set[str]:
        """Extract key concepts from content."""
        concepts = set()
        
        # Extract 2-3 word phrases
        words = re.findall(r'\b\w+\b', content.lower())
        
        for i in range(len(words) - 1):
            # 2-word phrases
            phrase = f"{words[i]} {words[i+1]}"
            if len(phrase) > 5:  # Minimum phrase length
                concepts.add(phrase)
            
            # 3-word phrases
            if i < len(words) - 2:
                phrase = f"{words[i]} {words[i+1]} {words[i+2]}"
                if len(phrase) > 8:  # Minimum phrase length
                    concepts.add(phrase)
        
        return concepts
    
    def _calculate_reference_boost(self, source_content: str, target_content: str) -> float:
        """Calculate boost for explicit references."""
        # Look for reference patterns
        ref_patterns = [
            r'\[\[.*?\]\]',  # Wiki-style links
            r'\[.*?\]\(.*?\)',  # Markdown links
            r'@\w+',  # @ mentions
            r'#\w+',  # # references
            r'see also',  # Explicit references
            r'related to',
            r'refers to',
        ]
        
        ref_count = 0
        for pattern in ref_patterns:
            matches1 = len(re.findall(pattern, source_content, re.IGNORECASE))
            matches2 = len(re.findall(pattern, target_content, re.IGNORECASE))
            ref_count += matches1 + matches2
        
        return min(1.0, ref_count / 10.0)  # Normalize to 0-1
    
    def _calculate_topic_boost(self, source_content: str, target_content: str) -> float:
        """Calculate boost for shared topics."""
        # Extract hashtags and topic keywords
        topics1 = self._extract_topics(source_content)
        topics2 = self._extract_topics(target_content)
        
        if not topics1 or not topics2:
            return 0.0
        
        shared_topics = topics1 & topics2
        total_topics = topics1 | topics2
        
        return len(shared_topics) / len(total_topics) if total_topics else 0.0
    
    def _extract_topics(self, content: str) -> Set[str]:
        """Extract topics from content."""
        topics = set()
        
        # Extract hashtags
        hashtags = re.findall(r'#(\w+)', content)
        topics.update(hashtags)
        
        # Extract topic keywords
        topic_keywords = [
            'python', 'javascript', 'programming', 'code', 'software',
            'ai', 'machine learning', 'data science', 'analytics',
            'web development', 'frontend', 'backend', 'database',
            'project', 'meeting', 'research', 'idea', 'todo',
            'book', 'article', 'paper', 'study', 'learning'
        ]
        
        content_lower = content.lower()
        for keyword in topic_keywords:
            if keyword in content_lower:
                topics.add(keyword)
        
        return topics
    
    def _calculate_metadata_adjustment(self, connection: Connection) -> float:
        """Calculate confidence adjustment based on metadata."""
        adjustment = 0.0
        metadata = connection.metadata
        
        # Boost for high-quality discovery methods
        discovery_method = metadata.get('discovery_method', '')
        if discovery_method == 'vector_similarity':
            similarity_score = metadata.get('similarity_score', 0.0)
            if similarity_score > 0.8:
                adjustment += 0.05
        elif discovery_method == 'explicit_reference':
            ref_count = metadata.get('reference_count', 0)
            adjustment += min(0.1, ref_count * 0.02)
        
        # Adjustment for time-based connections
        if connection.connection_type == ConnectionType.TEMPORAL:
            time_diff_hours = metadata.get('time_difference_hours', 0)
            if time_diff_hours < 1:  # Very close in time
                adjustment += 0.05
        
        return adjustment
    
    def _generate_detailed_explanation(self, connection: Connection, 
                                     source_content: str, 
                                     target_content: str) -> str:
        """Generate a detailed explanation for the connection."""
        base_explanation = connection.explanation
        
        # Enhance explanation based on connection type
        if connection.connection_type == ConnectionType.SEMANTIC:
            explanation = self._explain_semantic_connection(
                connection, source_content, target_content
            )
        elif connection.connection_type == ConnectionType.REFERENCE:
            explanation = self._explain_reference_connection(
                connection, source_content, target_content
            )
        elif connection.connection_type == ConnectionType.TOPICAL:
            explanation = self._explain_topical_connection(
                connection, source_content, target_content
            )
        elif connection.connection_type == ConnectionType.TEMPORAL:
            explanation = self._explain_temporal_connection(connection)
        else:
            explanation = base_explanation
        
        # Add confidence qualifier
        confidence_qualifier = self._get_confidence_qualifier(connection.confidence)
        explanation = f"{confidence_qualifier} {explanation}"
        
        return explanation
    
    def _explain_semantic_connection(self, connection: Connection, 
                                   source_content: str, 
                                   target_content: str) -> str:
        """Generate explanation for semantic connections."""
        if not source_content or not target_content:
            return connection.explanation
        
        # Find shared concepts
        concepts1 = self._extract_concepts(source_content)
        concepts2 = self._extract_concepts(target_content)
        shared_concepts = concepts1 & concepts2
        
        if shared_concepts:
            concept_list = ", ".join(list(shared_concepts)[:3])
            explanation = f"Semantic similarity through shared concepts: {concept_list}"
            if len(shared_concepts) > 3:
                explanation += f" (+{len(shared_concepts) - 3} more)"
        else:
            vocab_similarity = self._calculate_vocabulary_similarity(source_content, target_content)
            explanation = f"Semantic similarity through vocabulary overlap ({vocab_similarity:.2f})"
        
        return explanation
    
    def _explain_reference_connection(self, connection: Connection, 
                                    source_content: str, 
                                    target_content: str) -> str:
        """Generate explanation for reference connections."""
        metadata = connection.metadata
        references = metadata.get('references', [])
        
        if references:
            ref_types = [ref.get('pattern', 'unknown') for ref in references]
            ref_type_counts = Counter(ref_types)
            
            explanation = "Explicit references found: "
            explanations = []
            
            for ref_type, count in ref_type_counts.items():
                if 'wiki' in ref_type.lower():
                    explanations.append(f"{count} wiki-style link(s)")
                elif 'markdown' in ref_type.lower():
                    explanations.append(f"{count} markdown link(s)")
                elif '@' in ref_type:
                    explanations.append(f"{count} @ mention(s)")
                elif '#' in ref_type:
                    explanations.append(f"{count} # reference(s)")
                else:
                    explanations.append(f"{count} reference(s)")
            
            explanation += ", ".join(explanations)
        else:
            explanation = connection.explanation
        
        return explanation
    
    def _explain_topical_connection(self, connection: Connection, 
                                  source_content: str, 
                                  target_content: str) -> str:
        """Generate explanation for topical connections."""
        metadata = connection.metadata
        shared_topics = metadata.get('shared_topics', [])
        
        if shared_topics:
            topic_list = ", ".join(shared_topics[:3])
            explanation = f"Shared topics: {topic_list}"
            if len(shared_topics) > 3:
                explanation += f" (+{len(shared_topics) - 3} more)"
        else:
            explanation = connection.explanation
        
        return explanation
    
    def _explain_temporal_connection(self, connection: Connection) -> str:
        """Generate explanation for temporal connections."""
        metadata = connection.metadata
        time_diff_hours = metadata.get('time_difference_hours', 0)
        
        if time_diff_hours < 1:
            explanation = f"Created within {time_diff_hours*60:.0f} minutes"
        elif time_diff_hours < 24:
            explanation = f"Created within {time_diff_hours:.1f} hours"
        else:
            explanation = f"Created within {time_diff_hours/24:.1f} days"
        
        return explanation
    
    def _get_confidence_qualifier(self, confidence: float) -> str:
        """Get a qualifier describing the confidence level."""
        if confidence >= 0.9:
            return "Very strong connection:"
        elif confidence >= 0.8:
            return "Strong connection:"
        elif confidence >= 0.7:
            return "Good connection:"
        elif confidence >= 0.6:
            return "Moderate connection:"
        elif confidence >= 0.5:
            return "Weak connection:"
        else:
            return "Tentative connection:"
    
    def analyze_connection_quality(self, connections: List[Connection]) -> Dict[str, Any]:
        """Analyze the overall quality of a set of connections.
        
        Args:
            connections: List of connections to analyze
            
        Returns:
            Dictionary with quality metrics
        """
        if not connections:
            return {
                'total_connections': 0,
                'quality_score': 0.0,
                'confidence_distribution': {},
                'type_distribution': {},
                'recommendations': []
            }
        
        # Calculate quality metrics
        confidences = [c.confidence for c in connections]
        types = [c.connection_type.value for c in connections]
        
        quality_metrics = {
            'total_connections': len(connections),
            'average_confidence': statistics.mean(confidences),
            'median_confidence': statistics.median(confidences),
            'confidence_std': statistics.stdev(confidences) if len(confidences) > 1 else 0.0,
            'min_confidence': min(confidences),
            'max_confidence': max(confidences),
            'confidence_distribution': self._calculate_confidence_distribution(confidences),
            'type_distribution': dict(Counter(types)),
            'quality_score': self._calculate_overall_quality_score(connections),
            'recommendations': self._generate_quality_recommendations(connections)
        }
        
        return quality_metrics
    
    def _calculate_confidence_distribution(self, confidences: List[float]) -> Dict[str, int]:
        """Calculate distribution of confidence scores."""
        ranges = {
            '0.0-0.2': 0,
            '0.2-0.4': 0,
            '0.4-0.6': 0,
            '0.6-0.8': 0,
            '0.8-1.0': 0
        }
        
        for confidence in confidences:
            if confidence < 0.2:
                ranges['0.0-0.2'] += 1
            elif confidence < 0.4:
                ranges['0.2-0.4'] += 1
            elif confidence < 0.6:
                ranges['0.4-0.6'] += 1
            elif confidence < 0.8:
                ranges['0.6-0.8'] += 1
            else:
                ranges['0.8-1.0'] += 1
        
        return ranges
    
    def _calculate_overall_quality_score(self, connections: List[Connection]) -> float:
        """Calculate overall quality score for connections."""
        if not connections:
            return 0.0
        
        # Factors: average confidence, connection diversity, explanation quality
        confidences = [c.confidence for c in connections]
        avg_confidence = statistics.mean(confidences)
        
        # Diversity score (higher is better)
        types = [c.connection_type for c in connections]
        type_diversity = len(set(types)) / len(ConnectionType)
        
        # Explanation quality (based on length and content)
        explanation_scores = []
        for c in connections:
            score = min(1.0, len(c.explanation) / 50.0)  # Normalize by length
            if 'strong' in c.explanation.lower() or 'high' in c.explanation.lower():
                score += 0.1
            explanation_scores.append(score)
        
        avg_explanation_score = statistics.mean(explanation_scores)
        
        # Weighted combination
        quality_score = (
            avg_confidence * 0.5 +
            type_diversity * 0.3 +
            avg_explanation_score * 0.2
        )
        
        return quality_score
    
    def _generate_quality_recommendations(self, connections: List[Connection]) -> List[str]:
        """Generate recommendations for improving connection quality."""
        recommendations = []
        
        if not connections:
            return ["No connections found. Consider running connection discovery."]
        
        confidences = [c.confidence for c in connections]
        avg_confidence = statistics.mean(confidences)
        
        # Confidence-based recommendations
        if avg_confidence < 0.5:
            recommendations.append("Average confidence is low. Consider adjusting discovery thresholds.")
        
        if len([c for c in confidences if c < 0.3]) > len(confidences) * 0.3:
            recommendations.append("Many low-confidence connections. Consider raising minimum confidence threshold.")
        
        # Type diversity recommendations
        types = [c.connection_type for c in connections]
        type_counts = Counter(types)
        
        if len(type_counts) < 3:
            recommendations.append("Limited connection types. Consider enabling more discovery methods.")
        
        # Explanation quality recommendations
        short_explanations = [c for c in connections if len(c.explanation) < 20]
        if len(short_explanations) > len(connections) * 0.2:
            recommendations.append("Many connections have brief explanations. Consider enhancing explanation generation.")
        
        return recommendations