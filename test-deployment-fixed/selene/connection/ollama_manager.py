"""
Ollama Connection Manager for SMS-32.

Provides centralized connection management, health monitoring, and configuration
for all Ollama interactions in the Selene system.
"""

import asyncio
import os
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from typing import Dict, Optional, Any, List
import httpx
import logging
from contextlib import asynccontextmanager

logger = logging.getLogger(__name__)


class ConnectionStatus(Enum):
    """Connection status enumeration."""
    HEALTHY = "healthy"
    UNHEALTHY = "unhealthy"
    UNKNOWN = "unknown"
    CONNECTING = "connecting"
    DISCONNECTED = "disconnected"


@dataclass
class OllamaConfig:
    """Configuration for Ollama connection management."""
    base_url: str = "http://localhost:11434"
    timeout: float = 120.0
    max_connections: int = 10
    health_check_interval: int = 30
    max_retries: int = 3
    retry_delay: float = 1.0
    connection_timeout: float = 10.0
    read_timeout: float = 60.0
    validate_on_init: bool = True
    
    @classmethod
    def from_env(cls) -> "OllamaConfig":
        """Create configuration from environment variables."""
        base_url = os.getenv("OLLAMA_HOST", "http://localhost:11434")
        if not base_url.startswith("http"):
            base_url = f"http://{base_url}"
        
        port = os.getenv("OLLAMA_PORT")
        if port and ":" not in base_url.split("//")[1]:
            base_url = f"{base_url}:{port}"
        
        return cls(
            base_url=base_url,
            timeout=float(os.getenv("OLLAMA_TIMEOUT", "120.0")),
            max_connections=int(os.getenv("OLLAMA_MAX_CONNECTIONS", "10")),
            health_check_interval=int(os.getenv("OLLAMA_HEALTH_CHECK_INTERVAL", "30")),
            max_retries=int(os.getenv("OLLAMA_MAX_RETRIES", "3")),
            retry_delay=float(os.getenv("OLLAMA_RETRY_DELAY", "1.0")),
            connection_timeout=float(os.getenv("OLLAMA_CONNECTION_TIMEOUT", "10.0")),
            read_timeout=float(os.getenv("OLLAMA_READ_TIMEOUT", "60.0")),
            validate_on_init=os.getenv("OLLAMA_VALIDATE_ON_INIT", "true").lower() == "true"
        )


@dataclass
class ConnectionInfo:
    """Information about a connection."""
    server_id: str
    base_url: str
    status: ConnectionStatus
    last_check: datetime
    client: Optional[httpx.AsyncClient] = None
    error_count: int = 0
    last_error: Optional[str] = None
    models: List[str] = field(default_factory=list)


class OllamaConnectionManager:
    """
    Centralized Ollama connection manager.
    
    Provides connection pooling, health monitoring, and configuration management
    for all Ollama interactions in the Selene system.
    """
    
    def __init__(self, config: Optional[OllamaConfig] = None):
        """Initialize the connection manager."""
        self.config = config or OllamaConfig.from_env()
        self.connections: Dict[str, ConnectionInfo] = {}
        self._health_monitor_task: Optional[asyncio.Task] = None
        self._shutdown_event = asyncio.Event()
        self._lock = asyncio.Lock()
        
    async def start(self):
        """Start the connection manager and health monitoring."""
        logger.info(f"Starting Ollama connection manager with base URL: {self.config.base_url}")
        
        # Initialize default connection
        await self._initialize_connection("default", self.config.base_url)
        
        # Start health monitoring
        if self.config.health_check_interval > 0:
            self._health_monitor_task = asyncio.create_task(self._health_monitor())
            
    async def stop(self):
        """Stop the connection manager and clean up resources."""
        logger.info("Stopping Ollama connection manager")
        
        # Signal shutdown
        self._shutdown_event.set()
        
        # Stop health monitoring
        if self._health_monitor_task:
            self._health_monitor_task.cancel()
            try:
                await self._health_monitor_task
            except asyncio.CancelledError:
                pass
        
        # Close all connections
        async with self._lock:
            for conn_info in self.connections.values():
                if conn_info.client:
                    await conn_info.client.aclose()
            self.connections.clear()
    
    async def get_client(self, server_id: str = "default") -> httpx.AsyncClient:
        """
        Get a connection client for the specified server.
        
        Args:
            server_id: Identifier for the server connection
            
        Returns:
            httpx.AsyncClient: The async HTTP client
            
        Raises:
            ConnectionError: If connection cannot be established
        """
        async with self._lock:
            conn_info = self.connections.get(server_id)
            
            if not conn_info:
                raise ConnectionError(f"No connection configured for server: {server_id}")
            
            if conn_info.client is None or conn_info.status == ConnectionStatus.DISCONNECTED:
                await self._create_client(conn_info)
            
            if conn_info.status == ConnectionStatus.UNHEALTHY:
                # Try to reconnect
                await self._check_connection_health(conn_info)
                
            if conn_info.status != ConnectionStatus.HEALTHY:
                raise ConnectionError(f"Connection to {server_id} is not healthy: {conn_info.last_error}")
                
            return conn_info.client
    
    @asynccontextmanager
    async def connection(self, server_id: str = "default"):
        """
        Context manager for getting a connection client.
        
        Args:
            server_id: Identifier for the server connection
            
        Yields:
            httpx.AsyncClient: The async HTTP client
        """
        client = await self.get_client(server_id)
        try:
            yield client
        except Exception as e:
            # Mark connection as potentially unhealthy
            await self._handle_connection_error(server_id, str(e))
            raise
    
    async def add_connection(self, server_id: str, base_url: str) -> bool:
        """
        Add a new connection to the manager.
        
        Args:
            server_id: Identifier for the server connection
            base_url: Base URL for the Ollama server
            
        Returns:
            bool: True if connection was successfully added
        """
        try:
            await self._initialize_connection(server_id, base_url)
            return True
        except Exception as e:
            logger.error(f"Failed to add connection {server_id}: {e}")
            return False
    
    async def remove_connection(self, server_id: str) -> bool:
        """
        Remove a connection from the manager.
        
        Args:
            server_id: Identifier for the server connection
            
        Returns:
            bool: True if connection was successfully removed
        """
        async with self._lock:
            conn_info = self.connections.get(server_id)
            if not conn_info:
                return False
            
            if conn_info.client:
                await conn_info.client.aclose()
            
            del self.connections[server_id]
            return True
    
    async def get_connection_status(self, server_id: str = "default") -> ConnectionStatus:
        """
        Get the current status of a connection.
        
        Args:
            server_id: Identifier for the server connection
            
        Returns:
            ConnectionStatus: Current connection status
        """
        conn_info = self.connections.get(server_id)
        if not conn_info:
            return ConnectionStatus.UNKNOWN
        return conn_info.status
    
    async def get_available_models(self, server_id: str = "default") -> List[str]:
        """
        Get list of available models for a connection.
        
        Args:
            server_id: Identifier for the server connection
            
        Returns:
            List[str]: List of available model names
        """
        conn_info = self.connections.get(server_id)
        if not conn_info:
            return []
        return conn_info.models.copy()
    
    async def health_check(self, server_id: str = "default") -> bool:
        """
        Perform a health check on a connection.
        
        Args:
            server_id: Identifier for the server connection
            
        Returns:
            bool: True if connection is healthy
        """
        conn_info = self.connections.get(server_id)
        if not conn_info:
            return False
        
        await self._check_connection_health(conn_info)
        return conn_info.status == ConnectionStatus.HEALTHY
    
    async def get_connection_info(self) -> Dict[str, Dict[str, Any]]:
        """
        Get information about all connections.
        
        Returns:
            Dict[str, Dict[str, Any]]: Connection information
        """
        async with self._lock:
            return {
                server_id: {
                    "base_url": conn_info.base_url,
                    "status": conn_info.status.value,
                    "last_check": conn_info.last_check.isoformat(),
                    "error_count": conn_info.error_count,
                    "last_error": conn_info.last_error,
                    "models": conn_info.models,
                }
                for server_id, conn_info in self.connections.items()
            }
    
    async def _initialize_connection(self, server_id: str, base_url: str):
        """Initialize a new connection."""
        conn_info = ConnectionInfo(
            server_id=server_id,
            base_url=base_url,
            status=ConnectionStatus.CONNECTING,
            last_check=datetime.now()
        )
        
        self.connections[server_id] = conn_info
        
        try:
            await self._create_client(conn_info)
            if self.config.validate_on_init:
                await self._check_connection_health(conn_info)
            else:
                # If validation is disabled, assume connection is healthy
                conn_info.status = ConnectionStatus.HEALTHY
                conn_info.last_check = datetime.now()
        except Exception as e:
            conn_info.status = ConnectionStatus.UNHEALTHY
            conn_info.last_error = str(e)
            logger.error(f"Failed to initialize connection {server_id}: {e}")
            raise
    
    async def _create_client(self, conn_info: ConnectionInfo):
        """Create HTTP client for a connection."""
        if conn_info.client:
            await conn_info.client.aclose()
        
        timeout = httpx.Timeout(
            connect=self.config.connection_timeout,
            read=self.config.read_timeout,
            write=self.config.timeout,
            pool=self.config.timeout
        )
        
        conn_info.client = httpx.AsyncClient(
            base_url=conn_info.base_url,
            timeout=timeout,
            limits=httpx.Limits(max_connections=self.config.max_connections)
        )
        
        conn_info.status = ConnectionStatus.CONNECTING
    
    async def _check_connection_health(self, conn_info: ConnectionInfo):
        """Check the health of a connection."""
        if not conn_info.client:
            await self._create_client(conn_info)
        
        try:
            # Check if Ollama is responding
            response = await conn_info.client.get("/api/tags")
            
            if response.status_code == 200:
                conn_info.status = ConnectionStatus.HEALTHY
                conn_info.last_check = datetime.now()
                conn_info.error_count = 0
                conn_info.last_error = None
                
                # Update available models
                try:
                    data = response.json()
                    conn_info.models = [model["name"] for model in data.get("models", [])]
                except Exception:
                    conn_info.models = []
                
                logger.debug(f"Connection {conn_info.server_id} is healthy")
            else:
                raise httpx.HTTPStatusError(
                    f"HTTP {response.status_code}",
                    request=response.request,
                    response=response
                )
                
        except Exception as e:
            conn_info.status = ConnectionStatus.UNHEALTHY
            conn_info.error_count += 1
            conn_info.last_error = str(e)
            conn_info.last_check = datetime.now()
            logger.warning(f"Connection {conn_info.server_id} health check failed: {e}")
    
    async def _handle_connection_error(self, server_id: str, error: str):
        """Handle connection error by updating status."""
        conn_info = self.connections.get(server_id)
        if conn_info:
            conn_info.error_count += 1
            conn_info.last_error = error
            if conn_info.error_count >= self.config.max_retries:
                conn_info.status = ConnectionStatus.UNHEALTHY
    
    async def _health_monitor(self):
        """Background task for monitoring connection health."""
        logger.info("Starting health monitor")
        
        while not self._shutdown_event.is_set():
            try:
                await asyncio.sleep(self.config.health_check_interval)
                
                if self._shutdown_event.is_set():
                    break
                
                # Check all connections
                async with self._lock:
                    for conn_info in self.connections.values():
                        if conn_info.status != ConnectionStatus.DISCONNECTED:
                            await self._check_connection_health(conn_info)
                            
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Health monitor error: {e}")
        
        logger.info("Health monitor stopped")


# Global connection manager instance
_global_manager: Optional[OllamaConnectionManager] = None


async def get_global_manager() -> OllamaConnectionManager:
    """Get the global connection manager instance."""
    global _global_manager
    if _global_manager is None:
        _global_manager = OllamaConnectionManager()
        await _global_manager.start()
    return _global_manager


async def shutdown_global_manager():
    """Shutdown the global connection manager."""
    global _global_manager
    if _global_manager:
        await _global_manager.stop()
        _global_manager = None