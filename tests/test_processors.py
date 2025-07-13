"""
Tests for note processing pipeline.
"""

import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from pathlib import Path

from selene.processors.base import BaseProcessor, ProcessorResult
from selene.processors.llm_processor import LLMProcessor


class MockProcessor(BaseProcessor):
    """Mock processor for testing base functionality."""
    
    async def process(self, content: str, **kwargs) -> ProcessorResult:
        """Mock process method."""
        return ProcessorResult(
            success=True,
            content=f"Processed: {content}",
            metadata={"test": True, **kwargs}
        )
    
    def get_processor_info(self) -> dict:
        """Mock processor info."""
        return {"name": "Mock Processor", "version": "1.0.0"}


class TestBaseProcessor:
    """Test base processor functionality."""
    
    @pytest.fixture
    def processor(self):
        """Create mock processor instance."""
        return MockProcessor()
    
    @pytest.mark.asyncio
    async def test_process_basic(self, processor):
        """Test basic content processing."""
        result = await processor.process("test content")
        
        assert result.success is True
        assert result.content == "Processed: test content"
        assert result.metadata["test"] is True
        assert result.error is None
    
    @pytest.mark.asyncio
    async def test_process_with_kwargs(self, processor):
        """Test processing with additional parameters."""
        result = await processor.process("test", param1="value1", param2=42)
        
        assert result.success is True
        assert result.metadata["param1"] == "value1"
        assert result.metadata["param2"] == 42
    
    def test_validate_input_valid(self, processor):
        """Test input validation with valid content."""
        assert processor.validate_input("valid content") is True
        assert processor.validate_input("  valid with spaces  ") is True
    
    def test_validate_input_invalid(self, processor):
        """Test input validation with invalid content."""
        assert processor.validate_input("") is False
        assert processor.validate_input("   ") is False
        assert processor.validate_input(None) is False
    
    @pytest.mark.asyncio
    async def test_process_file_success(self, processor, tmp_path):
        """Test successful file processing."""
        test_file = tmp_path / "test.txt"
        test_file.write_text("file content")
        
        result = await processor.process_file(test_file)
        
        assert result.success is True
        assert result.content == "Processed: file content"
        assert result.metadata["file_path"] == str(test_file)
    
    @pytest.mark.asyncio
    async def test_process_file_not_found(self, processor, tmp_path):
        """Test file processing with non-existent file."""
        test_file = tmp_path / "nonexistent.txt"
        
        result = await processor.process_file(test_file)
        
        assert result.success is False
        assert "Failed to process file" in result.error
        assert result.metadata["file_path"] == str(test_file)
    
    @pytest.mark.asyncio
    async def test_process_file_empty(self, processor, tmp_path):
        """Test file processing with empty file."""
        test_file = tmp_path / "empty.txt"
        test_file.write_text("")
        
        result = await processor.process_file(test_file)
        
        assert result.success is False
        assert result.error == "Invalid or empty file content"
    
    @pytest.mark.asyncio
    async def test_process_batch(self, processor):
        """Test batch processing."""
        contents = ["content1", "content2", "content3"]
        
        results = await processor.process_batch(contents)
        
        assert len(results) == 3
        for i, result in enumerate(results):
            assert result.success is True
            assert result.content == f"Processed: content{i+1}"
            assert result.metadata["batch_index"] == i


class TestLLMProcessor:
    """Test LLM processor functionality."""
    
    @pytest.fixture
    def mock_openai_response(self):
        """Mock OpenAI response."""
        mock_response = MagicMock()
        mock_response.choices = [MagicMock()]
        mock_response.choices[0].message.content = "Enhanced content"
        mock_response.usage.total_tokens = 100
        mock_response.usage.prompt_tokens = 50
        mock_response.usage.completion_tokens = 50
        return mock_response
    
    def test_init_without_api_key(self):
        """Test initialization without API key."""
        with pytest.raises(ValueError, match="OpenAI API key is required"):
            LLMProcessor({})
    
    def test_init_with_config(self):
        """Test initialization with valid config."""
        config = {
            "openai_api_key": "test-key",
            "model": "gpt-4",
            "max_tokens": 500,
            "temperature": 0.5
        }
        
        processor = LLMProcessor(config)
        
        assert processor.api_key == "test-key"
        assert processor.model == "gpt-4"
        assert processor.max_tokens == 500
        assert processor.temperature == 0.5
    
    @pytest.mark.asyncio
    async def test_process_success(self, mock_openai_response):
        """Test successful LLM processing."""
        config = {"openai_api_key": "test-key"}
        processor = LLMProcessor(config)
        
        # Create async mock
        async_mock = AsyncMock(return_value=mock_openai_response)
        
        with patch.object(processor.client.chat.completions, 'create', async_mock):
            result = await processor.process("test content", task="enhance")
        
        assert result.success is True
        assert result.content == "Enhanced content"
        assert result.metadata["task"] == "enhance"
        assert result.metadata["tokens_used"] == 100
        assert result.processing_time is not None
    
    @pytest.mark.asyncio
    async def test_process_with_custom_prompt(self, mock_openai_response):
        """Test processing with custom prompt."""
        config = {"openai_api_key": "test-key"}
        processor = LLMProcessor(config)
        
        async_mock = AsyncMock(return_value=mock_openai_response)
        
        with patch.object(processor.client.chat.completions, 'create', async_mock) as mock_create:
            await processor.process("test", prompt="Custom prompt")
            
            call_args = mock_create.call_args
            messages = call_args[1]["messages"]
            assert messages[0]["content"] == "Custom prompt"
    
    @pytest.mark.asyncio
    async def test_process_api_error(self):
        """Test processing with API error."""
        config = {"openai_api_key": "test-key"}
        processor = LLMProcessor(config)
        
        async_mock = AsyncMock(side_effect=Exception("API Error"))
        
        with patch.object(processor.client.chat.completions, 'create', async_mock):
            result = await processor.process("test content")
        
        assert result.success is False
        assert "LLM processing failed" in result.error
        assert result.processing_time is not None
    
    def test_get_task_prompt(self):
        """Test task prompt generation."""
        config = {"openai_api_key": "test-key"}
        processor = LLMProcessor(config)
        
        # Test known tasks
        summarize_prompt = processor._get_task_prompt("summarize")
        assert "summarize" in summarize_prompt.lower()
        
        enhance_prompt = processor._get_task_prompt("enhance")
        assert "enhance" in enhance_prompt.lower()
        
        # Test unknown task defaults to enhance
        unknown_prompt = processor._get_task_prompt("unknown_task")
        assert unknown_prompt == enhance_prompt
    
    def test_get_processor_info(self):
        """Test processor info retrieval."""
        config = {"openai_api_key": "test-key", "model": "gpt-4"}
        processor = LLMProcessor(config)
        
        info = processor.get_processor_info()
        
        assert info["name"] == "LLM Processor"
        assert info["model"] == "gpt-4"
        assert "content_enhancement" in info["capabilities"]
        assert "enhance" in info["supported_tasks"]
    
    @pytest.mark.asyncio
    async def test_process_invalid_content(self):
        """Test processing with invalid content."""
        config = {"openai_api_key": "test-key"}
        processor = LLMProcessor(config)
        
        result = await processor.process("")
        
        assert result.success is False
        assert result.error == "Invalid or empty content"


@pytest.mark.integration
class TestProcessorIntegration:
    """Integration tests requiring real API keys."""
    
    @pytest.mark.skipif(not pytest.importorskip("os").getenv("OPENAI_API_KEY"), 
                       reason="OPENAI_API_KEY not set")
    @pytest.mark.asyncio
    async def test_real_llm_processing(self):
        """Test real LLM processing with actual API."""
        import os
        
        config = {"openai_api_key": os.getenv("OPENAI_API_KEY")}
        processor = LLMProcessor(config)
        
        result = await processor.process("This is a test note about machine learning.", task="summarize")
        
        assert result.success is True
        assert len(result.content) > 0
        assert result.metadata["tokens_used"] > 0
        assert result.processing_time > 0