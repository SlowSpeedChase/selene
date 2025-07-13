"""
Note processing pipeline for Selene.

This module provides interfaces and implementations for processing notes
using various AI models and processing techniques.
"""

from .base import BaseProcessor, ProcessorResult
from .llm_processor import LLMProcessor
from .ollama_processor import OllamaProcessor
from .vector_processor import VectorProcessor

__all__ = ["BaseProcessor", "ProcessorResult", "LLMProcessor", "OllamaProcessor", "VectorProcessor"]