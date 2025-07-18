"""
Connection Analysis Module

This module provides functionality for discovering and analyzing meaningful connections
between notes in the Second Brain system. It implements sophisticated algorithms to
find semantic, temporal, topical, and reference-based relationships between notes.

Key Features:
- Connection discovery using vector similarity and content analysis
- Connection taxonomy with confidence scoring
- Bidirectional link management
- Connection analytics and statistics
- Integration with existing vector database and web interface

Components:
- models.py: Data models for connections and related entities
- discovery.py: Core connection discovery algorithms
- analyzer.py: Connection analysis and scoring logic
- storage.py: Database operations for connections
- statistics.py: Analytics and reporting for connection patterns
"""

from .models import Connection, ConnectionType, ConnectionStatistics, ConnectionFilter, NoteConnectionSummary
from .discovery import ConnectionDiscovery
from .analyzer import ConnectionAnalyzer
from .storage import ConnectionStorage
from .statistics import ConnectionStatisticsCollector

__all__ = [
    "Connection",
    "ConnectionType", 
    "ConnectionStatistics",
    "ConnectionFilter",
    "NoteConnectionSummary",
    "ConnectionDiscovery",
    "ConnectionAnalyzer",
    "ConnectionStorage",
    "ConnectionStatisticsCollector",
]