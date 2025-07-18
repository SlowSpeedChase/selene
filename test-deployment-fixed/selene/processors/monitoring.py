"""
Real-time LLM processing monitoring system.
"""

import asyncio
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional, Callable, Set
from uuid import uuid4


class ProcessingStage(Enum):
    """Stages of LLM processing pipeline."""
    
    INITIALIZING = "initializing"
    VALIDATING_INPUT = "validating_input"
    RESOLVING_TEMPLATE = "resolving_template"
    GENERATING_PROMPT = "generating_prompt"
    SELECTING_MODEL = "selecting_model"
    CONNECTING_TO_MODEL = "connecting_to_model"
    SENDING_REQUEST = "sending_request"
    STREAMING_RESPONSE = "streaming_response"
    PROCESSING_RESPONSE = "processing_response"
    COLLECTING_METADATA = "collecting_metadata"
    FINALIZING_RESULT = "finalizing_result"
    COMPLETED = "completed"
    FAILED = "failed"


@dataclass
class ProcessingEvent:
    """Event emitted during processing."""
    
    session_id: str
    stage: ProcessingStage
    timestamp: float
    message: str
    progress: float  # 0.0 to 1.0
    metadata: Dict[str, Any] = field(default_factory=dict)
    error: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "session_id": self.session_id,
            "stage": self.stage.value,
            "timestamp": self.timestamp,
            "message": self.message,
            "progress": self.progress,
            "metadata": self.metadata,
            "error": self.error
        }


@dataclass
class StreamingToken:
    """Token received during streaming response."""
    
    token: str
    is_final: bool = False
    token_count: int = 0
    total_tokens: Optional[int] = None
    tokens_per_second: Optional[float] = None


@dataclass
class ProcessingSession:
    """Represents a single processing session."""
    
    session_id: str
    start_time: float
    current_stage: ProcessingStage
    progress: float
    content_preview: str
    task: str
    model: str
    processor_type: str
    events: List[ProcessingEvent] = field(default_factory=list)
    streaming_tokens: List[str] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)
    error: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "session_id": self.session_id,
            "start_time": self.start_time,
            "current_stage": self.current_stage.value,
            "progress": self.progress,
            "content_preview": self.content_preview,
            "task": self.task,
            "model": self.model,
            "processor_type": self.processor_type,
            "events": [event.to_dict() for event in self.events],
            "streaming_tokens": self.streaming_tokens,
            "metadata": self.metadata,
            "error": self.error,
            "elapsed_time": time.time() - self.start_time
        }


class ProcessingMonitor:
    """Real-time LLM processing monitor."""
    
    def __init__(self):
        self.sessions: Dict[str, ProcessingSession] = {}
        self.event_listeners: Set[Callable] = set()
        self.websocket_connections: Set[Any] = set()
        self._cleanup_task: Optional[asyncio.Task] = None
        self._start_cleanup_task()
    
    def _start_cleanup_task(self):
        """Start background task to clean up old sessions."""
        if self._cleanup_task:
            return
            
        async def cleanup_old_sessions():
            while True:
                await asyncio.sleep(300)  # Clean up every 5 minutes
                current_time = time.time()
                expired_sessions = [
                    session_id for session_id, session in self.sessions.items()
                    if current_time - session.start_time > 3600  # 1 hour
                ]
                for session_id in expired_sessions:
                    del self.sessions[session_id]
        
        # Only start cleanup task if event loop is running
        try:
            loop = asyncio.get_running_loop()
            self._cleanup_task = asyncio.create_task(cleanup_old_sessions())
        except RuntimeError:
            # No event loop running, cleanup task will be started later
            self._cleanup_task = None
    
    def start_session(self, content: str, task: str, model: str, processor_type: str) -> str:
        """Start a new processing session."""
        session_id = str(uuid4())
        
        # Create content preview (first 100 chars)
        content_preview = content[:100] + "..." if len(content) > 100 else content
        
        session = ProcessingSession(
            session_id=session_id,
            start_time=time.time(),
            current_stage=ProcessingStage.INITIALIZING,
            progress=0.0,
            content_preview=content_preview,
            task=task,
            model=model,
            processor_type=processor_type
        )
        
        self.sessions[session_id] = session
        
        # Emit initial event
        self.emit_event(session_id, ProcessingStage.INITIALIZING, "Starting processing session", 0.0)
        
        return session_id
    
    def emit_event(self, session_id: str, stage: ProcessingStage, message: str, 
                  progress: float, metadata: Optional[Dict[str, Any]] = None,
                  error: Optional[str] = None):
        """Emit a processing event."""
        if session_id not in self.sessions:
            return
        
        session = self.sessions[session_id]
        
        # Create event
        event = ProcessingEvent(
            session_id=session_id,
            stage=stage,
            timestamp=time.time(),
            message=message,
            progress=progress,
            metadata=metadata or {},
            error=error
        )
        
        # Update session
        session.current_stage = stage
        session.progress = progress
        session.events.append(event)
        
        if error:
            session.error = error
            session.current_stage = ProcessingStage.FAILED
        
        # Notify listeners
        self._notify_listeners(event)
        
        # Send to WebSocket connections
        asyncio.create_task(self._notify_websockets(event))
    
    def emit_streaming_token(self, session_id: str, token: StreamingToken):
        """Emit a streaming token event."""
        if session_id not in self.sessions:
            return
        
        session = self.sessions[session_id]
        session.streaming_tokens.append(token.token)
        
        # Create streaming event
        metadata = {
            "token": token.token,
            "is_final": token.is_final,
            "token_count": token.token_count,
            "total_tokens": token.total_tokens,
            "tokens_per_second": token.tokens_per_second,
            "cumulative_text": "".join(session.streaming_tokens)
        }
        
        # Calculate progress for streaming (between 60% and 90%)
        if token.total_tokens:
            stream_progress = min(token.token_count / token.total_tokens, 1.0)
            overall_progress = 0.6 + (stream_progress * 0.3)  # 60% to 90%
        else:
            overall_progress = session.progress
        
        event = ProcessingEvent(
            session_id=session_id,
            stage=ProcessingStage.STREAMING_RESPONSE,
            timestamp=time.time(),
            message=f"Streaming token {token.token_count}" + 
                   (f"/{token.total_tokens}" if token.total_tokens else ""),
            progress=overall_progress,
            metadata=metadata
        )
        
        session.progress = overall_progress
        session.events.append(event)
        
        # Notify listeners
        self._notify_listeners(event)
        
        # Send to WebSocket connections
        asyncio.create_task(self._notify_websockets(event))
    
    def finish_session(self, session_id: str, success: bool = True, 
                      final_result: Optional[str] = None):
        """Finish a processing session."""
        if session_id not in self.sessions:
            return
        
        session = self.sessions[session_id]
        
        if success:
            self.emit_event(session_id, ProcessingStage.COMPLETED, 
                          "Processing completed successfully", 1.0,
                          {"final_result": final_result})
        else:
            self.emit_event(session_id, ProcessingStage.FAILED,
                          "Processing failed", session.progress,
                          error=session.error)
        
        # Update session metadata
        session.metadata.update({
            "total_processing_time": time.time() - session.start_time,
            "total_events": len(session.events),
            "total_tokens": len(session.streaming_tokens),
            "final_result_length": len(final_result) if final_result else 0
        })
    
    def get_session(self, session_id: str) -> Optional[ProcessingSession]:
        """Get a processing session by ID."""
        return self.sessions.get(session_id)
    
    def get_active_sessions(self) -> List[ProcessingSession]:
        """Get all active processing sessions."""
        return [
            session for session in self.sessions.values()
            if session.current_stage not in [ProcessingStage.COMPLETED, ProcessingStage.FAILED]
        ]
    
    def get_recent_sessions(self, limit: int = 10) -> List[ProcessingSession]:
        """Get recent processing sessions."""
        sorted_sessions = sorted(
            self.sessions.values(),
            key=lambda s: s.start_time,
            reverse=True
        )
        return sorted_sessions[:limit]
    
    def add_event_listener(self, listener: Callable[[ProcessingEvent], None]):
        """Add an event listener."""
        self.event_listeners.add(listener)
    
    def remove_event_listener(self, listener: Callable[[ProcessingEvent], None]):
        """Remove an event listener."""
        self.event_listeners.discard(listener)
    
    def add_websocket_connection(self, websocket):
        """Add a WebSocket connection for real-time updates."""
        self.websocket_connections.add(websocket)
    
    def remove_websocket_connection(self, websocket):
        """Remove a WebSocket connection."""
        self.websocket_connections.discard(websocket)
    
    def _notify_listeners(self, event: ProcessingEvent):
        """Notify all event listeners."""
        for listener in self.event_listeners:
            try:
                listener(event)
            except Exception as e:
                # Log error but don't interrupt processing
                print(f"Error in event listener: {e}")
    
    async def _notify_websockets(self, event: ProcessingEvent):
        """Notify all WebSocket connections."""
        if not self.websocket_connections:
            return
        
        message = {
            "type": "processing_event",
            "data": event.to_dict()
        }
        
        # Send to all connected WebSocket clients
        disconnected = set()
        for websocket in self.websocket_connections:
            try:
                await websocket.send_json(message)
            except Exception:
                # Connection was closed, mark for removal
                disconnected.add(websocket)
        
        # Remove disconnected WebSocket connections
        for websocket in disconnected:
            self.websocket_connections.discard(websocket)
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get processing statistics."""
        total_sessions = len(self.sessions)
        completed_sessions = sum(1 for s in self.sessions.values() 
                               if s.current_stage == ProcessingStage.COMPLETED)
        failed_sessions = sum(1 for s in self.sessions.values() 
                            if s.current_stage == ProcessingStage.FAILED)
        active_sessions = len(self.get_active_sessions())
        
        # Average processing time for completed sessions
        completed = [s for s in self.sessions.values() 
                    if s.current_stage == ProcessingStage.COMPLETED]
        avg_processing_time = (
            sum(s.metadata.get("total_processing_time", 0) for s in completed) / len(completed)
            if completed else 0
        )
        
        return {
            "total_sessions": total_sessions,
            "completed_sessions": completed_sessions,
            "failed_sessions": failed_sessions,
            "active_sessions": active_sessions,
            "success_rate": completed_sessions / total_sessions if total_sessions > 0 else 0,
            "avg_processing_time": avg_processing_time,
            "connected_websockets": len(self.websocket_connections),
            "event_listeners": len(self.event_listeners)
        }


# Global monitor instance
_monitor = ProcessingMonitor()


def get_monitor() -> ProcessingMonitor:
    """Get the global processing monitor instance."""
    return _monitor


# Stage progression mapping for automatic progress calculation
STAGE_PROGRESS = {
    ProcessingStage.INITIALIZING: 0.0,
    ProcessingStage.VALIDATING_INPUT: 0.05,
    ProcessingStage.RESOLVING_TEMPLATE: 0.10,
    ProcessingStage.GENERATING_PROMPT: 0.15,
    ProcessingStage.SELECTING_MODEL: 0.20,
    ProcessingStage.CONNECTING_TO_MODEL: 0.25,
    ProcessingStage.SENDING_REQUEST: 0.30,
    ProcessingStage.STREAMING_RESPONSE: 0.60,  # Will be updated dynamically
    ProcessingStage.PROCESSING_RESPONSE: 0.90,
    ProcessingStage.COLLECTING_METADATA: 0.95,
    ProcessingStage.FINALIZING_RESULT: 0.98,
    ProcessingStage.COMPLETED: 1.0,
    ProcessingStage.FAILED: 0.0  # Progress stays at last valid stage
}


def auto_emit_stage(session_id: str, stage: ProcessingStage, message: str,
                   metadata: Optional[Dict[str, Any]] = None):
    """Automatically emit a stage event with calculated progress."""
    progress = STAGE_PROGRESS.get(stage, 0.0)
    get_monitor().emit_event(session_id, stage, message, progress, metadata)