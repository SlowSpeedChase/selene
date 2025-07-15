"""
ChromaDB vector store for local document storage and retrieval.
"""

import asyncio
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import chromadb
from chromadb.config import Settings
from loguru import logger

from .embedding_service import EmbeddingResult, EmbeddingService


@dataclass
class Document:
    """Document stored in vector database."""

    id: str
    content: str
    metadata: Dict[str, Any]
    embedding: Optional[List[float]] = None


@dataclass
class SearchResult:
    """Result of semantic search."""

    document: Document
    similarity_score: float
    rank: int


@dataclass
class VectorStoreResult:
    """Result of vector store operations."""

    success: bool
    message: str
    data: Optional[Any] = None
    error: Optional[str] = None
    processing_time: Optional[float] = None


class ChromaStore:
    """ChromaDB-based vector store for local document storage and retrieval."""

    def __init__(
        self,
        db_path: str = "./chroma_db",
        collection_name: str = "selene_notes",
        embedding_service: Optional[EmbeddingService] = None,
    ):
        """
        Initialize ChromaDB vector store.

        Args:
            db_path: Path to ChromaDB database directory
            collection_name: Name of the collection to store documents
            embedding_service: Service for generating embeddings
        """
        self.db_path = Path(db_path)
        self.collection_name = collection_name
        self.embedding_service = embedding_service or EmbeddingService()

        # Initialize ChromaDB client
        self.client = None
        self.collection = None

    async def initialize(self) -> VectorStoreResult:
        """Initialize the vector store and create collection if needed."""
        start_time = time.time()
        try:
            # Create database directory if it doesn't exist
            self.db_path.mkdir(parents=True, exist_ok=True)

            # Initialize ChromaDB client with persistent storage
            self.client = chromadb.PersistentClient(
                path=str(self.db_path),
                settings=Settings(anonymized_telemetry=False, allow_reset=True),
            )

            # Get or create collection
            try:
                self.collection = self.client.get_collection(self.collection_name)
                logger.info(f"Loaded existing collection: {self.collection_name}")
            except Exception:
                self.collection = self.client.create_collection(
                    name=self.collection_name,
                    metadata={"description": "Selene note processing system documents"},
                )
                logger.info(f"Created new collection: {self.collection_name}")

            return VectorStoreResult(
                success=True,
                message=f"Vector store initialized successfully",
                data={
                    "collection_name": self.collection_name,
                    "db_path": str(self.db_path),
                },
                processing_time=time.time() - start_time,
            )

        except Exception as e:
            error_msg = f"Failed to initialize vector store: {str(e)}"
            logger.error(error_msg)
            return VectorStoreResult(
                success=False,
                message="Vector store initialization failed",
                error=error_msg,
                processing_time=time.time() - start_time,
            )

    async def add_document(
        self,
        content: str,
        metadata: Optional[Dict[str, Any]] = None,
        doc_id: Optional[str] = None,
    ) -> VectorStoreResult:
        """
        Add a document to the vector store.

        Args:
            content: Document content
            metadata: Optional metadata for the document
            doc_id: Optional custom document ID

        Returns:
            VectorStoreResult with operation status
        """
        start_time = time.time()

        if not self.collection:
            await self.initialize()

        try:
            # Generate document ID if not provided
            if not doc_id:
                doc_id = str(uuid.uuid4())

            # Generate embedding for the content
            embedding_result = await self.embedding_service.generate_single_embedding(
                content
            )
            if not embedding_result.success:
                return VectorStoreResult(
                    success=False,
                    message="Failed to generate embedding",
                    error=embedding_result.error,
                    processing_time=time.time() - start_time,
                )

            # Prepare metadata
            doc_metadata = metadata or {}
            doc_metadata.update(
                {
                    "content_length": len(content),
                    "embedding_model": embedding_result.model_used,
                    "created_at": time.time(),
                }
            )

            # Add to ChromaDB
            self.collection.add(
                ids=[doc_id],
                documents=[content],
                embeddings=[embedding_result.embeddings[0]],
                metadatas=[doc_metadata],
            )

            logger.info(f"Added document {doc_id} to vector store")

            return VectorStoreResult(
                success=True,
                message=f"Document added successfully",
                data={
                    "document_id": doc_id,
                    "embedding_model": embedding_result.model_used,
                    "content_length": len(content),
                },
                processing_time=time.time() - start_time,
            )

        except Exception as e:
            error_msg = f"Failed to add document: {str(e)}"
            logger.error(error_msg)
            return VectorStoreResult(
                success=False,
                message="Document addition failed",
                error=error_msg,
                processing_time=time.time() - start_time,
            )

    async def search(
        self, query: str, n_results: int = 5, where: Optional[Dict[str, Any]] = None
    ) -> VectorStoreResult:
        """
        Search for similar documents.

        Args:
            query: Search query text
            n_results: Number of results to return
            where: Optional metadata filter

        Returns:
            VectorStoreResult with search results
        """
        start_time = time.time()

        if not self.collection:
            await self.initialize()

        try:
            # Generate embedding for query
            embedding_result = await self.embedding_service.generate_single_embedding(
                query
            )
            if not embedding_result.success:
                return VectorStoreResult(
                    success=False,
                    message="Failed to generate query embedding",
                    error=embedding_result.error,
                    processing_time=time.time() - start_time,
                )

            # Search in ChromaDB
            search_results = self.collection.query(
                query_embeddings=[embedding_result.embeddings[0]],
                n_results=n_results,
                where=where,
                include=["documents", "metadatas", "distances"],
            )

            # Format results
            results = []
            if search_results["ids"] and search_results["ids"][0]:
                for i, doc_id in enumerate(search_results["ids"][0]):
                    document = Document(
                        id=doc_id,
                        content=search_results["documents"][0][i],
                        metadata=search_results["metadatas"][0][i],
                    )

                    # Convert distance to similarity score (higher = more similar)
                    distance = search_results["distances"][0][i]
                    similarity_score = 1.0 / (1.0 + distance)

                    search_result = SearchResult(
                        document=document, similarity_score=similarity_score, rank=i + 1
                    )
                    results.append(search_result)

            logger.info(f"Found {len(results)} similar documents for query")

            return VectorStoreResult(
                success=True,
                message=f"Search completed successfully",
                data={
                    "results": results,
                    "query": query,
                    "total_results": len(results),
                    "embedding_model": embedding_result.model_used,
                },
                processing_time=time.time() - start_time,
            )

        except Exception as e:
            error_msg = f"Search failed: {str(e)}"
            logger.error(error_msg)
            return VectorStoreResult(
                success=False,
                message="Search operation failed",
                error=error_msg,
                processing_time=time.time() - start_time,
            )

    async def get_document(self, doc_id: str) -> VectorStoreResult:
        """
        Retrieve a specific document by ID.

        Args:
            doc_id: Document ID to retrieve

        Returns:
            VectorStoreResult with document data
        """
        start_time = time.time()

        if not self.collection:
            await self.initialize()

        try:
            result = self.collection.get(
                ids=[doc_id], include=["documents", "metadatas"]
            )

            if not result["ids"] or not result["ids"][0]:
                return VectorStoreResult(
                    success=False,
                    message="Document not found",
                    error=f"No document found with ID: {doc_id}",
                    processing_time=time.time() - start_time,
                )

            document = Document(
                id=result["ids"][0],
                content=result["documents"][0],
                metadata=result["metadatas"][0],
            )

            return VectorStoreResult(
                success=True,
                message="Document retrieved successfully",
                data={"document": document},
                processing_time=time.time() - start_time,
            )

        except Exception as e:
            error_msg = f"Failed to retrieve document: {str(e)}"
            logger.error(error_msg)
            return VectorStoreResult(
                success=False,
                message="Document retrieval failed",
                error=error_msg,
                processing_time=time.time() - start_time,
            )

    async def delete_document(self, doc_id: str) -> VectorStoreResult:
        """
        Delete a document from the vector store.

        Args:
            doc_id: Document ID to delete

        Returns:
            VectorStoreResult with operation status
        """
        start_time = time.time()

        if not self.collection:
            await self.initialize()

        try:
            self.collection.delete(ids=[doc_id])

            logger.info(f"Deleted document {doc_id} from vector store")

            return VectorStoreResult(
                success=True,
                message="Document deleted successfully",
                data={"deleted_id": doc_id},
                processing_time=time.time() - start_time,
            )

        except Exception as e:
            error_msg = f"Failed to delete document: {str(e)}"
            logger.error(error_msg)
            return VectorStoreResult(
                success=False,
                message="Document deletion failed",
                error=error_msg,
                processing_time=time.time() - start_time,
            )

    async def list_documents(self, limit: int = 100) -> VectorStoreResult:
        """
        List all documents in the collection.

        Args:
            limit: Maximum number of documents to return

        Returns:
            VectorStoreResult with document list
        """
        start_time = time.time()

        if not self.collection:
            await self.initialize()

        try:
            result = self.collection.get(
                limit=limit, include=["documents", "metadatas"]
            )

            documents = []
            if result["ids"]:
                for i, doc_id in enumerate(result["ids"]):
                    document = Document(
                        id=doc_id,
                        content=result["documents"][i],
                        metadata=result["metadatas"][i],
                    )
                    documents.append(document)

            return VectorStoreResult(
                success=True,
                message=f"Retrieved {len(documents)} documents",
                data={"documents": documents, "total_count": len(documents)},
                processing_time=time.time() - start_time,
            )

        except Exception as e:
            error_msg = f"Failed to list documents: {str(e)}"
            logger.error(error_msg)
            return VectorStoreResult(
                success=False,
                message="Document listing failed",
                error=error_msg,
                processing_time=time.time() - start_time,
            )

    async def get_collection_stats(self) -> VectorStoreResult:
        """Get statistics about the collection."""
        start_time = time.time()

        if not self.collection:
            await self.initialize()

        try:
            count = self.collection.count()

            stats = {
                "collection_name": self.collection_name,
                "document_count": count,
                "db_path": str(self.db_path),
                "embedding_service_info": self.embedding_service.get_embedding_info(),
            }

            return VectorStoreResult(
                success=True,
                message="Collection statistics retrieved",
                data=stats,
                processing_time=time.time() - start_time,
            )

        except Exception as e:
            error_msg = f"Failed to get collection stats: {str(e)}"
            logger.error(error_msg)
            return VectorStoreResult(
                success=False,
                message="Stats retrieval failed",
                error=error_msg,
                processing_time=time.time() - start_time,
            )
