"""
Vector database module for Selene.

This module provides local vector database functionality using ChromaDB
for storing and retrieving document embeddings.
"""

from .chroma_store import ChromaStore
from .embedding_service import EmbeddingService

__all__ = ["ChromaStore", "EmbeddingService"]
