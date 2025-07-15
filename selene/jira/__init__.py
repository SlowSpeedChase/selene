"""
JIRA integration module for Selene.

This module provides JIRA API integration for project tracking,
ticket management, and automated sync functionality.
"""

from .client import JiraClient
from .ticket_manager import TicketManager

__all__ = ["JiraClient", "TicketManager"]
