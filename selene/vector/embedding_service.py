"""
Embedding service for generating vector embeddings from text.
"""

import asyncio
import os
import time
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

import openai
from loguru import logger

try:
    import ollama

    OLLAMA_AVAILABLE = True
except ImportError:
    OLLAMA_AVAILABLE = False
    logger.warning("Ollama not available for embeddings")


@dataclass
class EmbeddingResult:
    """Result of embedding generation."""

    success: bool
    embeddings: List[List[float]]
    model_used: str
    processing_time: float
    error: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None


class EmbeddingService:
    """Service for generating text embeddings using local or cloud models."""

    def __init__(
        self,
        prefer_local: bool = True,
        local_model: str = "nomic-embed-text",
        openai_model: str = "text-embedding-3-small",
    ):
        """
        Initialize embedding service.

        Args:
            prefer_local: Whether to prefer local embeddings over cloud
            local_model: Local embedding model to use with Ollama
            openai_model: OpenAI embedding model to use as fallback
        """
        self.prefer_local = prefer_local
        self.local_model = local_model
        self.openai_model = openai_model
        self.openai_client = None

        # Initialize OpenAI client if API key is available
        if os.getenv("OPENAI_API_KEY"):
            self.openai_client = openai.OpenAI()

    async def _get_local_embeddings(self, texts: List[str]) -> EmbeddingResult:
        """Generate embeddings using local Ollama model."""
        if not OLLAMA_AVAILABLE:
            return EmbeddingResult(
                success=False,
                embeddings=[],
                model_used="",
                processing_time=0.0,
                error="Ollama not available",
            )

        start_time = time.time()
        try:
            # Check if model is available
            available_models = []
            try:
                models_response = ollama.list()
                available_models = [
                    model["name"] for model in models_response.get("models", [])
                ]
            except Exception as e:
                logger.warning(f"Could not list Ollama models: {e}")

            # Use best available embedding model
            model_to_use = self._find_best_embedding_model(available_models)
            if not model_to_use:
                return EmbeddingResult(
                    success=False,
                    embeddings=[],
                    model_used="",
                    processing_time=time.time() - start_time,
                    error=f"No suitable embedding model available. Consider installing: {self.local_model}",
                )

            embeddings = []
            for text in texts:
                response = ollama.embeddings(model=model_to_use, prompt=text)
                embeddings.append(response["embedding"])

            return EmbeddingResult(
                success=True,
                embeddings=embeddings,
                model_used=model_to_use,
                processing_time=time.time() - start_time,
                metadata={"provider": "ollama", "local": True},
            )

        except Exception as e:
            return EmbeddingResult(
                success=False,
                embeddings=[],
                model_used="",
                processing_time=time.time() - start_time,
                error=f"Local embedding generation failed: {str(e)}",
            )

    async def _get_openai_embeddings(self, texts: List[str]) -> EmbeddingResult:
        """Generate embeddings using OpenAI API."""
        if not self.openai_client:
            return EmbeddingResult(
                success=False,
                embeddings=[],
                model_used="",
                processing_time=0.0,
                error="OpenAI API key not configured",
            )

        start_time = time.time()
        try:
            response = self.openai_client.embeddings.create(
                model=self.openai_model, input=texts
            )

            embeddings = [item.embedding for item in response.data]

            return EmbeddingResult(
                success=True,
                embeddings=embeddings,
                model_used=self.openai_model,
                processing_time=time.time() - start_time,
                metadata={
                    "provider": "openai",
                    "local": False,
                    "usage": response.usage.total_tokens,
                },
            )

        except Exception as e:
            return EmbeddingResult(
                success=False,
                embeddings=[],
                model_used="",
                processing_time=time.time() - start_time,
                error=f"OpenAI embedding generation failed: {str(e)}",
            )

    def _find_best_embedding_model(self, available_models: List[str]) -> Optional[str]:
        """Find the best available embedding model."""
        preference_order = [
            "nomic-embed-text",
            "nomic-embed-text:latest",
            "mxbai-embed-large",
            "mxbai-embed-large:latest",
            "all-minilm",
            "all-minilm:latest",
        ]

        for preferred in preference_order:
            if preferred in available_models:
                return preferred

        # Look for any embedding model
        embedding_keywords = ["embed", "embedding"]
        for model in available_models:
            if any(keyword in model.lower() for keyword in embedding_keywords):
                return model

        return None

    async def generate_embeddings(self, texts: List[str]) -> EmbeddingResult:
        """
        Generate embeddings for a list of texts.

        Args:
            texts: List of text strings to embed

        Returns:
            EmbeddingResult with generated embeddings
        """
        if not texts:
            return EmbeddingResult(
                success=False,
                embeddings=[],
                model_used="",
                processing_time=0.0,
                error="No texts provided for embedding",
            )

        # Try local first if preferred
        if self.prefer_local:
            logger.info("Attempting local embedding generation...")
            result = await self._get_local_embeddings(texts)
            if result.success:
                logger.info(
                    f"Local embeddings generated successfully with {result.model_used}"
                )
                return result
            else:
                logger.warning(f"Local embedding failed: {result.error}")

        # Fallback to OpenAI
        logger.info("Attempting OpenAI embedding generation...")
        result = await self._get_openai_embeddings(texts)
        if result.success:
            logger.info(
                f"OpenAI embeddings generated successfully with {result.model_used}"
            )
            return result
        else:
            logger.error(f"All embedding methods failed. Last error: {result.error}")
            return result

    async def generate_single_embedding(self, text: str) -> EmbeddingResult:
        """
        Generate embedding for a single text.

        Args:
            text: Text string to embed

        Returns:
            EmbeddingResult with single embedding
        """
        result = await self.generate_embeddings([text])
        return result

    def get_embedding_info(self) -> Dict[str, Any]:
        """Get information about embedding service configuration."""
        return {
            "prefer_local": self.prefer_local,
            "local_model": self.local_model,
            "openai_model": self.openai_model,
            "ollama_available": OLLAMA_AVAILABLE,
            "openai_configured": self.openai_client is not None,
        }
