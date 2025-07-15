"""
Tests for MultiModelProcessor - SMS-19 Advanced AI Features
"""

import pytest
import asyncio
from unittest.mock import Mock, AsyncMock, patch
from selene.processors.multi_model_processor import (
    MultiModelProcessor, 
    ModelConfig, 
    ModelComparisonResult
)
from selene.processors.base import ProcessorResult


class TestMultiModelProcessor:
    """Test suite for MultiModelProcessor."""
    
    @pytest.fixture
    def mock_config(self):
        """Mock configuration for testing."""
        return {
            "models": [
                {
                    "name": "llama3.2:1b",
                    "type": "ollama",
                    "config": {
                        "base_url": "http://localhost:11434",
                        "model": "llama3.2:1b",
                        "validate_on_init": False
                    },
                    "tasks": ["summarize", "classify"],
                    "priority": 1
                },
                {
                    "name": "mistral:7b",
                    "type": "ollama",
                    "config": {
                        "base_url": "http://localhost:11434",
                        "model": "mistral:7b",
                        "validate_on_init": False
                    },
                    "tasks": ["enhance", "extract_insights"],
                    "priority": 2
                }
            ]
        }
    
    @pytest.fixture
    def processor(self, mock_config):
        """Create MultiModelProcessor instance for testing."""
        return MultiModelProcessor(mock_config)
    
    def test_model_config_creation(self):
        """Test ModelConfig dataclass creation."""
        config = ModelConfig(
            name="test_model",
            type="ollama",
            config={"model": "test"},
            tasks=["summarize"],
            priority=1
        )
        
        assert config.name == "test_model"
        assert config.type == "ollama"
        assert config.tasks == ["summarize"]
        assert config.priority == 1
        assert config.enabled is True
        assert config.max_concurrent == 1
    
    def test_model_comparison_result_creation(self):
        """Test ModelComparisonResult dataclass creation."""
        result = ModelComparisonResult(
            task="summarize",
            content="test content",
            model_results=[],
            best_model="llama3.2:1b",
            processing_time=1.5
        )
        
        assert result.task == "summarize"
        assert result.content == "test content"
        assert result.best_model == "llama3.2:1b"
        assert result.processing_time == 1.5
    
    def test_load_model_configs(self, processor):
        """Test loading model configurations."""
        assert len(processor.model_configs) == 2
        assert "llama3.2:1b" in processor.model_configs
        assert "mistral:7b" in processor.model_configs
        
        # Test first model config
        config = processor.model_configs["llama3.2:1b"]
        assert config.name == "llama3.2:1b"
        assert config.type == "ollama"
        assert config.tasks == ["summarize", "classify"]
        assert config.priority == 1
    
    def test_load_default_config(self):
        """Test loading default configuration when none provided."""
        processor = MultiModelProcessor({})
        
        assert len(processor.model_configs) == 1
        assert "llama3.2:1b" in processor.model_configs
        
        config = processor.model_configs["llama3.2:1b"]
        assert config.tasks == ["summarize", "classify"]
    
    def test_build_routing_rules(self, processor):
        """Test building routing rules from model configs."""
        # Should have routing rules for all tasks
        expected_tasks = ["summarize", "classify", "enhance", "extract_insights"]
        
        for task in expected_tasks:
            assert task in processor.routing_rules
        
        # Check specific routing (priority-based)
        assert processor.routing_rules["summarize"] == "llama3.2:1b"  # priority 1
        assert processor.routing_rules["enhance"] == "mistral:7b"  # priority 2
    
    def test_model_stats_initialization(self, processor):
        """Test model statistics initialization."""
        assert len(processor.model_stats) == 2
        
        for model_name in ["llama3.2:1b", "mistral:7b"]:
            stats = processor.model_stats[model_name]
            assert stats["total_requests"] == 0
            assert stats["successful_requests"] == 0
            assert stats["failed_requests"] == 0
            assert stats["avg_processing_time"] == 0.0
            assert stats["last_used"] is None
    
    def test_get_available_models(self, processor):
        """Test getting available models."""
        # Mock the models dict since _initialize_models is async
        processor.models = {
            "llama3.2:1b": Mock(),
            "mistral:7b": Mock()
        }
        
        available = processor.get_available_models()
        assert len(available) == 2
        assert "llama3.2:1b" in available
        assert "mistral:7b" in available
    
    def test_get_tasks_for_model(self, processor):
        """Test getting tasks for a specific model."""
        tasks = processor.get_tasks_for_model("llama3.2:1b")
        assert tasks == ["summarize", "classify"]
        
        tasks = processor.get_tasks_for_model("mistral:7b")
        assert tasks == ["enhance", "extract_insights"]
        
        # Test non-existent model
        tasks = processor.get_tasks_for_model("non_existent")
        assert tasks == []
    
    def test_get_model_for_task(self, processor):
        """Test getting preferred model for a task."""
        assert processor.get_model_for_task("summarize") == "llama3.2:1b"
        assert processor.get_model_for_task("enhance") == "mistral:7b"
        assert processor.get_model_for_task("non_existent") is None
    
    def test_get_processor_info(self, processor):
        """Test getting processor information."""
        info = processor.get_processor_info()
        
        assert info["name"] == "MultiModelProcessor"
        assert info["version"] == "1.0.0"
        assert "multi_model_processing" in info["capabilities"]
        assert "task_routing" in info["capabilities"]
        assert "model_comparison" in info["capabilities"]
        
        # Check models info
        assert len(info["models"]) == 2
        assert "llama3.2:1b" in info["models"]
        assert info["models"]["llama3.2:1b"]["type"] == "ollama"
        assert info["models"]["llama3.2:1b"]["tasks"] == ["summarize", "classify"]
        
        # Check routing rules
        assert info["routing_rules"]["summarize"] == "llama3.2:1b"
        assert info["routing_rules"]["enhance"] == "mistral:7b"
    
    def test_get_model_stats(self, processor):
        """Test getting model statistics."""
        stats = processor.get_model_stats()
        
        assert len(stats) == 2
        assert "llama3.2:1b" in stats
        assert "mistral:7b" in stats
        
        # Check stats structure
        for model_name in stats:
            model_stats = stats[model_name]
            assert "total_requests" in model_stats
            assert "successful_requests" in model_stats
            assert "failed_requests" in model_stats
            assert "avg_processing_time" in model_stats
            assert "last_used" in model_stats


class TestMultiModelProcessorAsync:
    """Test suite for async functionality of MultiModelProcessor."""
    
    @pytest.fixture
    def processor_with_mocks(self):
        """Create processor with mocked models."""
        config = {
            "models": [
                {
                    "name": "model1",
                    "type": "ollama",
                    "config": {"model": "model1"},
                    "tasks": ["summarize"],
                    "priority": 1
                },
                {
                    "name": "model2",
                    "type": "ollama",
                    "config": {"model": "model2"},
                    "tasks": ["enhance"],
                    "priority": 2
                }
            ]
        }
        
        processor = MultiModelProcessor(config)
        
        # Mock the models
        mock_model1 = Mock()
        mock_model1.process = AsyncMock(return_value=ProcessorResult(
            success=True,
            content="model1 result",
            metadata={"model": "model1"}
        ))
        
        mock_model2 = Mock()
        mock_model2.process = AsyncMock(return_value=ProcessorResult(
            success=True,
            content="model2 result",
            metadata={"model": "model2"}
        ))
        
        processor.models = {
            "model1": mock_model1,
            "model2": mock_model2
        }
        
        return processor
    
    @pytest.mark.asyncio
    async def test_process_with_routing(self, processor_with_mocks):
        """Test processing with automatic routing."""
        result = await processor_with_mocks.process(
            content="test content",
            task="summarize"
        )
        
        assert result.success
        assert result.content == "model1 result"
        assert result.metadata["selected_model"] == "model1"
        assert result.metadata["routing_used"] is True
        
        # Check that the correct model was called
        processor_with_mocks.models["model1"].process.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_process_with_specific_model(self, processor_with_mocks):
        """Test processing with specific model."""
        result = await processor_with_mocks.process(
            content="test content",
            task="enhance",
            model="model2"
        )
        
        assert result.success
        assert result.content == "model2 result"
        assert result.metadata["selected_model"] == "model2"
        
        # Check that the correct model was called
        processor_with_mocks.models["model2"].process.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_process_model_not_found(self, processor_with_mocks):
        """Test processing with non-existent model."""
        result = await processor_with_mocks.process(
            content="test content",
            task="summarize",
            model="non_existent"
        )
        
        assert not result.success
        assert "Model not found" in result.error
        assert result.metadata["error"] == "model_not_found"
    
    @pytest.mark.asyncio
    async def test_process_no_model_for_task(self, processor_with_mocks):
        """Test processing with task that has no configured model."""
        result = await processor_with_mocks.process(
            content="test content",
            task="unknown_task"
        )
        
        assert not result.success
        assert "No model configured for task" in result.error
        assert result.metadata["error"] == "no_model_for_task"
    
    @pytest.mark.asyncio
    async def test_fallback_processing(self, processor_with_mocks):
        """Test fallback processing when primary model fails."""
        # Make first model fail
        processor_with_mocks.models["model1"].process = AsyncMock(
            return_value=ProcessorResult(
                success=False,
                content="",
                metadata={},
                error="model1 failed"
            )
        )
        
        # Add model2 to handle summarize task for fallback
        processor_with_mocks.model_configs["model2"].tasks.append("summarize")
        processor_with_mocks._build_routing_rules()
        
        result = await processor_with_mocks.process(
            content="test content",
            task="summarize",
            fallback=True
        )
        
        assert result.success
        assert result.content == "model2 result"
        assert result.metadata["fallback_used"] is True
        assert result.metadata["failed_model"] == "model1"
        assert result.metadata["fallback_model"] == "model2"
    
    @pytest.mark.asyncio
    async def test_model_comparison(self, processor_with_mocks):
        """Test model comparison functionality."""
        result = await processor_with_mocks.process(
            content="test content",
            task="summarize",
            compare_models=["model1", "model2"]
        )
        
        assert result.success
        assert result.metadata["models_compared"] == ["model1", "model2"]
        assert result.metadata["best_model"] == "model1"
        assert "comparison_result" in result.metadata
        
        # Both models should have been called
        processor_with_mocks.models["model1"].process.assert_called_once()
        processor_with_mocks.models["model2"].process.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_model_stats_update(self, processor_with_mocks):
        """Test that model statistics are updated after processing."""
        # Initial stats
        initial_stats = processor_with_mocks.model_stats["model1"].copy()
        assert initial_stats["total_requests"] == 0
        assert initial_stats["successful_requests"] == 0
        
        # Process request
        await processor_with_mocks.process(
            content="test content",
            task="summarize"
        )
        
        # Check updated stats
        updated_stats = processor_with_mocks.model_stats["model1"]
        assert updated_stats["total_requests"] == 1
        assert updated_stats["successful_requests"] == 1
        assert updated_stats["failed_requests"] == 0
        assert updated_stats["last_used"] is not None
        assert updated_stats["avg_processing_time"] > 0
    
    @pytest.mark.asyncio
    async def test_model_stats_failure(self, processor_with_mocks):
        """Test that model statistics are updated on failure."""
        # Make model fail
        processor_with_mocks.models["model1"].process = AsyncMock(
            return_value=ProcessorResult(
                success=False,
                content="",
                metadata={},
                error="processing failed"
            )
        )
        
        # Process request
        await processor_with_mocks.process(
            content="test content",
            task="summarize"
        )
        
        # Check failure stats
        stats = processor_with_mocks.model_stats["model1"]
        assert stats["total_requests"] == 1
        assert stats["successful_requests"] == 0
        assert stats["failed_requests"] == 1


if __name__ == "__main__":
    pytest.main([__file__])