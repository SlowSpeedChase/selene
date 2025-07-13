"""
Vector database processor for storing and retrieving note content.
"""

import asyncio
import time
from typing import Dict, Any, Optional, List
from loguru import logger

from .base import BaseProcessor, ProcessorResult
from ..vector.chroma_store import ChromaStore, VectorStoreResult
from ..vector.embedding_service import EmbeddingService


class VectorProcessor(BaseProcessor):
    """Processor for vector database operations."""
    
    def __init__(self, config: Optional[Dict[str, Any]] = None):
        """Initialize vector processor with configuration."""
        super().__init__(config)
        
        # Initialize vector store
        db_path = self.config.get('db_path', './chroma_db')
        collection_name = self.config.get('collection_name', 'selene_notes')
        
        embedding_service = EmbeddingService(
            prefer_local=self.config.get('prefer_local_embeddings', True),
            local_model=self.config.get('local_embedding_model', 'nomic-embed-text'),
            openai_model=self.config.get('openai_embedding_model', 'text-embedding-3-small')
        )
        
        self.vector_store = ChromaStore(
            db_path=db_path,
            collection_name=collection_name,
            embedding_service=embedding_service
        )
        
        self._initialized = False
    
    async def _ensure_initialized(self):
        """Ensure vector store is initialized."""
        if not self._initialized:
            result = await self.vector_store.initialize()
            if not result.success:
                raise Exception(f"Failed to initialize vector store: {result.error}")
            self._initialized = True
    
    async def process(self, content: str, task: str = "store", **kwargs) -> ProcessorResult:
        """
        Process content with vector database operations.
        
        Args:
            content: Content to process
            task: Vector operation to perform (store, search, retrieve, delete, list, stats)
            **kwargs: Additional parameters for the operation
            
        Returns:
            ProcessorResult with operation results
        """
        start_time = time.time()
        
        try:
            await self._ensure_initialized()
            
            if task == "store":
                return await self._store_document(content, **kwargs)
            elif task == "search":
                return await self._search_documents(content, **kwargs)
            elif task == "retrieve":
                return await self._retrieve_document(content, **kwargs)
            elif task == "delete":
                return await self._delete_document(content, **kwargs)
            elif task == "list":
                return await self._list_documents(**kwargs)
            elif task == "stats":
                return await self._get_stats()
            else:
                return ProcessorResult(
                    success=False,
                    content="",
                    metadata={"task": task},
                    error=f"Unknown vector task: {task}. Available tasks: store, search, retrieve, delete, list, stats",
                    processing_time=time.time() - start_time
                )
                
        except Exception as e:
            logger.error(f"Vector processing failed: {str(e)}")
            return ProcessorResult(
                success=False,
                content="",
                metadata={"task": task},
                error=f"Vector processing error: {str(e)}",
                processing_time=time.time() - start_time
            )
    
    async def _store_document(self, content: str, **kwargs) -> ProcessorResult:
        """Store a document in the vector database."""
        metadata = kwargs.get('metadata', {})
        doc_id = kwargs.get('doc_id')
        file_path = kwargs.get('file_path')
        
        # Add file path to metadata if provided
        if file_path:
            metadata['source_file'] = file_path
        
        result = await self.vector_store.add_document(
            content=content,
            metadata=metadata,
            doc_id=doc_id
        )
        
        if result.success:
            return ProcessorResult(
                success=True,
                content=f"Document stored successfully with ID: {result.data['document_id']}",
                metadata={
                    "task": "store",
                    "document_id": result.data['document_id'],
                    "embedding_model": result.data['embedding_model'],
                    "content_length": result.data['content_length']
                },
                processing_time=result.processing_time
            )
        else:
            return ProcessorResult(
                success=False,
                content="",
                metadata={"task": "store"},
                error=result.error,
                processing_time=result.processing_time
            )
    
    async def _search_documents(self, query: str, **kwargs) -> ProcessorResult:
        """Search for similar documents."""
        n_results = kwargs.get('n_results', 5)
        where_filter = kwargs.get('where')
        
        result = await self.vector_store.search(
            query=query,
            n_results=n_results,
            where=where_filter
        )
        
        if result.success:
            search_results = result.data['results']
            
            # Format search results for display
            formatted_results = []
            for search_result in search_results:
                doc = search_result.document
                formatted_results.append({
                    "rank": search_result.rank,
                    "similarity_score": round(search_result.similarity_score, 3),
                    "document_id": doc.id,
                    "content_preview": doc.content[:200] + "..." if len(doc.content) > 200 else doc.content,
                    "metadata": doc.metadata
                })
            
            return ProcessorResult(
                success=True,
                content=f"Found {len(search_results)} similar documents",
                metadata={
                    "task": "search",
                    "query": query,
                    "results": formatted_results,
                    "total_results": len(search_results),
                    "embedding_model": result.data['embedding_model']
                },
                processing_time=result.processing_time
            )
        else:
            return ProcessorResult(
                success=False,
                content="",
                metadata={"task": "search", "query": query},
                error=result.error,
                processing_time=result.processing_time
            )
    
    async def _retrieve_document(self, doc_id: str, **kwargs) -> ProcessorResult:
        """Retrieve a specific document by ID."""
        result = await self.vector_store.get_document(doc_id)
        
        if result.success:
            document = result.data['document']
            return ProcessorResult(
                success=True,
                content=document.content,
                metadata={
                    "task": "retrieve",
                    "document_id": document.id,
                    "document_metadata": document.metadata
                },
                processing_time=result.processing_time
            )
        else:
            return ProcessorResult(
                success=False,
                content="",
                metadata={"task": "retrieve", "document_id": doc_id},
                error=result.error,
                processing_time=result.processing_time
            )
    
    async def _delete_document(self, doc_id: str, **kwargs) -> ProcessorResult:
        """Delete a document from the vector database."""
        result = await self.vector_store.delete_document(doc_id)
        
        if result.success:
            return ProcessorResult(
                success=True,
                content=f"Document {doc_id} deleted successfully",
                metadata={
                    "task": "delete",
                    "deleted_id": result.data['deleted_id']
                },
                processing_time=result.processing_time
            )
        else:
            return ProcessorResult(
                success=False,
                content="",
                metadata={"task": "delete", "document_id": doc_id},
                error=result.error,
                processing_time=result.processing_time
            )
    
    async def _list_documents(self, **kwargs) -> ProcessorResult:
        """List all documents in the collection."""
        limit = kwargs.get('limit', 20)
        
        result = await self.vector_store.list_documents(limit=limit)
        
        if result.success:
            documents = result.data['documents']
            
            # Format document list for display
            formatted_docs = []
            for doc in documents:
                formatted_docs.append({
                    "document_id": doc.id,
                    "content_preview": doc.content[:100] + "..." if len(doc.content) > 100 else doc.content,
                    "metadata": doc.metadata
                })
            
            return ProcessorResult(
                success=True,
                content=f"Retrieved {len(documents)} documents",
                metadata={
                    "task": "list",
                    "documents": formatted_docs,
                    "total_count": result.data['total_count']
                },
                processing_time=result.processing_time
            )
        else:
            return ProcessorResult(
                success=False,
                content="",
                metadata={"task": "list"},
                error=result.error,
                processing_time=result.processing_time
            )
    
    async def _get_stats(self) -> ProcessorResult:
        """Get collection statistics."""
        result = await self.vector_store.get_collection_stats()
        
        if result.success:
            stats = result.data
            
            return ProcessorResult(
                success=True,
                content=f"Collection '{stats['collection_name']}' contains {stats['document_count']} documents",
                metadata={
                    "task": "stats",
                    "collection_stats": stats
                },
                processing_time=result.processing_time
            )
        else:
            return ProcessorResult(
                success=False,
                content="",
                metadata={"task": "stats"},
                error=result.error,
                processing_time=result.processing_time
            )
    
    def get_processor_info(self) -> Dict[str, Any]:
        """Get information about this processor."""
        return {
            "name": "VectorProcessor",
            "version": "1.0.0",
            "description": "Local vector database processor using ChromaDB",
            "capabilities": [
                "store documents with embeddings",
                "semantic search and retrieval", 
                "document management (retrieve, delete, list)",
                "collection statistics",
                "local and cloud embedding generation"
            ],
            "supported_tasks": ["store", "search", "retrieve", "delete", "list", "stats"],
            "local_first": True,
            "privacy_focused": True,
            "config": {
                "db_path": self.config.get('db_path', './chroma_db'),
                "collection_name": self.config.get('collection_name', 'selene_notes'),
                "prefer_local_embeddings": self.config.get('prefer_local_embeddings', True)
            }
        }