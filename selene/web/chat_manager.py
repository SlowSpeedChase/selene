"""
Web Chat Session Manager for SELENE.

Manages chat sessions for the web interface, integrating with the existing
ChatAgent architecture while providing web-specific functionality.
"""

import asyncio
import uuid
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field

from loguru import logger
from fastapi import WebSocket

from ..chat.agent import ChatAgent
from ..chat.enhanced_agent import EnhancedChatAgent
from ..chat.config import ChatConfig
from .models import (
    ChatSessionResponse,
    ChatMessageResponse,
    ChatHistoryResponse,
    ChatSessionListResponse,
)


@dataclass
class WebChatSession:
    """Web chat session container."""
    
    session_id: str
    agent: ChatAgent  # Can be ChatAgent or EnhancedChatAgent
    vault_path: Optional[str]
    session_name: Optional[str]
    created_at: datetime
    enable_memory: bool
    debug_mode: bool
    user_id: Optional[str] = None  # For enhanced agent personalization
    is_enhanced: bool = False  # Track if using enhanced agent
    websockets: List[WebSocket] = field(default_factory=list)
    last_activity: datetime = field(default_factory=datetime.now)
    
    def to_response(self) -> ChatSessionResponse:
        """Convert to response model."""
        return ChatSessionResponse(
            session_id=self.session_id,
            vault_path=self.vault_path,
            session_name=self.session_name,
            created_at=self.created_at.isoformat(),
            enable_memory=self.enable_memory,
            debug_mode=self.debug_mode,
            vault_detected=bool(self.vault_path and Path(self.vault_path).exists()),
            available_tools=list(self.agent.tool_registry.get_enabled_tools().keys())
        )


class WebChatManager:
    """
    Manager for web chat sessions.
    
    Handles session lifecycle, WebSocket connections, and integration
    with the existing ChatAgent system.
    """
    
    def __init__(self):
        """Initialize the web chat manager."""
        self.sessions: Dict[str, WebChatSession] = {}
        self.session_lock = asyncio.Lock()
        logger.info("WebChatManager initialized")
    
    async def create_session(
        self,
        vault_path: Optional[str] = None,
        session_name: Optional[str] = None,
        enable_memory: bool = True,
        debug_mode: bool = False,
        use_enhanced_agent: bool = True
    ) -> ChatSessionResponse:
        """
        Create a new chat session.
        
        Args:
            vault_path: Path to Obsidian vault
            session_name: Human-readable session name
            enable_memory: Enable conversation memory
            debug_mode: Enable debug logging
            use_enhanced_agent: Use enhanced agent with advanced features
            
        Returns:
            ChatSessionResponse with session details
        """
        async with self.session_lock:
            session_id = str(uuid.uuid4())
            
            try:
                # Create chat configuration
                config = ChatConfig()
                if vault_path:
                    config.vault_path = vault_path
                config.enable_memory = enable_memory
                config.debug_mode = debug_mode
                
                # Initialize ChatAgent (enhanced or standard)
                if use_enhanced_agent:
                    agent = EnhancedChatAgent(config)
                    user_id = f"web_user_{session_id[:8]}"  # Generate user ID for personalization
                else:
                    agent = ChatAgent(config)
                    user_id = None
                    
                # Note: We'll initialize the agent lazily when first message is sent
                # to avoid blocking the session creation on Ollama availability
                
                # Create session
                session = WebChatSession(
                    session_id=session_id,
                    agent=agent,
                    vault_path=vault_path,
                    session_name=session_name or f"Session {len(self.sessions) + 1}",
                    created_at=datetime.now(),
                    enable_memory=enable_memory,
                    debug_mode=debug_mode,
                    user_id=user_id,
                    is_enhanced=use_enhanced_agent
                )
                
                self.sessions[session_id] = session
                
                logger.info(f"Created chat session {session_id} with vault: {vault_path}")
                return session.to_response()
                
            except Exception as e:
                logger.error(f"Failed to create chat session: {e}")
                raise
    
    async def get_session(self, session_id: str) -> Optional[WebChatSession]:
        """Get a chat session by ID."""
        async with self.session_lock:
            session = self.sessions.get(session_id)
            if session:
                session.last_activity = datetime.now()
            return session
    
    async def delete_session(self, session_id: str) -> bool:
        """Delete a chat session."""
        async with self.session_lock:
            session = self.sessions.pop(session_id, None)
            if session:
                # Close all WebSocket connections
                for ws in session.websockets:
                    try:
                        await ws.close()
                    except Exception as e:
                        logger.warning(f"Error closing WebSocket: {e}")
                
                logger.info(f"Deleted chat session {session_id}")
                return True
            return False
    
    async def list_sessions(self) -> ChatSessionListResponse:
        """List all active chat sessions."""
        async with self.session_lock:
            sessions = [session.to_response() for session in self.sessions.values()]
            return ChatSessionListResponse(
                sessions=sessions,
                total_sessions=len(sessions)
            )
    
    async def add_websocket(self, session_id: str, websocket: WebSocket) -> bool:
        """Add a WebSocket connection to a session."""
        session = await self.get_session(session_id)
        if session:
            session.websockets.append(websocket)
            logger.info(f"Added WebSocket to session {session_id}")
            return True
        return False
    
    async def remove_websocket(self, session_id: str, websocket: WebSocket) -> bool:
        """Remove a WebSocket connection from a session."""
        session = await self.get_session(session_id)
        if session and websocket in session.websockets:
            session.websockets.remove(websocket)
            logger.info(f"Removed WebSocket from session {session_id}")
            return True
        return False
    
    async def send_message(
        self,
        session_id: str,
        message: str,
        message_type: str = "user"
    ) -> Optional[ChatMessageResponse]:
        """
        Send a message to a chat session and get response.
        
        Args:
            session_id: Session ID
            message: Message content
            message_type: Type of message ('user', 'system')
            
        Returns:
            ChatMessageResponse or None if session not found
        """
        session = await self.get_session(session_id)
        if not session:
            return None
        
        try:
            message_id = str(uuid.uuid4())
            timestamp = datetime.now()
            
            # Process message with ChatAgent
            start_time = datetime.now()
            
            if message_type == "user":
                # Initialize agent if not already done
                if not session.agent._initialized:
                    if session.is_enhanced:
                        logger.info("Initializing Enhanced ChatAgent for first message...")
                        success = await session.agent.initialize(user_id=session.user_id)
                    else:
                        logger.info("Initializing ChatAgent for first message...")
                        success = await session.agent.initialize()
                    
                    if not success:
                        raise Exception("Failed to initialize ChatAgent. Please ensure Ollama is running.")
                
                # Process user message through the agent
                content = await session.agent.chat(message)
                metadata = {"processed": True}
            else:
                # System message
                content = message
                metadata = {}
            
            processing_time = (datetime.now() - start_time).total_seconds()
            
            # Create response
            chat_response = ChatMessageResponse(
                message_id=message_id,
                content=content,
                timestamp=timestamp.isoformat(),
                message_type="assistant" if message_type == "user" else message_type,
                metadata=metadata,
                processing_time=processing_time
            )
            
            # Broadcast to all connected WebSockets
            await self._broadcast_to_session(session_id, {
                "type": "message",
                "data": chat_response.dict()
            })
            
            return chat_response
            
        except Exception as e:
            logger.error(f"Error processing message in session {session_id}: {e}")
            error_response = ChatMessageResponse(
                message_id=str(uuid.uuid4()),
                content=f"Error processing message: {str(e)}",
                timestamp=datetime.now().isoformat(),
                message_type="error",
                metadata={"error": str(e)}
            )
            
            await self._broadcast_to_session(session_id, {
                "type": "error",
                "data": error_response.dict()
            })
            
            return error_response
    
    async def get_conversation_history(self, session_id: str) -> Optional[ChatHistoryResponse]:
        """Get conversation history for a session."""
        session = await self.get_session(session_id)
        if not session:
            return None
        
        try:
            # Get history from the agent's conversation state
            history = session.agent.conversation_state.get_recent_messages(limit=100)
            
            messages = []
            for msg in history:
                messages.append(ChatMessageResponse(
                    message_id=str(msg.get("id", uuid.uuid4())),
                    content=msg.get("content", ""),
                    timestamp=msg.get("timestamp", datetime.now().isoformat()),
                    message_type=msg.get("type", "unknown"),
                    metadata=msg.get("metadata", {})
                ))
            
            return ChatHistoryResponse(
                session_id=session_id,
                messages=messages,
                total_messages=len(messages),
                session_created_at=session.created_at.isoformat()
            )
            
        except Exception as e:
            logger.error(f"Error getting conversation history for session {session_id}: {e}")
            return None
    
    async def _broadcast_to_session(self, session_id: str, message: Dict[str, Any]):
        """Broadcast a message to all WebSockets in a session."""
        session = await self.get_session(session_id)
        if not session:
            return
        
        # Remove closed connections
        active_websockets = []
        for ws in session.websockets:
            try:
                await ws.send_json(message)
                active_websockets.append(ws)
            except Exception as e:
                logger.warning(f"WebSocket error, removing: {e}")
        
        session.websockets = active_websockets
    
    async def cleanup_inactive_sessions(self, max_age_hours: int = 24):
        """Clean up inactive sessions older than max_age_hours."""
        async with self.session_lock:
            now = datetime.now()
            to_remove = []
            
            for session_id, session in self.sessions.items():
                age_hours = (now - session.last_activity).total_seconds() / 3600
                if age_hours > max_age_hours:
                    to_remove.append(session_id)
            
            for session_id in to_remove:
                await self.delete_session(session_id)
                logger.info(f"Cleaned up inactive session {session_id}")