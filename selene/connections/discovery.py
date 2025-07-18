"""
Connection Discovery Engine

Core algorithms for discovering meaningful connections between notes using
various analysis techniques including vector similarity, content analysis,
and temporal patterns.
"""

import re
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Set, Tuple, Any
from pathlib import Path
import asyncio
from collections import defaultdict

from ..vector.chroma_store import ChromaStore
from ..vector.embedding_service import EmbeddingService
from .models import Connection, ConnectionType
from .analyzer import ConnectionAnalyzer
from loguru import logger


class ConnectionDiscovery:
    """Discovers meaningful connections between notes using multiple analysis methods."""
    
    def __init__(self, vector_store: Optional[ChromaStore] = None, 
                 embedding_service: Optional[EmbeddingService] = None):
        """Initialize connection discovery engine.
        
        Args:
            vector_store: ChromaDB vector store for semantic analysis
            embedding_service: Service for generating embeddings
        """
        self.vector_store = vector_store or ChromaStore()
        self.embedding_service = embedding_service or EmbeddingService()
        self.analyzer = ConnectionAnalyzer()
        
        # Configuration
        self.min_confidence_threshold = 0.3
        self.max_connections_per_note = 50
        self.semantic_similarity_threshold = 0.6
        self.temporal_window_days = 30
        
    async def discover_connections(self, note_ids: Optional[List[str]] = None) -> List[Connection]:
        """Discover connections between notes.
        
        Args:
            note_ids: Optional list of specific note IDs to analyze
            
        Returns:
            List of discovered connections
        """
        logger.info(f"Starting connection discovery for {len(note_ids) if note_ids else 'all'} notes")
        
        # Get all notes if no specific IDs provided
        if note_ids is None:
            note_ids = await self._get_all_note_ids()
        
        if len(note_ids) < 2:
            logger.warning("Need at least 2 notes for connection discovery")
            return []
        
        connections = []
        
        # Discover different types of connections
        semantic_connections = await self._discover_semantic_connections(note_ids)
        temporal_connections = await self._discover_temporal_connections(note_ids)
        topical_connections = await self._discover_topical_connections(note_ids)
        reference_connections = await self._discover_reference_connections(note_ids)
        
        connections.extend(semantic_connections)
        connections.extend(temporal_connections)
        connections.extend(topical_connections)
        connections.extend(reference_connections)
        
        # Filter and score connections
        filtered_connections = self._filter_connections(connections)
        
        logger.info(f"Discovered {len(filtered_connections)} connections")
        return filtered_connections
    
    async def _get_all_note_ids(self) -> List[str]:
        """Get all note IDs from the vector store."""
        try:
            # Query vector store for all documents
            results = self.vector_store.collection.get()
            return results.get('ids', [])
        except Exception as e:
            logger.error(f"Failed to get note IDs from vector store: {e}")
            return []
    
    async def _discover_semantic_connections(self, note_ids: List[str]) -> List[Connection]:
        """Discover semantic connections using vector similarity."""
        connections = []
        
        try:
            # Get all documents with their embeddings
            for i, source_id in enumerate(note_ids):
                # Query for similar documents
                results = self.vector_store.search(
                    query=f"id:{source_id}",
                    n_results=min(self.max_connections_per_note, len(note_ids) - 1)
                )
                
                if not results or not results.get('ids'):
                    continue
                
                # Create connections based on similarity
                for j, target_id in enumerate(results['ids'][0]):
                    if target_id == source_id:
                        continue
                    
                    distance = results['distances'][0][j]
                    similarity = 1 - distance  # Convert distance to similarity
                    
                    if similarity >= self.semantic_similarity_threshold:
                        explanation = f"High semantic similarity (score: {similarity:.3f})"
                        
                        # Get document content for better explanation
                        if results.get('documents') and j < len(results['documents'][0]):
                            doc_content = results['documents'][0][j]
                            explanation += f". Shared concepts found in content analysis."
                        
                        connection = Connection(
                            source_id=source_id,
                            target_id=target_id,
                            connection_type=ConnectionType.SEMANTIC,
                            confidence=similarity,
                            explanation=explanation,
                            metadata={
                                'similarity_score': similarity,
                                'discovery_method': 'vector_similarity'
                            }
                        )
                        connections.append(connection)
        
        except Exception as e:
            logger.error(f"Error discovering semantic connections: {e}")
        
        return connections
    
    async def _discover_temporal_connections(self, note_ids: List[str]) -> List[Connection]:
        """Discover temporal connections based on creation/modification times."""
        connections = []
        
        try:
            # Get note metadata including timestamps
            note_metadata = await self._get_note_metadata(note_ids)
            
            # Group notes by time windows
            time_groups = self._group_notes_by_time(note_metadata)
            
            # Create connections within time windows
            for time_window, notes in time_groups.items():
                if len(notes) < 2:
                    continue
                
                for i, source_note in enumerate(notes):
                    for target_note in notes[i+1:]:
                        # Calculate confidence based on temporal proximity
                        time_diff = abs((source_note['timestamp'] - target_note['timestamp']).total_seconds())
                        max_diff = self.temporal_window_days * 24 * 3600
                        confidence = max(0, 1 - (time_diff / max_diff))
                        
                        if confidence >= self.min_confidence_threshold:
                            explanation = f"Created within {time_diff/3600:.1f} hours of each other"
                            
                            connection = Connection(
                                source_id=source_note['id'],
                                target_id=target_note['id'],
                                connection_type=ConnectionType.TEMPORAL,
                                confidence=confidence,
                                explanation=explanation,
                                metadata={
                                    'time_difference_hours': time_diff / 3600,
                                    'discovery_method': 'temporal_proximity'
                                }
                            )
                            connections.append(connection)
        
        except Exception as e:
            logger.error(f"Error discovering temporal connections: {e}")
        
        return connections
    
    async def _discover_topical_connections(self, note_ids: List[str]) -> List[Connection]:
        """Discover topical connections based on shared themes and topics."""
        connections = []
        
        try:
            # Extract topics from notes
            note_topics = await self._extract_note_topics(note_ids)
            
            # Find notes with shared topics
            for source_id, source_topics in note_topics.items():
                for target_id, target_topics in note_topics.items():
                    if source_id >= target_id:  # Avoid duplicates
                        continue
                    
                    # Calculate topic overlap
                    common_topics = source_topics.intersection(target_topics)
                    if not common_topics:
                        continue
                    
                    # Calculate confidence based on topic overlap
                    total_topics = source_topics.union(target_topics)
                    overlap_ratio = len(common_topics) / len(total_topics)
                    confidence = overlap_ratio * 0.8  # Scale to prevent overconfidence
                    
                    if confidence >= self.min_confidence_threshold:
                        topic_list = ", ".join(list(common_topics)[:3])
                        explanation = f"Shared topics: {topic_list}"
                        if len(common_topics) > 3:
                            explanation += f" (+{len(common_topics) - 3} more)"
                        
                        connection = Connection(
                            source_id=source_id,
                            target_id=target_id,
                            connection_type=ConnectionType.TOPICAL,
                            confidence=confidence,
                            explanation=explanation,
                            metadata={
                                'shared_topics': list(common_topics),
                                'overlap_ratio': overlap_ratio,
                                'discovery_method': 'topic_analysis'
                            }
                        )
                        connections.append(connection)
        
        except Exception as e:
            logger.error(f"Error discovering topical connections: {e}")
        
        return connections
    
    async def _discover_reference_connections(self, note_ids: List[str]) -> List[Connection]:
        """Discover explicit reference connections based on links and mentions."""
        connections = []
        
        try:
            # Get note content for all notes
            note_content = await self._get_note_content(note_ids)
            
            # Find explicit references between notes
            for source_id, content in note_content.items():
                if not content:
                    continue
                
                # Look for explicit mentions of other notes
                for target_id in note_ids:
                    if source_id == target_id:
                        continue
                    
                    # Search for various reference patterns
                    references = self._find_references(content, target_id)
                    
                    if references:
                        confidence = min(1.0, len(references) * 0.3)  # Scale by number of references
                        
                        if confidence >= self.min_confidence_threshold:
                            explanation = f"Explicit reference found: {references[0]['context']}"
                            
                            connection = Connection(
                                source_id=source_id,
                                target_id=target_id,
                                connection_type=ConnectionType.REFERENCE,
                                confidence=confidence,
                                explanation=explanation,
                                metadata={
                                    'references': references,
                                    'reference_count': len(references),
                                    'discovery_method': 'explicit_reference'
                                }
                            )
                            connections.append(connection)
        
        except Exception as e:
            logger.error(f"Error discovering reference connections: {e}")
        
        return connections
    
    def _find_references(self, content: str, target_id: str) -> List[Dict[str, Any]]:
        """Find references to a target note in content."""
        references = []
        
        # Common reference patterns
        patterns = [
            rf'\[\[{re.escape(target_id)}\]\]',  # Wiki-style links
            rf'\[.*?\]\({re.escape(target_id)}\)',  # Markdown links
            rf'@{re.escape(target_id)}',  # @ mentions
            rf'#{re.escape(target_id)}',  # # references
        ]
        
        for pattern in patterns:
            matches = re.finditer(pattern, content, re.IGNORECASE)
            for match in matches:
                # Get context around the reference
                start = max(0, match.start() - 50)
                end = min(len(content), match.end() + 50)
                context = content[start:end].strip()
                
                references.append({
                    'pattern': pattern,
                    'match': match.group(),
                    'context': context,
                    'position': match.start()
                })
        
        return references
    
    async def _get_note_metadata(self, note_ids: List[str]) -> Dict[str, Dict[str, Any]]:
        """Get metadata for notes including timestamps."""
        metadata = {}
        
        try:
            # Get metadata from vector store
            results = self.vector_store.collection.get(
                ids=note_ids,
                include=['metadatas']
            )
            
            if results and results.get('metadatas'):
                for i, note_id in enumerate(results['ids']):
                    note_metadata = results['metadatas'][i] if i < len(results['metadatas']) else {}
                    
                    # Extract timestamp (fallback to current time if not found)
                    timestamp = datetime.now()
                    if 'created_at' in note_metadata:
                        try:
                            timestamp = datetime.fromisoformat(note_metadata['created_at'])
                        except:
                            pass
                    
                    metadata[note_id] = {
                        'id': note_id,
                        'timestamp': timestamp,
                        'metadata': note_metadata
                    }
        
        except Exception as e:
            logger.error(f"Error getting note metadata: {e}")
        
        return metadata
    
    def _group_notes_by_time(self, note_metadata: Dict[str, Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
        """Group notes by time windows."""
        time_groups = defaultdict(list)
        
        for note_id, metadata in note_metadata.items():
            timestamp = metadata['timestamp']
            
            # Group by day
            day_key = timestamp.strftime("%Y-%m-%d")
            time_groups[day_key].append(metadata)
        
        return dict(time_groups)
    
    async def _extract_note_topics(self, note_ids: List[str]) -> Dict[str, Set[str]]:
        """Extract topics from notes using simple keyword analysis."""
        note_topics = {}
        
        try:
            # Get note content
            note_content = await self._get_note_content(note_ids)
            
            for note_id, content in note_content.items():
                if not content:
                    note_topics[note_id] = set()
                    continue
                
                # Extract topics using simple keyword analysis
                topics = self._extract_topics_from_content(content)
                note_topics[note_id] = topics
        
        except Exception as e:
            logger.error(f"Error extracting note topics: {e}")
        
        return note_topics
    
    def _extract_topics_from_content(self, content: str) -> Set[str]:
        """Extract topics from content using keyword analysis."""
        topics = set()
        
        # Simple topic extraction based on common patterns
        # This could be enhanced with more sophisticated NLP
        
        # Extract hashtags
        hashtags = re.findall(r'#(\w+)', content)
        topics.update(hashtags)
        
        # Extract common topic keywords
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
    
    async def _get_note_content(self, note_ids: List[str]) -> Dict[str, str]:
        """Get content for notes."""
        note_content = {}
        
        try:
            # Get documents from vector store
            results = self.vector_store.collection.get(
                ids=note_ids,
                include=['documents']
            )
            
            if results and results.get('documents'):
                for i, note_id in enumerate(results['ids']):
                    content = results['documents'][i] if i < len(results['documents']) else ""
                    note_content[note_id] = content
        
        except Exception as e:
            logger.error(f"Error getting note content: {e}")
        
        return note_content
    
    def _filter_connections(self, connections: List[Connection]) -> List[Connection]:
        """Filter connections based on confidence and limits."""
        # Remove duplicates (same source-target pair)
        unique_connections = {}
        for connection in connections:
            key = (connection.source_id, connection.target_id)
            reverse_key = (connection.target_id, connection.source_id)
            
            # Keep the connection with higher confidence
            if key not in unique_connections and reverse_key not in unique_connections:
                unique_connections[key] = connection
            elif key in unique_connections:
                if connection.confidence > unique_connections[key].confidence:
                    unique_connections[key] = connection
            elif reverse_key in unique_connections:
                if connection.confidence > unique_connections[reverse_key].confidence:
                    del unique_connections[reverse_key]
                    unique_connections[key] = connection
        
        # Filter by minimum confidence
        filtered_connections = [
            conn for conn in unique_connections.values()
            if conn.confidence >= self.min_confidence_threshold
        ]
        
        # Limit connections per note
        note_connection_counts = defaultdict(int)
        final_connections = []
        
        # Sort by confidence (highest first)
        filtered_connections.sort(key=lambda x: x.confidence, reverse=True)
        
        for connection in filtered_connections:
            source_count = note_connection_counts[connection.source_id]
            target_count = note_connection_counts[connection.target_id]
            
            if source_count < self.max_connections_per_note and target_count < self.max_connections_per_note:
                final_connections.append(connection)
                note_connection_counts[connection.source_id] += 1
                note_connection_counts[connection.target_id] += 1
        
        return final_connections