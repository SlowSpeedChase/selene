"""
SELENE Chat Module - Conversational AI Agent for Obsidian Vault Management

This module provides a conversational AI agent that can interact with Obsidian vaults
through natural language, similar to how Claude Code interacts with codebases.
"""

from .agent import ChatAgent
from .config import ChatConfig
from .tools.base import BaseTool, ToolRegistry

__all__ = ["ChatAgent", "ChatConfig", "BaseTool", "ToolRegistry"]