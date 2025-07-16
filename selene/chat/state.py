"""
Conversation state management for SELENE chatbot agent.
"""

import asyncio
import json
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional
from uuid import uuid4

from loguru import logger

from .config import ChatConfig


class ConversationState:
    """Manages conversation state and memory for the chat agent."""
    
    def __init__(self, config: ChatConfig):
        """Initialize conversation state manager."""
        self.config = config
        self.db_path = config.get_memory_db_path()
        self.conversation_id = str(uuid4())
        self.messages: List[Dict[str, Any]] = []
        self._db_connection: Optional[sqlite3.Connection] = None
        
    async def initialize(self) -> None:
        """Initialize conversation memory database."""
        if not self.config.conversation_memory:
            return
            
        try:
            # Create database directory if needed
            self.db_path.parent.mkdir(parents=True, exist_ok=True)
            
            # Initialize database
            self._db_connection = sqlite3.connect(str(self.db_path))
            self._db_connection.row_factory = sqlite3.Row
            
            # Create tables
            await self._create_tables()
            
            logger.debug(f"Conversation memory initialized: {self.db_path}")
            
        except Exception as e:
            logger.error(f"Failed to initialize conversation memory: {e}")
            self._db_connection = None
            
    async def _create_tables(self) -> None:
        """Create database tables for conversation storage."""
        if not self._db_connection:
            return
            
        cursor = self._db_connection.cursor()
        
        # Conversations table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY,
                vault_path TEXT,
                started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                ended_at TIMESTAMP,
                message_count INTEGER DEFAULT 0,
                metadata TEXT
            )
        """)
        
        # Messages table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                conversation_id TEXT,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                metadata TEXT,
                FOREIGN KEY (conversation_id) REFERENCES conversations (id)
            )
        """)
        
        # Context table for storing important context
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS context (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                conversation_id TEXT,
                context_type TEXT NOT NULL,
                context_data TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (conversation_id) REFERENCES conversations (id)
            )
        """)
        
        self._db_connection.commit()
        
    async def start_conversation(self, vault_path: Optional[str] = None) -> str:
        """
        Start a new conversation.
        
        Args:
            vault_path: Path to the vault for this conversation
            
        Returns:
            Conversation ID
        """
        self.conversation_id = str(uuid4())
        self.messages = []
        
        if self._db_connection:
            try:
                cursor = self._db_connection.cursor()
                cursor.execute("""
                    INSERT INTO conversations (id, vault_path, metadata)
                    VALUES (?, ?, ?)
                """, (
                    self.conversation_id,
                    vault_path,
                    json.dumps({"agent_version": "1.0", "config": "default"})
                ))
                self._db_connection.commit()
                
                logger.debug(f"Started conversation: {self.conversation_id}")
                
            except Exception as e:
                logger.error(f"Failed to save conversation start: {e}")
                
        return self.conversation_id
        
    async def add_message(self, role: str, content: str, metadata: Optional[Dict[str, Any]] = None) -> None:
        """
        Add a message to the conversation.
        
        Args:
            role: Message role (user, assistant, system)
            content: Message content
            metadata: Optional metadata for the message
        """
        message = {
            "role": role,
            "content": content,
            "timestamp": datetime.now().isoformat(),
            "metadata": metadata or {}
        }
        
        self.messages.append(message)
        
        # Limit message history to prevent memory issues
        if len(self.messages) > self.config.max_conversation_history:
            self.messages = self.messages[-self.config.max_conversation_history:]
            
        # Save to database
        if self._db_connection:
            try:
                cursor = self._db_connection.cursor()
                cursor.execute("""
                    INSERT INTO messages (conversation_id, role, content, metadata)
                    VALUES (?, ?, ?, ?)
                """, (
                    self.conversation_id,
                    role,
                    content,
                    json.dumps(metadata) if metadata else None
                ))
                self._db_connection.commit()
                
            except Exception as e:
                logger.error(f"Failed to save message: {e}")
                
    async def get_context(self, window_size: Optional[int] = None) -> List[Dict[str, Any]]:
        """
        Get conversation context for AI processing.
        
        Args:
            window_size: Number of recent messages to include
            
        Returns:
            List of recent messages
        """
        size = window_size or self.config.context_window_size
        return self.messages[-size:] if self.messages else []
        
    async def get_conversation_summary(self) -> Dict[str, Any]:
        """Get summary of current conversation."""
        return {
            "conversation_id": self.conversation_id,
            "message_count": len(self.messages),
            "started_at": self.messages[0]["timestamp"] if self.messages else None,
            "last_message_at": self.messages[-1]["timestamp"] if self.messages else None,
            "roles": list(set(msg["role"] for msg in self.messages))
        }
        
    async def search_conversations(self, query: str, limit: int = 10) -> List[Dict[str, Any]]:
        """
        Search through conversation history.
        
        Args:
            query: Search query
            limit: Maximum results to return
            
        Returns:
            List of matching conversation snippets
        """
        if not self._db_connection:
            return []
            
        try:
            cursor = self._db_connection.cursor()
            cursor.execute("""
                SELECT c.id, c.vault_path, c.started_at, m.role, m.content, m.timestamp
                FROM conversations c
                JOIN messages m ON c.id = m.conversation_id
                WHERE m.content LIKE ?
                ORDER BY m.timestamp DESC
                LIMIT ?
            """, (f"%{query}%", limit))
            
            results = []
            for row in cursor.fetchall():
                results.append({
                    "conversation_id": row["id"],
                    "vault_path": row["vault_path"],
                    "conversation_started": row["started_at"],
                    "message_role": row["role"],
                    "message_content": row["content"],
                    "message_timestamp": row["timestamp"]
                })
                
            return results
            
        except Exception as e:
            logger.error(f"Failed to search conversations: {e}")
            return []
            
    async def get_conversation_history(self, conversation_id: str) -> List[Dict[str, Any]]:
        """
        Get full history for a specific conversation.
        
        Args:
            conversation_id: ID of conversation to retrieve
            
        Returns:
            List of messages in the conversation
        """
        if not self._db_connection:
            return []
            
        try:
            cursor = self._db_connection.cursor()
            cursor.execute("""
                SELECT role, content, timestamp, metadata
                FROM messages
                WHERE conversation_id = ?
                ORDER BY timestamp ASC
            """, (conversation_id,))
            
            messages = []
            for row in cursor.fetchall():
                message = {
                    "role": row["role"],
                    "content": row["content"],
                    "timestamp": row["timestamp"],
                    "metadata": json.loads(row["metadata"]) if row["metadata"] else {}
                }
                messages.append(message)
                
            return messages
            
        except Exception as e:
            logger.error(f"Failed to get conversation history: {e}")
            return []
            
    async def save_context(self, context_type: str, context_data: Dict[str, Any]) -> None:
        """
        Save important context information.
        
        Args:
            context_type: Type of context (vault_state, user_preferences, etc.)
            context_data: Context data to save
        """
        if not self._db_connection:
            return
            
        try:
            cursor = self._db_connection.cursor()
            cursor.execute("""
                INSERT INTO context (conversation_id, context_type, context_data)
                VALUES (?, ?, ?)
            """, (
                self.conversation_id,
                context_type,
                json.dumps(context_data)
            ))
            self._db_connection.commit()
            
        except Exception as e:
            logger.error(f"Failed to save context: {e}")
            
    async def get_context_data(self, context_type: str) -> List[Dict[str, Any]]:
        """
        Get saved context data.
        
        Args:
            context_type: Type of context to retrieve
            
        Returns:
            List of context data entries
        """
        if not self._db_connection:
            return []
            
        try:
            cursor = self._db_connection.cursor()
            cursor.execute("""
                SELECT context_data, created_at
                FROM context
                WHERE conversation_id = ? AND context_type = ?
                ORDER BY created_at DESC
            """, (self.conversation_id, context_type))
            
            results = []
            for row in cursor.fetchall():
                results.append({
                    "data": json.loads(row["context_data"]),
                    "created_at": row["created_at"]
                })
                
            return results
            
        except Exception as e:
            logger.error(f"Failed to get context data: {e}")
            return []
            
    async def end_conversation(self) -> None:
        """End the current conversation."""
        if self._db_connection:
            try:
                cursor = self._db_connection.cursor()
                cursor.execute("""
                    UPDATE conversations
                    SET ended_at = CURRENT_TIMESTAMP, message_count = ?
                    WHERE id = ?
                """, (len(self.messages), self.conversation_id))
                self._db_connection.commit()
                
                logger.debug(f"Ended conversation: {self.conversation_id}")
                
            except Exception as e:
                logger.error(f"Failed to end conversation: {e}")
                
    async def save(self) -> None:
        """Save current conversation state."""
        if self._db_connection:
            try:
                self._db_connection.commit()
                logger.debug("Conversation state saved")
            except Exception as e:
                logger.error(f"Failed to save conversation state: {e}")
                
    async def get_statistics(self) -> Dict[str, Any]:
        """Get conversation statistics."""
        if not self._db_connection:
            return {}
            
        try:
            cursor = self._db_connection.cursor()
            
            # Total conversations
            cursor.execute("SELECT COUNT(*) FROM conversations")
            total_conversations = cursor.fetchone()[0]
            
            # Total messages
            cursor.execute("SELECT COUNT(*) FROM messages")
            total_messages = cursor.fetchone()[0]
            
            # Messages by role
            cursor.execute("""
                SELECT role, COUNT(*) as count
                FROM messages
                GROUP BY role
            """)
            messages_by_role = dict(cursor.fetchall())
            
            # Recent activity
            cursor.execute("""
                SELECT DATE(timestamp) as date, COUNT(*) as count
                FROM messages
                WHERE timestamp >= datetime('now', '-7 days')
                GROUP BY DATE(timestamp)
                ORDER BY date DESC
            """)
            recent_activity = dict(cursor.fetchall())
            
            return {
                "total_conversations": total_conversations,
                "total_messages": total_messages,
                "messages_by_role": messages_by_role,
                "recent_activity": recent_activity,
                "current_conversation": {
                    "id": self.conversation_id,
                    "message_count": len(self.messages)
                }
            }
            
        except Exception as e:
            logger.error(f"Failed to get conversation statistics: {e}")
            return {}
            
    def __del__(self):
        """Clean up database connection."""
        if self._db_connection:
            self._db_connection.close()