"""
Tests for the enhanced CLI chat interface.
"""

import pytest
import asyncio
import tempfile
import json
from pathlib import Path
from unittest.mock import Mock, AsyncMock, patch
from datetime import datetime

from selene.chat.cli import CLIChatInterface
from selene.chat.config import ChatConfig


class TestCLIChatInterface:
    """Test the enhanced CLI chat interface."""
    
    @pytest.fixture
    def mock_config(self):
        """Create mock chat configuration."""
        return ChatConfig(
            vault_path="test-vault",
            conversation_memory=True
        )
    
    @pytest.fixture
    def mock_agent(self):
        """Create mock enhanced chat agent."""
        agent = Mock()
        agent.initialize = AsyncMock(return_value=True)
        agent.chat = AsyncMock(return_value="Test response")
        agent.shutdown = AsyncMock()
        return agent
    
    def test_cli_initialization(self, mock_config):
        """Test CLI interface initialization."""
        cli = CLIChatInterface(mock_config)
        
        assert cli.config == mock_config
        assert cli.debug == False
        assert cli.running == False
        assert cli.session_id is not None
        assert cli.user_id is not None
        assert len(cli.shortcuts) > 0
        assert len(cli.available_commands) > 0
    
    def test_shortcuts_mapping(self, mock_config):
        """Test command shortcuts mapping."""
        cli = CLIChatInterface(mock_config)
        
        # Test common shortcuts
        assert cli.shortcuts['/h'] == 'help'
        assert cli.shortcuts['/q'] == 'quit'
        assert cli.shortcuts['/exit'] == 'quit'
        assert cli.shortcuts['/clear'] == 'clear'
        assert cli.shortcuts['/status'] == 'status'
    
    def test_available_commands(self, mock_config):
        """Test available commands dictionary."""
        cli = CLIChatInterface(mock_config)
        
        # Test essential commands
        assert 'help' in cli.available_commands
        assert 'quit' in cli.available_commands
        assert 'clear' in cli.available_commands
        assert 'status' in cli.available_commands
        assert 'stats' in cli.available_commands
        assert 'features' in cli.available_commands
    
    @pytest.mark.asyncio
    async def test_initialization_success(self, mock_config):
        """Test successful CLI initialization."""
        cli = CLIChatInterface(mock_config)
        
        with patch('selene.chat.cli.EnhancedChatAgent') as mock_agent_class:
            mock_agent = Mock()
            mock_agent.initialize = AsyncMock(return_value=True)
            mock_agent_class.return_value = mock_agent
            
            result = await cli.initialize()
            
            assert result == True
            assert cli.agent == mock_agent
            mock_agent.initialize.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_initialization_failure(self, mock_config):
        """Test failed CLI initialization."""
        cli = CLIChatInterface(mock_config)
        
        with patch('selene.chat.cli.EnhancedChatAgent') as mock_agent_class:
            mock_agent = Mock()
            mock_agent.initialize = AsyncMock(return_value=False)
            mock_agent_class.return_value = mock_agent
            
            result = await cli.initialize()
            
            assert result == False
    
    @pytest.mark.asyncio
    async def test_process_chat_message(self, mock_config):
        """Test processing chat messages."""
        cli = CLIChatInterface(mock_config)
        cli.agent = Mock()
        cli.agent.chat = AsyncMock(return_value="Test response")
        
        # Mock console output
        with patch.object(cli.console, 'status'), \
             patch.object(cli.console, 'print'), \
             patch.object(cli, '_display_response') as mock_display:
            
            await cli._process_input("test message")
            
            cli.agent.chat.assert_called_once_with("test message")
            mock_display.assert_called_once_with("Test response")
            
            # Check session data
            assert len(cli.session_data['messages']) == 1
            assert cli.session_data['messages'][0]['user'] == "test message"
            assert cli.session_data['messages'][0]['selene'] == "Test response"
    
    @pytest.mark.asyncio
    async def test_handle_help_command(self, mock_config):
        """Test help command handling."""
        cli = CLIChatInterface(mock_config)
        
        with patch.object(cli, '_show_help') as mock_help:
            await cli._handle_command('/help')
            mock_help.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_handle_quit_command(self, mock_config):
        """Test quit command handling."""
        cli = CLIChatInterface(mock_config)
        cli.running = True
        
        await cli._handle_command('/quit')
        
        assert cli.running == False
    
    @pytest.mark.asyncio
    async def test_handle_status_command(self, mock_config):
        """Test status command handling."""
        cli = CLIChatInterface(mock_config)
        cli.agent = Mock()
        
        with patch.object(cli, '_show_status') as mock_status:
            await cli._handle_command('/status')
            mock_status.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_command_shortcuts(self, mock_config):
        """Test command shortcuts work properly."""
        cli = CLIChatInterface(mock_config)
        
        with patch.object(cli, '_show_help') as mock_help:
            await cli._handle_command('/h')  # Shortcut for help
            mock_help.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_unknown_command(self, mock_config):
        """Test unknown command handling."""
        cli = CLIChatInterface(mock_config)
        
        with patch.object(cli.console, 'print') as mock_print:
            await cli._handle_command('/unknown')
            
            # Should print error message
            mock_print.assert_called()
    
    def test_session_statistics_tracking(self, mock_config):
        """Test session statistics tracking."""
        cli = CLIChatInterface(mock_config)
        
        # Initial state
        assert cli.session_data['statistics']['total_messages'] == 0
        assert cli.session_data['statistics']['commands_used'] == 0
        
        # Simulate message processing
        cli.session_data['statistics']['total_messages'] += 1
        cli.session_data['statistics']['response_times'].append(1.5)
        
        # Check statistics
        assert cli.session_data['statistics']['total_messages'] == 1
        assert len(cli.session_data['statistics']['response_times']) == 1
        assert cli.session_data['statistics']['response_times'][0] == 1.5
    
    def test_display_response(self, mock_config):
        """Test response display formatting."""
        cli = CLIChatInterface(mock_config)
        
        with patch.object(cli.console, 'print') as mock_print:
            cli._display_response("Test response")
            
            # Should print formatted response
            mock_print.assert_called()
    
    def test_show_help(self, mock_config):
        """Test help display."""
        cli = CLIChatInterface(mock_config)
        
        with patch.object(cli.console, 'print') as mock_print:
            cli._show_help()
            
            # Should print help information
            assert mock_print.call_count >= 2  # Table + examples
    
    def test_show_commands(self, mock_config):
        """Test commands display."""
        cli = CLIChatInterface(mock_config)
        
        with patch.object(cli.console, 'print') as mock_print:
            cli._show_commands()
            
            # Should print commands
            mock_print.assert_called()
    
    def test_show_statistics(self, mock_config):
        """Test statistics display."""
        cli = CLIChatInterface(mock_config)
        
        # Add some test data
        cli.session_data['statistics']['total_messages'] = 5
        cli.session_data['statistics']['commands_used'] = 2
        cli.session_data['statistics']['response_times'] = [1.0, 2.0, 1.5]
        
        with patch.object(cli.console, 'print') as mock_print:
            cli._show_statistics()
            
            # Should print statistics
            mock_print.assert_called()
    
    @pytest.mark.asyncio
    async def test_show_features(self, mock_config):
        """Test features display."""
        cli = CLIChatInterface(mock_config)
        cli.agent = Mock()
        
        with patch.object(cli.console, 'print') as mock_print:
            await cli._show_features()
            
            # Should print features
            mock_print.assert_called()
    
    def test_show_vault_info(self, mock_config):
        """Test vault information display."""
        cli = CLIChatInterface(mock_config)
        
        with patch.object(cli.console, 'print') as mock_print:
            cli._show_vault_info()
            
            # Should print vault information
            mock_print.assert_called()
    
    def test_show_history_empty(self, mock_config):
        """Test history display when empty."""
        cli = CLIChatInterface(mock_config)
        
        with patch.object(cli.console, 'print') as mock_print:
            cli._show_history()
            
            # Should print empty history message
            mock_print.assert_called()
    
    def test_show_history_with_messages(self, mock_config):
        """Test history display with messages."""
        cli = CLIChatInterface(mock_config)
        
        # Add test messages
        cli.session_data['messages'] = [
            {
                'timestamp': datetime.now().isoformat(),
                'user': 'test message',
                'selene': 'test response',
                'response_time': 1.0
            }
        ]
        
        with patch.object(cli.console, 'print') as mock_print:
            cli._show_history()
            
            # Should print history
            mock_print.assert_called()
    
    def test_format_history(self, mock_config):
        """Test history formatting."""
        cli = CLIChatInterface(mock_config)
        
        # Add test messages
        cli.session_data['messages'] = [
            {
                'timestamp': datetime.now().isoformat(),
                'user': 'test message',
                'selene': 'test response',
                'response_time': 1.0
            }
        ]
        
        formatted = cli._format_history()
        
        assert 'test message' in formatted
        assert 'test response' in formatted
    
    def test_format_duration(self, mock_config):
        """Test duration formatting."""
        cli = CLIChatInterface(mock_config)
        
        # Test different duration formats
        duration = cli._format_duration()
        
        # Should return formatted duration string
        assert isinstance(duration, str)
        assert any(char in duration for char in ['s', 'm', 'h'])
    
    @pytest.mark.asyncio
    async def test_save_session(self, mock_config):
        """Test session saving."""
        cli = CLIChatInterface(mock_config)
        
        with tempfile.TemporaryDirectory() as tmpdir:
            # Change to temp directory
            original_cwd = Path.cwd()
            
            try:
                import os
                os.chdir(tmpdir)
                
                with patch.object(cli.console, 'print') as mock_print:
                    await cli._save_session()
                    
                    # Should print success message
                    mock_print.assert_called()
                    
                    # Check file was created
                    sessions_dir = Path("sessions")
                    assert sessions_dir.exists()
                    
                    session_files = list(sessions_dir.glob("session_*.json"))
                    assert len(session_files) == 1
                    
                    # Check file contents
                    with open(session_files[0], 'r') as f:
                        data = json.load(f)
                    
                    assert data['session_id'] == cli.session_id
                    assert data['user_id'] == cli.user_id
                    
            finally:
                os.chdir(original_cwd)
    
    @pytest.mark.asyncio
    async def test_load_session_no_files(self, mock_config):
        """Test loading session when no files exist."""
        cli = CLIChatInterface(mock_config)
        
        with patch.object(cli.console, 'print') as mock_print:
            await cli._load_session()
            
            # Should print no sessions message
            mock_print.assert_called()
    
    def test_toggle_debug(self, mock_config):
        """Test debug mode toggle."""
        cli = CLIChatInterface(mock_config)
        
        initial_debug = cli.debug
        
        with patch.object(cli.console, 'print') as mock_print:
            cli._toggle_debug()
            
            # Should toggle debug state
            assert cli.debug != initial_debug
            mock_print.assert_called()
    
    @pytest.mark.asyncio
    async def test_search_vault(self, mock_config):
        """Test vault search functionality."""
        cli = CLIChatInterface(mock_config)
        cli.agent = Mock()
        cli.agent.chat = AsyncMock(return_value="Search results")
        
        with patch('rich.prompt.Prompt.ask', return_value="test query"), \
             patch.object(cli.console, 'status'), \
             patch.object(cli, '_display_response') as mock_display:
            
            await cli._search_vault()
            
            cli.agent.chat.assert_called_once_with("search test query")
            mock_display.assert_called_once_with("Search results")
    
    @pytest.mark.asyncio
    async def test_search_vault_empty_query(self, mock_config):
        """Test vault search with empty query."""
        cli = CLIChatInterface(mock_config)
        cli.agent = Mock()
        
        with patch('rich.prompt.Prompt.ask', return_value=""):
            await cli._search_vault()
            
            # Should not call agent
            cli.agent.chat.assert_not_called()
    
    @pytest.mark.asyncio
    async def test_show_connections(self, mock_config):
        """Test showing connections."""
        cli = CLIChatInterface(mock_config)
        cli.agent = Mock()
        cli.agent.chat = AsyncMock(return_value="Connection info")
        
        with patch.object(cli.console, 'status'), \
             patch.object(cli, '_display_response') as mock_display:
            
            await cli._show_connections()
            
            cli.agent.chat.assert_called_once_with("show connections")
            mock_display.assert_called_once_with("Connection info")
    
    @pytest.mark.asyncio
    async def test_shutdown(self, mock_config):
        """Test CLI shutdown."""
        cli = CLIChatInterface(mock_config)
        cli.agent = Mock()
        cli.agent.shutdown = AsyncMock()
        
        with patch.object(cli, '_save_session') as mock_save, \
             patch.object(cli.console, 'print') as mock_print:
            
            await cli._shutdown()
            
            mock_save.assert_called_once()
            cli.agent.shutdown.assert_called_once()
            mock_print.assert_called()  # Goodbye message


class TestCLIChatIntegration:
    """Integration tests for CLI chat functionality."""
    
    @pytest.mark.asyncio
    async def test_run_cli_chat_function(self):
        """Test the run_cli_chat function."""
        with patch('selene.chat.cli.ChatConfig') as mock_config_class, \
             patch('selene.chat.cli.CLIChatInterface') as mock_cli_class:
            
            # Setup mocks
            mock_config = Mock()
            mock_config_class.from_file.return_value = mock_config
            
            mock_cli = Mock()
            mock_cli.run = AsyncMock()
            mock_cli_class.return_value = mock_cli
            
            # Import and run function
            from selene.chat.cli import run_cli_chat
            
            await run_cli_chat(
                vault="test-vault",
                config_file="test-config.yaml",
                no_memory=True,
                debug=True
            )
            
            # Check configuration was updated
            assert mock_config.vault_path == "test-vault"
            assert mock_config.conversation_memory == False
            
            # Check CLI was created and run
            mock_cli_class.assert_called_once_with(mock_config, debug=True)
            mock_cli.run.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_run_cli_chat_with_defaults(self):
        """Test run_cli_chat with default parameters."""
        with patch('selene.chat.cli.ChatConfig') as mock_config_class, \
             patch('selene.chat.cli.CLIChatInterface') as mock_cli_class:
            
            # Setup mocks
            mock_config = Mock()
            mock_config_class.from_file.return_value = mock_config
            
            mock_cli = Mock()
            mock_cli.run = AsyncMock()
            mock_cli_class.return_value = mock_cli
            
            # Import and run function
            from selene.chat.cli import run_cli_chat
            
            await run_cli_chat()
            
            # Check CLI was created with defaults
            mock_cli_class.assert_called_once_with(mock_config, debug=False)
            mock_cli.run.assert_called_once()
    
    def test_import_cli_module(self):
        """Test that CLI module can be imported."""
        from selene.chat.cli import CLIChatInterface, run_cli_chat
        
        # Check classes and functions exist
        assert CLIChatInterface is not None
        assert run_cli_chat is not None
        assert callable(run_cli_chat)


class TestCLIChatCommands:
    """Test specific CLI chat commands."""
    
    @pytest.fixture
    def cli_with_agent(self):
        """Create CLI with mock agent."""
        config = ChatConfig(vault_path="test-vault")
        cli = CLIChatInterface(config)
        cli.agent = Mock()
        cli.agent.chat = AsyncMock(return_value="Test response")
        return cli
    
    @pytest.mark.asyncio
    async def test_clear_command(self, cli_with_agent):
        """Test clear command."""
        cli = cli_with_agent
        
        with patch.object(cli.console, 'clear') as mock_clear:
            await cli._handle_command('/clear')
            mock_clear.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_stats_command(self, cli_with_agent):
        """Test stats command."""
        cli = cli_with_agent
        
        with patch.object(cli, '_show_statistics') as mock_stats:
            await cli._handle_command('/stats')
            mock_stats.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_commands_command(self, cli_with_agent):
        """Test commands command."""
        cli = cli_with_agent
        
        with patch.object(cli, '_show_commands') as mock_commands:
            await cli._handle_command('/commands')
            mock_commands.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_history_command(self, cli_with_agent):
        """Test history command."""
        cli = cli_with_agent
        
        with patch.object(cli, '_show_history') as mock_history:
            await cli._handle_command('/history')
            mock_history.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_debug_command(self, cli_with_agent):
        """Test debug command."""
        cli = cli_with_agent
        
        with patch.object(cli, '_toggle_debug') as mock_debug:
            await cli._handle_command('/debug')
            mock_debug.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_vault_command(self, cli_with_agent):
        """Test vault command."""
        cli = cli_with_agent
        
        with patch.object(cli, '_show_vault_info') as mock_vault:
            await cli._handle_command('/vault')
            mock_vault.assert_called_once()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])