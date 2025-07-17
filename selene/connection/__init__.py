"""
Connection management module for Selene.

This module provides centralized connection management for external services,
starting with Ollama connection management in SMS-32.
"""

from .ollama_manager import OllamaConnectionManager, OllamaConfig, ConnectionStatus

__all__ = ["OllamaConnectionManager", "OllamaConfig", "ConnectionStatus"]