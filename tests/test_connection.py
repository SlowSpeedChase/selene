"""
Tests for the Ollama connection manager (SMS-32).
"""

import pytest
import asyncio
from unittest.mock import Mock, patch, AsyncMock
from datetime import datetime
import httpx

from selene.connection.ollama_manager import (
    OllamaConnectionManager,
    OllamaConfig,
    ConnectionStatus,
    ConnectionInfo,
    get_global_manager,
    shutdown_global_manager
)


class TestOllamaConfig:
    """Test OllamaConfig class."""
    
    def test_default_config(self):
        """Test default configuration values."""
        config = OllamaConfig()
        assert config.base_url == "http://localhost:11434"
        assert config.timeout == 120.0
        assert config.max_connections == 10
        assert config.health_check_interval == 30
        assert config.max_retries == 3
        assert config.retry_delay == 1.0
        assert config.connection_timeout == 10.0
        assert config.read_timeout == 60.0
        assert config.validate_on_init is True
    
    def test_from_env_default(self):
        """Test configuration from environment with defaults."""
        with patch.dict('os.environ', {}, clear=True):
            config = OllamaConfig.from_env()
            assert config.base_url == "http://localhost:11434"
            assert config.timeout == 120.0
    
    def test_from_env_custom(self):
        """Test configuration from environment with custom values."""
        env_vars = {
            'OLLAMA_HOST': 'http://custom-host:8080',
            'OLLAMA_TIMEOUT': '60.0',
            'OLLAMA_MAX_CONNECTIONS': '20',
            'OLLAMA_HEALTH_CHECK_INTERVAL': '60',
            'OLLAMA_MAX_RETRIES': '5',
            'OLLAMA_RETRY_DELAY': '2.0',
            'OLLAMA_CONNECTION_TIMEOUT': '15.0',
            'OLLAMA_READ_TIMEOUT': '90.0',
            'OLLAMA_VALIDATE_ON_INIT': 'false'
        }
        
        with patch.dict('os.environ', env_vars):
            config = OllamaConfig.from_env()
            assert config.base_url == "http://custom-host:8080"
            assert config.timeout == 60.0
            assert config.max_connections == 20
            assert config.health_check_interval == 60
            assert config.max_retries == 5
            assert config.retry_delay == 2.0
            assert config.connection_timeout == 15.0
            assert config.read_timeout == 90.0
            assert config.validate_on_init is False
    
    def test_from_env_host_without_http(self):
        """Test environment host without http prefix."""
        with patch.dict('os.environ', {'OLLAMA_HOST': 'localhost:8080'}):
            config = OllamaConfig.from_env()
            assert config.base_url == "http://localhost:8080"
    
    def test_from_env_with_port(self):
        """Test environment with separate port."""
        with patch.dict('os.environ', {
            'OLLAMA_HOST': 'http://localhost',
            'OLLAMA_PORT': '8080'
        }):
            config = OllamaConfig.from_env()
            assert config.base_url == "http://localhost:8080"


class TestOllamaConnectionManager:
    """Test OllamaConnectionManager class."""
    
    @pytest.fixture
    def config(self):
        """Create test configuration."""
        return OllamaConfig(
            base_url="http://localhost:11434",
            timeout=30.0,
            health_check_interval=0,  # Disable health monitoring for tests
            validate_on_init=False
        )
    
    @pytest.fixture
    def manager(self, config):
        """Create connection manager instance."""
        return OllamaConnectionManager(config)
    
    @pytest.mark.asyncio
    async def test_initialization(self, manager):
        """Test manager initialization."""
        assert manager.config.base_url == "http://localhost:11434"
        assert len(manager.connections) == 0
        assert manager._health_monitor_task is None
    
    @pytest.mark.asyncio
    async def test_start_stop(self, manager):
        """Test manager start and stop."""
        with patch('httpx.AsyncClient') as mock_client:
            mock_client.return_value = AsyncMock()
            
            await manager.start()
            assert "default" in manager.connections
            assert manager.connections["default"].base_url == "http://localhost:11434"
            
            await manager.stop()
            assert len(manager.connections) == 0
    
    @pytest.mark.asyncio
    async def test_get_client_success(self, manager):
        """Test successful client retrieval."""
        mock_client = AsyncMock()
        
        with patch('httpx.AsyncClient', return_value=mock_client):
            await manager.start()
            
            client = await manager.get_client("default")
            assert client == mock_client
            
            await manager.stop()
    
    @pytest.mark.asyncio
    async def test_get_client_unknown_server(self, manager):
        """Test client retrieval for unknown server."""
        await manager.start()
        
        with pytest.raises(ConnectionError, match="No connection configured"):
            await manager.get_client("unknown")
        
        await manager.stop()
    
    @pytest.mark.asyncio
    async def test_add_connection(self, manager):
        """Test adding a new connection."""
        with patch('httpx.AsyncClient') as mock_client:
            mock_client.return_value = AsyncMock()
            
            await manager.start()
            
            success = await manager.add_connection("test", "http://test:8080")
            assert success is True
            assert "test" in manager.connections
            assert manager.connections["test"].base_url == "http://test:8080"
            
            await manager.stop()
    
    @pytest.mark.asyncio
    async def test_remove_connection(self, manager):
        """Test removing a connection."""
        with patch('httpx.AsyncClient') as mock_client:
            mock_client.return_value = AsyncMock()
            
            await manager.start()
            await manager.add_connection("test", "http://test:8080")
            
            success = await manager.remove_connection("test")
            assert success is True
            assert "test" not in manager.connections
            
            # Try to remove non-existent connection
            success = await manager.remove_connection("nonexistent")
            assert success is False
            
            await manager.stop()
    
    @pytest.mark.asyncio
    async def test_connection_status(self, manager):
        """Test getting connection status."""
        with patch('httpx.AsyncClient') as mock_client:
            mock_client.return_value = AsyncMock()
            
            await manager.start()
            
            status = await manager.get_connection_status("default")
            assert status == ConnectionStatus.HEALTHY  # Should be healthy when validation is disabled
            
            status = await manager.get_connection_status("unknown")
            assert status == ConnectionStatus.UNKNOWN
            
            await manager.stop()
    
    @pytest.mark.asyncio
    async def test_health_check_success(self, manager):
        """Test successful health check."""
        mock_client = AsyncMock()
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "models": [{"name": "llama3.2"}, {"name": "mistral"}]
        }
        mock_client.get.return_value = mock_response
        
        with patch('httpx.AsyncClient', return_value=mock_client):
            await manager.start()
            
            result = await manager.health_check("default")
            assert result is True
            
            status = await manager.get_connection_status("default")
            assert status == ConnectionStatus.HEALTHY
            
            models = await manager.get_available_models("default")
            assert models == ["llama3.2", "mistral"]
            
            await manager.stop()
    
    @pytest.mark.asyncio
    async def test_health_check_failure(self, manager):
        """Test failed health check."""
        mock_client = AsyncMock()
        mock_client.get.side_effect = httpx.ConnectError("Connection failed")
        
        with patch('httpx.AsyncClient', return_value=mock_client):
            await manager.start()
            
            result = await manager.health_check("default")
            assert result is False
            
            status = await manager.get_connection_status("default")
            assert status == ConnectionStatus.UNHEALTHY
            
            await manager.stop()
    
    @pytest.mark.asyncio
    async def test_connection_context_manager(self, manager):
        """Test connection context manager."""
        mock_client = AsyncMock()
        
        with patch('httpx.AsyncClient', return_value=mock_client):
            await manager.start()
            
            async with manager.connection("default") as client:
                assert client == mock_client
            
            await manager.stop()
    
    @pytest.mark.asyncio
    async def test_connection_info(self, manager):
        """Test getting connection information."""
        with patch('httpx.AsyncClient') as mock_client:
            mock_client.return_value = AsyncMock()
            
            await manager.start()
            
            info = await manager.get_connection_info()
            assert "default" in info
            assert info["default"]["base_url"] == "http://localhost:11434"
            assert info["default"]["status"] == ConnectionStatus.HEALTHY.value  # Should be healthy when validation is disabled
            
            await manager.stop()
    
    @pytest.mark.asyncio
    async def test_health_monitor_disabled(self, manager):
        """Test that health monitor is disabled when interval is 0."""
        with patch('httpx.AsyncClient') as mock_client:
            mock_client.return_value = AsyncMock()
            
            await manager.start()
            assert manager._health_monitor_task is None
            
            await manager.stop()
    
    @pytest.mark.asyncio
    async def test_health_monitor_enabled(self, config):
        """Test health monitor when enabled."""
        config.health_check_interval = 1
        manager = OllamaConnectionManager(config)
        
        with patch('httpx.AsyncClient') as mock_client:
            mock_client.return_value = AsyncMock()
            
            await manager.start()
            assert manager._health_monitor_task is not None
            
            await manager.stop()
    
    @pytest.mark.asyncio
    async def test_error_handling(self, manager):
        """Test error handling in connection operations."""
        with patch('httpx.AsyncClient') as mock_client:
            mock_client.side_effect = Exception("Client creation failed")
            
            # Starting should fail when client creation fails
            with pytest.raises(Exception, match="Client creation failed"):
                await manager.start()
            
            await manager.stop()


class TestGlobalManager:
    """Test global manager functions."""
    
    @pytest.mark.asyncio
    async def test_get_global_manager(self):
        """Test getting global manager instance."""
        # Clean up any existing manager
        await shutdown_global_manager()
        
        with patch('httpx.AsyncClient') as mock_client:
            mock_client.return_value = AsyncMock()
            
            manager1 = await get_global_manager()
            manager2 = await get_global_manager()
            
            assert manager1 is manager2  # Should be the same instance
            
            await shutdown_global_manager()
    
    @pytest.mark.asyncio
    async def test_shutdown_global_manager(self):
        """Test shutting down global manager."""
        with patch('httpx.AsyncClient') as mock_client:
            mock_client.return_value = AsyncMock()
            
            manager = await get_global_manager()
            assert manager is not None
            
            await shutdown_global_manager()
            
            # Getting manager again should create a new instance
            new_manager = await get_global_manager()
            assert new_manager is not manager
            
            await shutdown_global_manager()


class TestConnectionInfo:
    """Test ConnectionInfo class."""
    
    def test_connection_info_creation(self):
        """Test ConnectionInfo creation."""
        info = ConnectionInfo(
            server_id="test",
            base_url="http://test:8080",
            status=ConnectionStatus.HEALTHY,
            last_check=datetime.now()
        )
        
        assert info.server_id == "test"
        assert info.base_url == "http://test:8080"
        assert info.status == ConnectionStatus.HEALTHY
        assert info.client is None
        assert info.error_count == 0
        assert info.last_error is None
        assert info.models == []
    
    def test_connection_info_with_models(self):
        """Test ConnectionInfo with models."""
        info = ConnectionInfo(
            server_id="test",
            base_url="http://test:8080",
            status=ConnectionStatus.HEALTHY,
            last_check=datetime.now(),
            models=["llama3.2", "mistral"]
        )
        
        assert info.models == ["llama3.2", "mistral"]