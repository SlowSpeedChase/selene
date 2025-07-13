"""
Tests for vector database functionality.
"""

import pytest
import asyncio
import tempfile
import shutil
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

from selene.vector.embedding_service import EmbeddingService, EmbeddingResult
from selene.vector.chroma_store import ChromaStore, VectorStoreResult, Document
from selene.processors.vector_processor import VectorProcessor


class TestEmbeddingService:
    """Test embedding service functionality."""
    
    @pytest.fixture
    def embedding_service(self):
        """Create embedding service for testing."""
        return EmbeddingService(
            prefer_local=True,
            local_model="test-model",
            openai_model="text-embedding-3-small"
        )
    
    @pytest.mark.asyncio
    async def test_embedding_info(self, embedding_service):
        """Test embedding service info."""
        info = embedding_service.get_embedding_info()
        
        assert "prefer_local" in info
        assert "local_model" in info
        assert "openai_model" in info
        assert info["prefer_local"] is True
        assert info["local_model"] == "test-model"
    
    @pytest.mark.asyncio
    async def test_generate_embeddings_no_texts(self, embedding_service):
        """Test embedding generation with no texts."""
        result = await embedding_service.generate_embeddings([])
        
        assert not result.success
        assert "No texts provided" in result.error
        assert result.embeddings == []
    
    @pytest.mark.asyncio
    async def test_generate_single_embedding(self, embedding_service):
        """Test single embedding generation."""
        with patch.object(embedding_service, 'generate_embeddings') as mock_gen:
            mock_result = EmbeddingResult(
                success=True,
                embeddings=[[0.1, 0.2, 0.3]],
                model_used="test-model",
                processing_time=1.0
            )
            mock_gen.return_value = mock_result
            
            result = await embedding_service.generate_single_embedding("test text")
            
            assert result.success
            assert len(result.embeddings) == 1
            assert result.model_used == "test-model"
            mock_gen.assert_called_once_with(["test text"])


class TestChromaStore:
    """Test ChromaDB vector store functionality."""
    
    @pytest.fixture
    def temp_db_path(self):
        """Create temporary database path."""
        temp_dir = tempfile.mkdtemp()
        yield temp_dir
        shutil.rmtree(temp_dir)
    
    @pytest.fixture
    def mock_embedding_service(self):
        """Create mock embedding service."""
        service = MagicMock(spec=EmbeddingService)
        service.generate_single_embedding = AsyncMock()
        service.get_embedding_info.return_value = {"test": "info"}
        return service
    
    @pytest.fixture
    def chroma_store(self, temp_db_path, mock_embedding_service):
        """Create ChromaDB store for testing."""
        return ChromaStore(
            db_path=temp_db_path,
            collection_name="test_collection",
            embedding_service=mock_embedding_service
        )
    
    @pytest.mark.asyncio
    async def test_initialization(self, chroma_store):
        """Test ChromaDB store initialization."""
        result = await chroma_store.initialize()
        
        assert result.success
        assert "initialized successfully" in result.message
        assert chroma_store.client is not None
        assert chroma_store.collection is not None
    
    @pytest.mark.asyncio
    async def test_add_document_success(self, chroma_store, mock_embedding_service):
        """Test successful document addition."""
        # Setup mock embedding
        mock_embedding_service.generate_single_embedding.return_value = EmbeddingResult(
            success=True,
            embeddings=[[0.1, 0.2, 0.3]],
            model_used="test-model",
            processing_time=1.0
        )
        
        await chroma_store.initialize()
        
        result = await chroma_store.add_document(
            content="Test document content",
            metadata={"source": "test"},
            doc_id="test-doc-1"
        )
        
        assert result.success
        assert "Document added successfully" in result.message
        assert result.data["document_id"] == "test-doc-1"
        assert result.data["embedding_model"] == "test-model"
    
    @pytest.mark.asyncio
    async def test_add_document_embedding_failure(self, chroma_store, mock_embedding_service):
        """Test document addition with embedding failure."""
        # Setup mock embedding failure
        mock_embedding_service.generate_single_embedding.return_value = EmbeddingResult(
            success=False,
            embeddings=[],
            model_used="",
            processing_time=0.0,
            error="Embedding failed"
        )
        
        await chroma_store.initialize()
        
        result = await chroma_store.add_document(
            content="Test document content",
            doc_id="test-doc-1"
        )
        
        assert not result.success
        assert "Failed to generate embedding" in result.message
        assert result.error == "Embedding failed"
    
    @pytest.mark.asyncio
    async def test_search_documents(self, chroma_store, mock_embedding_service):
        """Test document search functionality."""
        # Setup mock embedding
        mock_embedding_service.generate_single_embedding.return_value = EmbeddingResult(
            success=True,
            embeddings=[[0.1, 0.2, 0.3]],
            model_used="test-model",
            processing_time=1.0
        )
        
        await chroma_store.initialize()
        
        # Add a document first
        await chroma_store.add_document(
            content="This is a test document about machine learning",
            doc_id="test-doc-1"
        )
        
        # Search for similar documents
        result = await chroma_store.search(
            query="machine learning",
            n_results=5
        )
        
        assert result.success
        assert "Search completed successfully" in result.message
        assert "results" in result.data
        assert result.data["query"] == "machine learning"
    
    @pytest.mark.asyncio
    async def test_get_document(self, chroma_store, mock_embedding_service):
        """Test document retrieval."""
        # Setup mock embedding
        mock_embedding_service.generate_single_embedding.return_value = EmbeddingResult(
            success=True,
            embeddings=[[0.1, 0.2, 0.3]],
            model_used="test-model",
            processing_time=1.0
        )
        
        await chroma_store.initialize()
        
        # Add a document first
        content = "Test document for retrieval"
        await chroma_store.add_document(
            content=content,
            doc_id="test-doc-1"
        )
        
        # Retrieve the document
        result = await chroma_store.get_document("test-doc-1")
        
        assert result.success
        assert "Document retrieved successfully" in result.message
        assert result.data["document"].content == content
        assert result.data["document"].id == "test-doc-1"
    
    @pytest.mark.asyncio
    async def test_get_nonexistent_document(self, chroma_store):
        """Test retrieval of non-existent document."""
        await chroma_store.initialize()
        
        result = await chroma_store.get_document("nonexistent-doc")
        
        assert not result.success
        assert "Document not found" in result.message
        assert "nonexistent-doc" in result.error
    
    @pytest.mark.asyncio
    async def test_delete_document(self, chroma_store, mock_embedding_service):
        """Test document deletion."""
        # Setup mock embedding
        mock_embedding_service.generate_single_embedding.return_value = EmbeddingResult(
            success=True,
            embeddings=[[0.1, 0.2, 0.3]],
            model_used="test-model",
            processing_time=1.0
        )
        
        await chroma_store.initialize()
        
        # Add a document first
        await chroma_store.add_document(
            content="Document to be deleted",
            doc_id="test-doc-1"
        )
        
        # Delete the document
        result = await chroma_store.delete_document("test-doc-1")
        
        assert result.success
        assert "Document deleted successfully" in result.message
        assert result.data["deleted_id"] == "test-doc-1"
    
    @pytest.mark.asyncio
    async def test_list_documents(self, chroma_store, mock_embedding_service):
        """Test document listing."""
        # Setup mock embedding
        mock_embedding_service.generate_single_embedding.return_value = EmbeddingResult(
            success=True,
            embeddings=[[0.1, 0.2, 0.3]],
            model_used="test-model",
            processing_time=1.0
        )
        
        await chroma_store.initialize()
        
        # Add multiple documents
        for i in range(3):
            await chroma_store.add_document(
                content=f"Test document {i}",
                doc_id=f"test-doc-{i}"
            )
        
        # List documents
        result = await chroma_store.list_documents(limit=10)
        
        assert result.success
        assert "Retrieved" in result.message
        assert len(result.data["documents"]) == 3
    
    @pytest.mark.asyncio
    async def test_get_collection_stats(self, chroma_store):
        """Test collection statistics."""
        await chroma_store.initialize()
        
        result = await chroma_store.get_collection_stats()
        
        assert result.success
        assert "Collection statistics retrieved" in result.message
        assert "collection_name" in result.data
        assert "document_count" in result.data
        assert result.data["collection_name"] == "test_collection"


class TestVectorProcessor:
    """Test vector processor functionality."""
    
    @pytest.fixture
    def temp_db_path(self):
        """Create temporary database path."""
        temp_dir = tempfile.mkdtemp()
        yield temp_dir
        shutil.rmtree(temp_dir)
    
    @pytest.fixture
    def vector_processor(self, temp_db_path):
        """Create vector processor for testing."""
        return VectorProcessor({
            "db_path": temp_db_path,
            "collection_name": "test_collection"
        })
    
    @pytest.mark.asyncio
    async def test_processor_info(self, vector_processor):
        """Test vector processor info."""
        info = vector_processor.get_processor_info()
        
        assert info["name"] == "VectorProcessor"
        assert info["local_first"] is True
        assert info["privacy_focused"] is True
        assert "store" in info["supported_tasks"]
        assert "search" in info["supported_tasks"]
    
    @pytest.mark.asyncio
    async def test_unknown_task(self, vector_processor):
        """Test vector processor with unknown task."""
        result = await vector_processor.process("content", task="unknown_task")
        
        assert not result.success
        assert "Unknown vector task" in result.error
        assert "unknown_task" in result.error
    
    @pytest.mark.asyncio
    async def test_store_task(self, vector_processor):
        """Test store task with mock."""
        with patch.object(vector_processor.vector_store, 'add_document') as mock_add:
            mock_add.return_value = VectorStoreResult(
                success=True,
                message="Document added",
                data={
                    "document_id": "test-id",
                    "embedding_model": "test-model",
                    "content_length": 12
                },
                processing_time=1.0
            )
            
            result = await vector_processor.process(
                "Test content", 
                task="store",
                metadata={"test": "data"}
            )
            
            assert result.success
            assert "Document stored successfully" in result.content
            assert result.metadata["document_id"] == "test-id"
            assert result.metadata["task"] == "store"
    
    @pytest.mark.asyncio
    async def test_search_task(self, vector_processor):
        """Test search task with mock."""
        mock_search_results = [
            MagicMock(
                document=MagicMock(
                    id="doc-1",
                    content="Test document content",
                    metadata={"source": "test"}
                ),
                similarity_score=0.95,
                rank=1
            )
        ]
        
        with patch.object(vector_processor.vector_store, 'search') as mock_search:
            mock_search.return_value = VectorStoreResult(
                success=True,
                message="Search completed",
                data={
                    "results": mock_search_results,
                    "query": "test query",
                    "total_results": 1,
                    "embedding_model": "test-model"
                },
                processing_time=1.0
            )
            
            result = await vector_processor.process(
                "test query", 
                task="search",
                n_results=5
            )
            
            assert result.success
            assert "Found 1 similar documents" in result.content
            assert result.metadata["task"] == "search"
            assert result.metadata["query"] == "test query"
            assert len(result.metadata["results"]) == 1
    
    @pytest.mark.asyncio
    async def test_retrieve_task(self, vector_processor):
        """Test retrieve task with mock."""
        mock_document = MagicMock(
            id="test-doc-1",
            content="Retrieved document content",
            metadata={"source": "test"}
        )
        
        with patch.object(vector_processor.vector_store, 'get_document') as mock_get:
            mock_get.return_value = VectorStoreResult(
                success=True,
                message="Document retrieved",
                data={"document": mock_document},
                processing_time=1.0
            )
            
            result = await vector_processor.process(
                "test-doc-1", 
                task="retrieve"
            )
            
            assert result.success
            assert result.content == "Retrieved document content"
            assert result.metadata["document_id"] == "test-doc-1"
            assert result.metadata["task"] == "retrieve"
    
    @pytest.mark.asyncio
    async def test_delete_task(self, vector_processor):
        """Test delete task with mock."""
        with patch.object(vector_processor.vector_store, 'delete_document') as mock_delete:
            mock_delete.return_value = VectorStoreResult(
                success=True,
                message="Document deleted",
                data={"deleted_id": "test-doc-1"},
                processing_time=1.0
            )
            
            result = await vector_processor.process(
                "test-doc-1", 
                task="delete"
            )
            
            assert result.success
            assert "Document test-doc-1 deleted successfully" in result.content
            assert result.metadata["deleted_id"] == "test-doc-1"
            assert result.metadata["task"] == "delete"
    
    @pytest.mark.asyncio
    async def test_list_task(self, vector_processor):
        """Test list task with mock."""
        mock_documents = [
            MagicMock(
                id=f"doc-{i}",
                content=f"Document {i} content",
                metadata={"source": f"test-{i}"}
            ) for i in range(3)
        ]
        
        with patch.object(vector_processor.vector_store, 'list_documents') as mock_list:
            mock_list.return_value = VectorStoreResult(
                success=True,
                message="Documents listed",
                data={
                    "documents": mock_documents,
                    "total_count": 3
                },
                processing_time=1.0
            )
            
            result = await vector_processor.process(
                "", 
                task="list",
                limit=10
            )
            
            assert result.success
            assert "Retrieved 3 documents" in result.content
            assert result.metadata["task"] == "list"
            assert len(result.metadata["documents"]) == 3
    
    @pytest.mark.asyncio
    async def test_stats_task(self, vector_processor):
        """Test stats task with mock."""
        mock_stats = {
            "collection_name": "test_collection",
            "document_count": 5,
            "db_path": "/test/path",
            "embedding_service_info": {"test": "info"}
        }
        
        with patch.object(vector_processor.vector_store, 'get_collection_stats') as mock_stats_call:
            mock_stats_call.return_value = VectorStoreResult(
                success=True,
                message="Stats retrieved",
                data=mock_stats,
                processing_time=1.0
            )
            
            result = await vector_processor.process("", task="stats")
            
            assert result.success
            assert "Collection 'test_collection' contains 5 documents" in result.content
            assert result.metadata["task"] == "stats"
            assert result.metadata["collection_stats"] == mock_stats


if __name__ == "__main__":
    pytest.main([__file__])