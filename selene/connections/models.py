"""
Connection Data Models

Defines the data structures for representing connections between notes,
including connection types, confidence scores, and metadata.
"""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional, Any
import uuid


class ConnectionType(Enum):
    """Types of connections between notes."""
    
    SEMANTIC = "semantic"          # Based on meaning/content similarity
    TEMPORAL = "temporal"          # Based on time-based patterns
    TOPICAL = "topical"           # Based on shared topics/themes
    REFERENCE = "reference"        # Based on explicit references/links
    CONCEPTUAL = "conceptual"     # Based on abstract concept similarity
    CAUSAL = "causal"             # Based on cause-and-effect relationships
    HIERARCHICAL = "hierarchical"  # Based on parent-child relationships


@dataclass
class Connection:
    """Represents a discovered connection between two notes."""
    
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    source_id: str = ""
    target_id: str = ""
    connection_type: ConnectionType = ConnectionType.SEMANTIC
    confidence: float = 0.0  # 0.0 to 1.0
    explanation: str = ""
    metadata: Dict[str, Any] = field(default_factory=dict)
    created_at: datetime = field(default_factory=datetime.now)
    updated_at: datetime = field(default_factory=datetime.now)
    
    def __post_init__(self):
        """Validate connection data after initialization."""
        if not (0.0 <= self.confidence <= 1.0):
            raise ValueError("Confidence must be between 0.0 and 1.0")
        if not self.source_id or not self.target_id:
            raise ValueError("Source and target IDs are required")
        if self.source_id == self.target_id:
            raise ValueError("Source and target cannot be the same")
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert connection to dictionary for serialization."""
        return {
            "id": self.id,
            "source_id": self.source_id,
            "target_id": self.target_id,
            "connection_type": self.connection_type.value,
            "confidence": self.confidence,
            "explanation": self.explanation,
            "metadata": self.metadata,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Connection":
        """Create connection from dictionary."""
        return cls(
            id=data["id"],
            source_id=data["source_id"],
            target_id=data["target_id"],
            connection_type=ConnectionType(data["connection_type"]),
            confidence=data["confidence"],
            explanation=data["explanation"],
            metadata=data.get("metadata", {}),
            created_at=datetime.fromisoformat(data["created_at"]),
            updated_at=datetime.fromisoformat(data["updated_at"]),
        )


@dataclass
class ConnectionStatistics:
    """Statistics about discovered connections."""
    
    total_connections: int = 0
    connections_by_type: Dict[str, int] = field(default_factory=dict)
    average_confidence: float = 0.0
    confidence_distribution: Dict[str, int] = field(default_factory=dict)
    most_connected_notes: List[Dict[str, Any]] = field(default_factory=list)
    connection_patterns: Dict[str, Any] = field(default_factory=dict)
    last_updated: datetime = field(default_factory=datetime.now)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert statistics to dictionary for serialization."""
        return {
            "total_connections": self.total_connections,
            "connections_by_type": self.connections_by_type,
            "average_confidence": self.average_confidence,
            "confidence_distribution": self.confidence_distribution,
            "most_connected_notes": self.most_connected_notes,
            "connection_patterns": self.connection_patterns,
            "last_updated": self.last_updated.isoformat(),
        }


@dataclass
class ConnectionFilter:
    """Filter criteria for connection queries."""
    
    connection_types: Optional[List[ConnectionType]] = None
    min_confidence: Optional[float] = None
    max_confidence: Optional[float] = None
    source_ids: Optional[List[str]] = None
    target_ids: Optional[List[str]] = None
    created_after: Optional[datetime] = None
    created_before: Optional[datetime] = None
    limit: Optional[int] = None
    
    def matches(self, connection: Connection) -> bool:
        """Check if connection matches filter criteria."""
        if self.connection_types and connection.connection_type not in self.connection_types:
            return False
        if self.min_confidence is not None and connection.confidence < self.min_confidence:
            return False
        if self.max_confidence is not None and connection.confidence > self.max_confidence:
            return False
        if self.source_ids and connection.source_id not in self.source_ids:
            return False
        if self.target_ids and connection.target_id not in self.target_ids:
            return False
        if self.created_after and connection.created_at < self.created_after:
            return False
        if self.created_before and connection.created_at > self.created_before:
            return False
        
        return True


@dataclass
class NoteConnectionSummary:
    """Summary of connections for a specific note."""
    
    note_id: str
    total_connections: int = 0
    incoming_connections: int = 0
    outgoing_connections: int = 0
    connection_types: Dict[str, int] = field(default_factory=dict)
    average_confidence: float = 0.0
    most_confident_connections: List[Connection] = field(default_factory=list)
    least_confident_connections: List[Connection] = field(default_factory=list)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert summary to dictionary."""
        return {
            "note_id": self.note_id,
            "total_connections": self.total_connections,
            "incoming_connections": self.incoming_connections,
            "outgoing_connections": self.outgoing_connections,
            "connection_types": self.connection_types,
            "average_confidence": self.average_confidence,
            "most_confident_connections": [c.to_dict() for c in self.most_confident_connections],
            "least_confident_connections": [c.to_dict() for c in self.least_confident_connections],
        }