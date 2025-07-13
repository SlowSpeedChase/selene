"""
File monitoring module for Selene.

This module provides real-time file system monitoring capabilities
for automatic document processing and AI analysis.
"""

from .file_watcher import FileWatcher
from .monitor_config import MonitorConfig

__all__ = ["FileWatcher", "MonitorConfig"]