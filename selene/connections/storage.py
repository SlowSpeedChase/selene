"""
Connection Storage

Handles database operations for storing and retrieving connections between notes.
Uses SQLite for persistent storage with efficient querying capabilities.
"""

import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
from contextlib import contextmanager
import json

from .models import Connection, ConnectionType, ConnectionFilter, NoteConnectionSummary
from loguru import logger


class ConnectionStorage:
    """Manages persistent storage of note connections."""
    
    def __init__(self, db_path: str = "connections.db"):
        """Initialize connection storage.
        
        Args:
            db_path: Path to SQLite database file
        """
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_database()
    
    def _init_database(self) -> None:
        """Initialize database tables."""
        with self._get_connection() as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS connections (
                    id TEXT PRIMARY KEY,
                    source_id TEXT NOT NULL,
                    target_id TEXT NOT NULL,
                    connection_type TEXT NOT NULL,
                    confidence REAL NOT NULL,
                    explanation TEXT NOT NULL,
                    metadata TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
            """)
            
            # Create indexes for efficient querying
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_connections_source_id 
                ON connections(source_id)
            """)
            
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_connections_target_id 
                ON connections(target_id)
            """)
            
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_connections_type 
                ON connections(connection_type)
            """)
            
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_connections_confidence 
                ON connections(confidence)
            """)
            
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_connections_created_at 
                ON connections(created_at)
            """)
            
            conn.commit()
    
    @contextmanager
    def _get_connection(self):
        """Get database connection with proper cleanup."""
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        try:
            yield conn
        finally:
            conn.close()
    
    def store_connection(self, connection: Connection) -> bool:
        """Store a connection in the database.
        
        Args:
            connection: Connection to store
            
        Returns:
            True if stored successfully, False otherwise
        """
        try:
            with self._get_connection() as conn:
                conn.execute("""
                    INSERT OR REPLACE INTO connections 
                    (id, source_id, target_id, connection_type, confidence, 
                     explanation, metadata, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    connection.id,
                    connection.source_id,
                    connection.target_id,
                    connection.connection_type.value,
                    connection.confidence,
                    connection.explanation,
                    json.dumps(connection.metadata),
                    connection.created_at.isoformat(),
                    connection.updated_at.isoformat(),
                ))
                conn.commit()
                return True
        except Exception as e:
            logger.error(f"Failed to store connection {connection.id}: {e}")
            return False
    
    def store_connections(self, connections: List[Connection]) -> int:
        """Store multiple connections in batch.
        
        Args:
            connections: List of connections to store
            
        Returns:
            Number of connections stored successfully
        """
        stored_count = 0
        with self._get_connection() as conn:
            for connection in connections:
                try:
                    conn.execute("""
                        INSERT OR REPLACE INTO connections 
                        (id, source_id, target_id, connection_type, confidence, 
                         explanation, metadata, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (
                        connection.id,
                        connection.source_id,
                        connection.target_id,
                        connection.connection_type.value,
                        connection.confidence,
                        connection.explanation,
                        json.dumps(connection.metadata),
                        connection.created_at.isoformat(),
                        connection.updated_at.isoformat(),
                    ))
                    stored_count += 1
                except Exception as e:
                    logger.error(f"Failed to store connection {connection.id}: {e}")
            
            conn.commit()
        
        return stored_count
    
    def get_connection(self, connection_id: str) -> Optional[Connection]:
        """Get a connection by ID.
        
        Args:
            connection_id: Connection ID
            
        Returns:
            Connection if found, None otherwise
        """
        with self._get_connection() as conn:
            cursor = conn.execute("""
                SELECT * FROM connections WHERE id = ?
            """, (connection_id,))
            
            row = cursor.fetchone()
            if row:
                return self._row_to_connection(row)
        
        return None
    
    def get_connections(self, filter_criteria: Optional[ConnectionFilter] = None) -> List[Connection]:
        """Get connections matching filter criteria.
        
        Args:
            filter_criteria: Optional filter criteria
            
        Returns:
            List of matching connections
        """
        query = "SELECT * FROM connections"
        params = []
        conditions = []
        
        if filter_criteria:
            if filter_criteria.connection_types:
                type_placeholders = ",".join("?" * len(filter_criteria.connection_types))
                conditions.append(f"connection_type IN ({type_placeholders})")
                params.extend([t.value for t in filter_criteria.connection_types])
            
            if filter_criteria.min_confidence is not None:
                conditions.append("confidence >= ?")
                params.append(filter_criteria.min_confidence)
            
            if filter_criteria.max_confidence is not None:
                conditions.append("confidence <= ?")
                params.append(filter_criteria.max_confidence)
            
            if filter_criteria.source_ids:
                source_placeholders = ",".join("?" * len(filter_criteria.source_ids))
                conditions.append(f"source_id IN ({source_placeholders})")
                params.extend(filter_criteria.source_ids)
            
            if filter_criteria.target_ids:
                target_placeholders = ",".join("?" * len(filter_criteria.target_ids))
                conditions.append(f"target_id IN ({target_placeholders})")
                params.extend(filter_criteria.target_ids)
            
            if filter_criteria.created_after:
                conditions.append("created_at >= ?")
                params.append(filter_criteria.created_after.isoformat())
            
            if filter_criteria.created_before:
                conditions.append("created_at <= ?")
                params.append(filter_criteria.created_before.isoformat())
        
        if conditions:
            query += " WHERE " + " AND ".join(conditions)
        
        query += " ORDER BY confidence DESC"
        
        if filter_criteria and filter_criteria.limit:
            query += " LIMIT ?"
            params.append(filter_criteria.limit)
        
        connections = []
        with self._get_connection() as conn:
            cursor = conn.execute(query, params)
            for row in cursor.fetchall():
                connections.append(self._row_to_connection(row))
        
        return connections
    
    def get_connections_for_note(self, note_id: str) -> List[Connection]:
        """Get all connections for a specific note (both incoming and outgoing).
        
        Args:
            note_id: Note ID
            
        Returns:
            List of connections involving the note
        """
        with self._get_connection() as conn:
            cursor = conn.execute("""
                SELECT * FROM connections 
                WHERE source_id = ? OR target_id = ?
                ORDER BY confidence DESC
            """, (note_id, note_id))
            
            connections = []
            for row in cursor.fetchall():
                connections.append(self._row_to_connection(row))
        
        return connections
    
    def get_note_connection_summary(self, note_id: str) -> NoteConnectionSummary:
        """Get connection summary for a specific note.
        
        Args:
            note_id: Note ID
            
        Returns:
            Connection summary for the note
        """
        connections = self.get_connections_for_note(note_id)
        
        summary = NoteConnectionSummary(note_id=note_id)
        summary.total_connections = len(connections)
        
        incoming = [c for c in connections if c.target_id == note_id]
        outgoing = [c for c in connections if c.source_id == note_id]
        
        summary.incoming_connections = len(incoming)
        summary.outgoing_connections = len(outgoing)
        
        # Connection types distribution
        type_counts = {}
        total_confidence = 0
        for connection in connections:
            conn_type = connection.connection_type.value
            type_counts[conn_type] = type_counts.get(conn_type, 0) + 1
            total_confidence += connection.confidence
        
        summary.connection_types = type_counts
        summary.average_confidence = total_confidence / len(connections) if connections else 0.0
        
        # Most and least confident connections
        sorted_connections = sorted(connections, key=lambda c: c.confidence, reverse=True)
        summary.most_confident_connections = sorted_connections[:5]
        summary.least_confident_connections = sorted_connections[-5:]
        
        return summary
    
    def delete_connection(self, connection_id: str) -> bool:
        """Delete a connection by ID.
        
        Args:
            connection_id: Connection ID
            
        Returns:
            True if deleted successfully, False otherwise
        """
        try:
            with self._get_connection() as conn:
                cursor = conn.execute("""
                    DELETE FROM connections WHERE id = ?
                """, (connection_id,))
                conn.commit()
                return cursor.rowcount > 0
        except Exception as e:
            logger.error(f"Failed to delete connection {connection_id}: {e}")
            return False
    
    def delete_connections_for_note(self, note_id: str) -> int:
        """Delete all connections for a specific note.
        
        Args:
            note_id: Note ID
            
        Returns:
            Number of connections deleted
        """
        try:
            with self._get_connection() as conn:
                cursor = conn.execute("""
                    DELETE FROM connections WHERE source_id = ? OR target_id = ?
                """, (note_id, note_id))
                conn.commit()
                return cursor.rowcount
        except Exception as e:
            logger.error(f"Failed to delete connections for note {note_id}: {e}")
            return 0
    
    def get_connection_statistics(self) -> Dict[str, Any]:
        """Get overall connection statistics.
        
        Returns:
            Dictionary with connection statistics
        """
        stats = {
            "total_connections": 0,
            "connections_by_type": {},
            "average_confidence": 0.0,
            "confidence_distribution": {},
            "most_connected_notes": [],
        }
        
        with self._get_connection() as conn:
            # Total connections
            cursor = conn.execute("SELECT COUNT(*) FROM connections")
            stats["total_connections"] = cursor.fetchone()[0]
            
            # Connections by type
            cursor = conn.execute("""
                SELECT connection_type, COUNT(*) 
                FROM connections 
                GROUP BY connection_type
            """)
            for row in cursor.fetchall():
                stats["connections_by_type"][row[0]] = row[1]
            
            # Average confidence
            cursor = conn.execute("SELECT AVG(confidence) FROM connections")
            avg_confidence = cursor.fetchone()[0]
            stats["average_confidence"] = avg_confidence if avg_confidence else 0.0
            
            # Confidence distribution
            cursor = conn.execute("""
                SELECT 
                    CASE 
                        WHEN confidence < 0.2 THEN '0.0-0.2'
                        WHEN confidence < 0.4 THEN '0.2-0.4'
                        WHEN confidence < 0.6 THEN '0.4-0.6'
                        WHEN confidence < 0.8 THEN '0.6-0.8'
                        ELSE '0.8-1.0'
                    END as confidence_range,
                    COUNT(*) as count
                FROM connections
                GROUP BY confidence_range
            """)
            for row in cursor.fetchall():
                stats["confidence_distribution"][row[0]] = row[1]
            
            # Most connected notes
            cursor = conn.execute("""
                SELECT note_id, connection_count FROM (
                    SELECT source_id as note_id, COUNT(*) as connection_count
                    FROM connections
                    GROUP BY source_id
                    UNION ALL
                    SELECT target_id as note_id, COUNT(*) as connection_count
                    FROM connections
                    GROUP BY target_id
                ) 
                GROUP BY note_id
                ORDER BY SUM(connection_count) DESC
                LIMIT 10
            """)
            for row in cursor.fetchall():
                stats["most_connected_notes"].append({
                    "note_id": row[0],
                    "connection_count": row[1]
                })
        
        return stats
    
    def _row_to_connection(self, row: sqlite3.Row) -> Connection:
        """Convert database row to Connection object.
        
        Args:
            row: Database row
            
        Returns:
            Connection object
        """
        return Connection(
            id=row["id"],
            source_id=row["source_id"],
            target_id=row["target_id"],
            connection_type=ConnectionType(row["connection_type"]),
            confidence=row["confidence"],
            explanation=row["explanation"],
            metadata=json.loads(row["metadata"]) if row["metadata"] else {},
            created_at=datetime.fromisoformat(row["created_at"]),
            updated_at=datetime.fromisoformat(row["updated_at"]),
        )