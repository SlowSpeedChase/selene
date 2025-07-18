"""
Tests for the connection analysis system.
"""

import pytest
import asyncio
import tempfile
import os
from datetime import datetime, timedelta
from pathlib import Path

from selene.connections import (
    Connection,
    ConnectionType,
    ConnectionStorage,
    ConnectionDiscovery,
    ConnectionAnalyzer,
    ConnectionStatisticsCollector,
    ConnectionFilter,
)
from selene.vector.chroma_store import ChromaStore
from selene.vector.embedding_service import EmbeddingService


class TestConnectionModels:
    """Test connection data models."""
    
    def test_connection_creation(self):
        """Test creating a connection."""
        connection = Connection(
            source_id="note1",
            target_id="note2",
            connection_type=ConnectionType.SEMANTIC,
            confidence=0.8,
            explanation="High semantic similarity"
        )
        
        assert connection.source_id == "note1"
        assert connection.target_id == "note2"
        assert connection.connection_type == ConnectionType.SEMANTIC
        assert connection.confidence == 0.8
        assert connection.explanation == "High semantic similarity"
        assert connection.id is not None
        assert isinstance(connection.created_at, datetime)
    
    def test_connection_validation(self):
        """Test connection validation."""
        # Test confidence range validation
        with pytest.raises(ValueError, match="Confidence must be between 0.0 and 1.0"):
            Connection(
                source_id="note1",
                target_id="note2",
                confidence=1.5
            )
        
        # Test same source and target
        with pytest.raises(ValueError, match="Source and target cannot be the same"):
            Connection(
                source_id="note1",
                target_id="note1",
                confidence=0.8
            )
        
        # Test empty IDs
        with pytest.raises(ValueError, match="Source and target IDs are required"):
            Connection(
                source_id="",
                target_id="note2",
                confidence=0.8
            )
    
    def test_connection_serialization(self):
        """Test connection to/from dict conversion."""
        connection = Connection(
            source_id="note1",
            target_id="note2",
            connection_type=ConnectionType.REFERENCE,
            confidence=0.9,
            explanation="Explicit reference found",
            metadata={"ref_count": 2}
        )
        
        # Test to_dict
        data = connection.to_dict()
        assert data["source_id"] == "note1"
        assert data["target_id"] == "note2"
        assert data["connection_type"] == "reference"
        assert data["confidence"] == 0.9
        assert data["explanation"] == "Explicit reference found"
        assert data["metadata"] == {"ref_count": 2}
        
        # Test from_dict
        restored = Connection.from_dict(data)
        assert restored.source_id == connection.source_id
        assert restored.target_id == connection.target_id
        assert restored.connection_type == connection.connection_type
        assert restored.confidence == connection.confidence
        assert restored.explanation == connection.explanation
        assert restored.metadata == connection.metadata


class TestConnectionStorage:
    """Test connection storage functionality."""
    
    @pytest.fixture
    def temp_db(self):
        """Create temporary database for testing."""
        with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
            db_path = f.name
        
        yield db_path
        
        # Cleanup
        if os.path.exists(db_path):
            os.unlink(db_path)
    
    def test_storage_initialization(self, temp_db):
        """Test storage initialization."""
        storage = ConnectionStorage(temp_db)
        assert storage.db_path.exists()
    
    def test_store_and_retrieve_connection(self, temp_db):
        """Test storing and retrieving connections."""
        storage = ConnectionStorage(temp_db)
        
        connection = Connection(
            source_id="note1",
            target_id="note2",
            connection_type=ConnectionType.SEMANTIC,
            confidence=0.8,
            explanation="Test connection"
        )
        
        # Store connection
        assert storage.store_connection(connection)
        
        # Retrieve connection
        retrieved = storage.get_connection(connection.id)
        assert retrieved is not None
        assert retrieved.source_id == connection.source_id
        assert retrieved.target_id == connection.target_id
        assert retrieved.connection_type == connection.connection_type
        assert retrieved.confidence == connection.confidence
    
    def test_store_multiple_connections(self, temp_db):
        """Test storing multiple connections."""
        storage = ConnectionStorage(temp_db)
        
        connections = [
            Connection(
                source_id="note1",
                target_id="note2",
                connection_type=ConnectionType.SEMANTIC,
                confidence=0.8,
                explanation="Connection 1"
            ),
            Connection(
                source_id="note2",
                target_id="note3",
                connection_type=ConnectionType.TEMPORAL,
                confidence=0.6,
                explanation="Connection 2"
            ),
            Connection(
                source_id="note1",
                target_id="note3",
                connection_type=ConnectionType.REFERENCE,
                confidence=0.9,
                explanation="Connection 3"
            )
        ]
        
        # Store connections
        stored_count = storage.store_connections(connections)
        assert stored_count == 3
        
        # Retrieve all connections
        all_connections = storage.get_connections()
        assert len(all_connections) == 3
    
    def test_get_connections_for_note(self, temp_db):
        """Test getting connections for a specific note."""
        storage = ConnectionStorage(temp_db)
        
        connections = [
            Connection(
                source_id="note1",
                target_id="note2",
                connection_type=ConnectionType.SEMANTIC,
                confidence=0.8,
                explanation="Connection 1"
            ),
            Connection(
                source_id="note2",
                target_id="note3",
                connection_type=ConnectionType.TEMPORAL,
                confidence=0.6,
                explanation="Connection 2"
            ),
            Connection(
                source_id="note1",
                target_id="note3",
                connection_type=ConnectionType.REFERENCE,
                confidence=0.9,
                explanation="Connection 3"
            )
        ]
        
        storage.store_connections(connections)
        
        # Get connections for note1
        note1_connections = storage.get_connections_for_note("note1")
        assert len(note1_connections) == 2  # note1 appears in 2 connections
        
        # Get connections for note2
        note2_connections = storage.get_connections_for_note("note2")
        assert len(note2_connections) == 2  # note2 appears in 2 connections
    
    def test_connection_filtering(self, temp_db):
        """Test filtering connections."""
        storage = ConnectionStorage(temp_db)
        
        connections = [
            Connection(
                source_id="note1",
                target_id="note2",
                connection_type=ConnectionType.SEMANTIC,
                confidence=0.8,
                explanation="High confidence"
            ),
            Connection(
                source_id="note2",
                target_id="note3",
                connection_type=ConnectionType.TEMPORAL,
                confidence=0.4,
                explanation="Low confidence"
            ),
            Connection(
                source_id="note1",
                target_id="note3",
                connection_type=ConnectionType.SEMANTIC,
                confidence=0.9,
                explanation="Very high confidence"
            )
        ]
        
        storage.store_connections(connections)
        
        # Filter by connection type
        filter_semantic = ConnectionFilter(connection_types=[ConnectionType.SEMANTIC])
        semantic_connections = storage.get_connections(filter_semantic)
        assert len(semantic_connections) == 2
        
        # Filter by confidence
        filter_high_conf = ConnectionFilter(min_confidence=0.7)
        high_conf_connections = storage.get_connections(filter_high_conf)
        assert len(high_conf_connections) == 2
        
        # Filter by source ID
        filter_source = ConnectionFilter(source_ids=["note1"])
        source_connections = storage.get_connections(filter_source)
        assert len(source_connections) == 2
    
    def test_connection_statistics(self, temp_db):
        """Test connection statistics."""
        storage = ConnectionStorage(temp_db)
        
        connections = [
            Connection(
                source_id="note1",
                target_id="note2",
                connection_type=ConnectionType.SEMANTIC,
                confidence=0.8,
                explanation="Connection 1"
            ),
            Connection(
                source_id="note2",
                target_id="note3",
                connection_type=ConnectionType.TEMPORAL,
                confidence=0.6,
                explanation="Connection 2"
            ),
            Connection(
                source_id="note1",
                target_id="note3",
                connection_type=ConnectionType.SEMANTIC,
                confidence=0.9,
                explanation="Connection 3"
            )
        ]
        
        storage.store_connections(connections)
        
        stats = storage.get_connection_statistics()
        assert stats["total_connections"] == 3
        assert stats["connections_by_type"]["semantic"] == 2
        assert stats["connections_by_type"]["temporal"] == 1
        assert stats["average_confidence"] == pytest.approx(0.767, rel=1e-2)
    
    def test_delete_connection(self, temp_db):
        """Test deleting connections."""
        storage = ConnectionStorage(temp_db)
        
        connection = Connection(
            source_id="note1",
            target_id="note2",
            connection_type=ConnectionType.SEMANTIC,
            confidence=0.8,
            explanation="Test connection"
        )
        
        storage.store_connection(connection)
        
        # Delete connection
        assert storage.delete_connection(connection.id)
        
        # Verify deletion
        retrieved = storage.get_connection(connection.id)
        assert retrieved is None


class TestConnectionAnalyzer:
    """Test connection analyzer functionality."""
    
    def test_analyzer_initialization(self):
        """Test analyzer initialization."""
        analyzer = ConnectionAnalyzer()
        assert analyzer.confidence_weights is not None
        assert len(analyzer.confidence_weights) == len(ConnectionType)
    
    def test_analyze_connection(self):
        """Test connection analysis."""
        analyzer = ConnectionAnalyzer()
        
        connection = Connection(
            source_id="note1",
            target_id="note2",
            connection_type=ConnectionType.SEMANTIC,
            confidence=0.6,
            explanation="Basic connection"
        )
        
        source_content = "This is about machine learning and AI concepts"
        target_content = "Machine learning algorithms and artificial intelligence"
        
        # Analyze connection
        analyzed = analyzer.analyze_connection(connection, source_content, target_content)
        
        # Check that analysis was performed
        assert analyzed.confidence >= connection.confidence  # Should be enhanced
        assert len(analyzed.explanation) > len(connection.explanation)  # Should be more detailed
        assert "analyzed_at" in analyzed.metadata
    
    def test_confidence_scoring(self):
        """Test confidence scoring enhancement."""
        analyzer = ConnectionAnalyzer()
        
        # Test semantic connection with high content similarity
        connection = Connection(
            source_id="note1",
            target_id="note2",
            connection_type=ConnectionType.SEMANTIC,
            confidence=0.5,
            explanation="Basic semantic connection"
        )
        
        # High similarity content
        source_content = "Python programming language syntax and features"
        target_content = "Python language programming syntax and methods"
        
        enhanced_confidence = analyzer._calculate_enhanced_confidence(
            connection, source_content, target_content
        )
        
        # Should be higher than original
        assert enhanced_confidence > 0.5
        assert enhanced_confidence <= 1.0
    
    def test_explanation_generation(self):
        """Test explanation generation."""
        analyzer = ConnectionAnalyzer()
        
        # Test reference connection
        connection = Connection(
            source_id="note1",
            target_id="note2",
            connection_type=ConnectionType.REFERENCE,
            confidence=0.8,
            explanation="Reference found",
            metadata={"references": [{"pattern": "wiki", "context": "See [[note2]]"}]}
        )
        
        explanation = analyzer._generate_detailed_explanation(connection, "", "")
        
        # Should include confidence qualifier and enhanced explanation
        assert "connection:" in explanation.lower()
        assert len(explanation) > len(connection.explanation)
    
    def test_quality_analysis(self):
        """Test connection quality analysis."""
        analyzer = ConnectionAnalyzer()
        
        connections = [
            Connection(
                source_id="note1",
                target_id="note2",
                connection_type=ConnectionType.SEMANTIC,
                confidence=0.8,
                explanation="High quality connection with detailed explanation"
            ),
            Connection(
                source_id="note2",
                target_id="note3",
                connection_type=ConnectionType.TEMPORAL,
                confidence=0.6,
                explanation="Medium quality connection"
            ),
            Connection(
                source_id="note1",
                target_id="note3",
                connection_type=ConnectionType.REFERENCE,
                confidence=0.9,
                explanation="Very high quality connection with comprehensive details"
            )
        ]
        
        quality_metrics = analyzer.analyze_connection_quality(connections)
        
        assert quality_metrics["total_connections"] == 3
        assert quality_metrics["average_confidence"] == pytest.approx(0.767, rel=1e-2)
        assert "quality_score" in quality_metrics
        assert "recommendations" in quality_metrics
        assert quality_metrics["quality_score"] > 0


class TestConnectionDiscovery:
    """Test connection discovery functionality."""
    
    @pytest.fixture
    def mock_vector_store(self):
        """Create a mock vector store for testing."""
        class MockVectorStore:
            def __init__(self):
                self.collection = MockCollection()
            
            def search(self, query, n_results=10):
                # Return mock similarity results
                return {
                    'ids': [['note2', 'note3']],
                    'distances': [[0.2, 0.4]],  # High similarity
                    'documents': [['Content about AI', 'Content about ML']]
                }
        
        class MockCollection:
            def get(self, ids=None, include=None):
                if ids:
                    return {
                        'ids': ids,
                        'documents': ['Content ' + id for id in ids],
                        'metadatas': [{'created_at': datetime.now().isoformat()} for _ in ids]
                    }
                else:
                    return {
                        'ids': ['note1', 'note2', 'note3'],
                        'documents': ['Content 1', 'Content 2', 'Content 3'],
                        'metadatas': [{'created_at': datetime.now().isoformat()} for _ in range(3)]
                    }
        
        return MockVectorStore()
    
    @pytest.mark.asyncio
    async def test_discovery_initialization(self, mock_vector_store):
        """Test discovery initialization."""
        discovery = ConnectionDiscovery(vector_store=mock_vector_store)
        assert discovery.vector_store is not None
        assert discovery.analyzer is not None
        assert discovery.min_confidence_threshold > 0
    
    @pytest.mark.asyncio
    async def test_semantic_connection_discovery(self, mock_vector_store):
        """Test semantic connection discovery."""
        discovery = ConnectionDiscovery(vector_store=mock_vector_store)
        
        # Test with specific note IDs
        note_ids = ['note1', 'note2', 'note3']
        connections = await discovery._discover_semantic_connections(note_ids)
        
        # Should find some connections based on mock data
        assert len(connections) > 0
        
        # Check connection properties
        for conn in connections:
            assert conn.connection_type == ConnectionType.SEMANTIC
            assert 0 <= conn.confidence <= 1
            assert conn.explanation is not None
    
    @pytest.mark.asyncio
    async def test_temporal_connection_discovery(self, mock_vector_store):
        """Test temporal connection discovery."""
        discovery = ConnectionDiscovery(vector_store=mock_vector_store)
        
        note_ids = ['note1', 'note2', 'note3']
        connections = await discovery._discover_temporal_connections(note_ids)
        
        # May find connections based on mock timestamps
        for conn in connections:
            assert conn.connection_type == ConnectionType.TEMPORAL
            assert 0 <= conn.confidence <= 1
            assert 'time_difference_hours' in conn.metadata
    
    @pytest.mark.asyncio
    async def test_reference_connection_discovery(self, mock_vector_store):
        """Test reference connection discovery."""
        discovery = ConnectionDiscovery(vector_store=mock_vector_store)
        
        # Mock note content with references
        original_method = discovery._get_note_content
        
        async def mock_get_note_content(note_ids):
            return {
                'note1': 'This refers to [[note2]] and mentions @note3',
                'note2': 'Content with #note1 reference',
                'note3': 'No references here'
            }
        
        discovery._get_note_content = mock_get_note_content
        
        note_ids = ['note1', 'note2', 'note3']
        connections = await discovery._discover_reference_connections(note_ids)
        
        # Should find reference connections
        assert len(connections) > 0
        
        for conn in connections:
            assert conn.connection_type == ConnectionType.REFERENCE
            assert conn.confidence > 0
            assert 'references' in conn.metadata
    
    @pytest.mark.asyncio
    async def test_full_discovery_process(self, mock_vector_store):
        """Test full connection discovery process."""
        discovery = ConnectionDiscovery(vector_store=mock_vector_store)
        
        # Set lower thresholds for testing
        discovery.min_confidence_threshold = 0.1
        discovery.semantic_similarity_threshold = 0.1
        
        note_ids = ['note1', 'note2', 'note3']
        connections = await discovery.discover_connections(note_ids)
        
        # Should find various types of connections
        assert len(connections) > 0
        
        # Check connection diversity
        connection_types = set(conn.connection_type for conn in connections)
        assert len(connection_types) >= 1  # At least semantic connections
        
        # Check bidirectional filtering
        for conn in connections:
            assert conn.source_id != conn.target_id
            assert conn.confidence >= discovery.min_confidence_threshold


class TestConnectionStatistics:
    """Test connection statistics functionality."""
    
    @pytest.fixture
    def temp_db(self):
        """Create temporary database for testing."""
        with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
            db_path = f.name
        
        yield db_path
        
        # Cleanup
        if os.path.exists(db_path):
            os.unlink(db_path)
    
    def test_statistics_collection(self, temp_db):
        """Test statistics collection."""
        storage = ConnectionStorage(temp_db)
        collector = ConnectionStatisticsCollector(storage)
        
        # Add test connections
        connections = [
            Connection(
                source_id="note1",
                target_id="note2",
                connection_type=ConnectionType.SEMANTIC,
                confidence=0.8,
                explanation="Connection 1"
            ),
            Connection(
                source_id="note2",
                target_id="note3",
                connection_type=ConnectionType.TEMPORAL,
                confidence=0.6,
                explanation="Connection 2"
            ),
            Connection(
                source_id="note1",
                target_id="note3",
                connection_type=ConnectionType.SEMANTIC,
                confidence=0.9,
                explanation="Connection 3"
            )
        ]
        
        storage.store_connections(connections)
        
        # Collect statistics
        stats = collector.collect_statistics()
        
        assert stats.total_connections == 3
        assert stats.connections_by_type["semantic"] == 2
        assert stats.connections_by_type["temporal"] == 1
        assert stats.average_confidence == pytest.approx(0.767, rel=1e-2)
        assert len(stats.most_connected_notes) > 0
    
    def test_connection_report_generation(self, temp_db):
        """Test connection report generation."""
        storage = ConnectionStorage(temp_db)
        collector = ConnectionStatisticsCollector(storage)
        
        # Add test connections
        connections = [
            Connection(
                source_id="note1",
                target_id="note2",
                connection_type=ConnectionType.SEMANTIC,
                confidence=0.8,
                explanation="Connection 1"
            ),
            Connection(
                source_id="note2",
                target_id="note3",
                connection_type=ConnectionType.TEMPORAL,
                confidence=0.6,
                explanation="Connection 2"
            )
        ]
        
        storage.store_connections(connections)
        
        # Generate global report
        global_report = collector.generate_connection_report()
        
        assert "overview" in global_report
        assert "statistics" in global_report
        assert "network_health" in global_report
        assert "recommendations" in global_report
        
        # Generate note-specific report
        note_report = collector.generate_connection_report("note1")
        
        assert note_report["note_id"] == "note1"
        assert "summary" in note_report
        assert "connection_details" in note_report
        assert "recommendations" in note_report
    
    def test_network_health_calculation(self, temp_db):
        """Test network health calculation."""
        storage = ConnectionStorage(temp_db)
        collector = ConnectionStatisticsCollector(storage)
        
        # Add high-quality connections
        connections = [
            Connection(
                source_id="note1",
                target_id="note2",
                connection_type=ConnectionType.SEMANTIC,
                confidence=0.9,
                explanation="High quality connection"
            ),
            Connection(
                source_id="note2",
                target_id="note3",
                connection_type=ConnectionType.REFERENCE,
                confidence=0.95,
                explanation="Very high quality connection"
            ),
            Connection(
                source_id="note1",
                target_id="note3",
                connection_type=ConnectionType.TOPICAL,
                confidence=0.85,
                explanation="Good quality connection"
            )
        ]
        
        storage.store_connections(connections)
        
        # Calculate network health
        health = collector._calculate_network_health(connections)
        
        assert "health_score" in health
        assert "status" in health
        assert "metrics" in health
        assert health["health_score"] > 0
        assert health["status"] in ["excellent", "good", "fair", "poor"]


@pytest.mark.asyncio
async def test_integration_workflow():
    """Test full integration workflow."""
    # Create temporary database
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    
    try:
        # Initialize components
        storage = ConnectionStorage(db_path)
        
        # Create mock vector store
        class MockVectorStore:
            def __init__(self):
                self.collection = MockCollection()
            
            def search(self, query, n_results=10):
                return {
                    'ids': [['note2', 'note3']],
                    'distances': [[0.3, 0.5]],
                    'documents': [['AI content', 'ML content']]
                }
        
        class MockCollection:
            def get(self, ids=None, include=None):
                if ids:
                    return {
                        'ids': ids,
                        'documents': ['Content ' + id for id in ids],
                        'metadatas': [{'created_at': datetime.now().isoformat()} for _ in ids]
                    }
                else:
                    return {
                        'ids': ['note1', 'note2', 'note3'],
                        'documents': ['Content 1', 'Content 2', 'Content 3'],
                        'metadatas': [{'created_at': datetime.now().isoformat()} for _ in range(3)]
                    }
        
        discovery = ConnectionDiscovery(vector_store=MockVectorStore())
        discovery.min_confidence_threshold = 0.1
        discovery.semantic_similarity_threshold = 0.1
        
        analyzer = ConnectionAnalyzer()
        collector = ConnectionStatisticsCollector(storage)
        
        # Full workflow
        # 1. Discover connections
        connections = await discovery.discover_connections(['note1', 'note2', 'note3'])
        assert len(connections) > 0
        
        # 2. Analyze connections
        for connection in connections:
            analyzed = analyzer.analyze_connection(connection, "test content", "test content")
            assert analyzed.confidence >= connection.confidence
        
        # 3. Store connections
        stored_count = storage.store_connections(connections)
        assert stored_count > 0
        
        # 4. Generate statistics
        stats = collector.collect_statistics()
        assert stats.total_connections > 0
        
        # 5. Generate report
        report = collector.generate_connection_report()
        assert "overview" in report
        assert "network_health" in report
        
    finally:
        # Cleanup
        if os.path.exists(db_path):
            os.unlink(db_path)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])