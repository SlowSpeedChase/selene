"""
Tests for the main module
"""

import pytest
from typer.testing import CliRunner

from selene.main import app


class TestMain:
    """Test cases for main application functionality."""

    def setup_method(self):
        """Set up test fixtures."""
        self.runner = CliRunner()

    def test_version_command(self):
        """Test the version command."""
        result = self.runner.invoke(app, ["version"])
        assert result.exit_code == 0
        assert "Selene version:" in result.stdout

    def test_start_command(self):
        """Test the start command."""
        result = self.runner.invoke(app, ["start"])
        assert result.exit_code == 0
        assert "System initialized successfully!" in result.stdout