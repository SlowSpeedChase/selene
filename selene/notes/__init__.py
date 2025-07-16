"""
Note management and formatting system for Selene.

This module provides comprehensive note formatting, structuring, and organization
capabilities for creating well-structured Obsidian-compatible notes.
"""

from .formatter import NoteFormatter, NoteTemplate, NoteFormat
from .metadata import FrontmatterManager, NoteMetadata
from .structure import NoteSection, NoteBuilder, NoteStructure, SectionType

__all__ = [
    "NoteFormatter",
    "NoteTemplate", 
    "NoteFormat",
    "NoteStructure",
    "FrontmatterManager",
    "NoteMetadata",
    "NoteSection",
    "NoteBuilder",
    "SectionType"
]