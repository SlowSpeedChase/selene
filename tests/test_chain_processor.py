"""
Tests for Chain Processor - SMS-19 Phase 2: Chain Processing
"""

import pytest
import asyncio
from unittest.mock import Mock, AsyncMock, patch

from selene.processors.chain_processor import (
    ProcessingChain,
    ChainStep,
    ChainStepResult,
    ChainResult,
    ChainExecutionMode,
    ChainStepCondition
)
from selene.processors.base import ProcessorResult


class TestChainStep:
    """Test suite for ChainStep data model."""
    
    def test_chain_step_creation(self):
        """Test basic ChainStep creation."""
        step = ChainStep(
            task="summarize",
            step_id="step1",
            description="Summarize content"
        )
        
        assert step.task == "summarize"
        assert step.step_id == "step1"
        assert step.description == "Summarize content"
        assert step.execution_mode == ChainExecutionMode.SEQUENTIAL
        assert step.processor_type == "multi_model"
        assert step.retry_count == 0
        assert step.skip_on_failure is False
    
    def test_chain_step_with_parallel_config(self):
        """Test ChainStep with parallel configuration."""
        step = ChainStep(
            task="enhance",
            step_id="step2",
            execution_mode=ChainExecutionMode.PARALLEL,
            parallel_group="analysis_group",
            model="llama3.2:3b"
        )
        
        assert step.execution_mode == ChainExecutionMode.PARALLEL
        assert step.parallel_group == "analysis_group"
        assert step.model == "llama3.2:3b"
    
    def test_chain_step_with_condition(self):
        """Test ChainStep with conditional execution."""
        step = ChainStep(
            task="questions",
            step_id="step3",
            execution_mode=ChainExecutionMode.CONDITIONAL,
            condition=ChainStepCondition.SUCCESS,
            condition_value="summary completed"
        )
        
        assert step.condition == ChainStepCondition.SUCCESS
        assert step.condition_value == "summary completed"
        assert step.execution_mode == ChainExecutionMode.CONDITIONAL


class TestProcessingChain:
    """Test suite for ProcessingChain."""
    
    def test_chain_initialization(self):
        """Test basic chain initialization."""
        steps = [
            ChainStep(task="summarize", step_id="step1"),
            ChainStep(task="enhance", step_id="step2")
        ]
        
        chain = ProcessingChain(steps, chain_id="test_chain")
        
        assert chain.chain_id == "test_chain"
        assert len(chain.steps) == 2
        assert chain.steps[0].step_id == "step1"
        assert chain.steps[1].step_id == "step2"
    
    def test_chain_validation_empty_steps(self):
        """Test chain validation with empty steps."""
        with pytest.raises(ValueError, match="Chain must have at least one step"):
            ProcessingChain([])
    
    def test_chain_validation_duplicate_step_ids(self):
        """Test chain validation with duplicate step IDs."""
        steps = [
            ChainStep(task="summarize", step_id="step1"),
            ChainStep(task="enhance", step_id="step1")  # Duplicate ID
        ]
        
        with pytest.raises(ValueError, match="All step IDs must be unique"):
            ProcessingChain(steps)
    
    def test_execution_plan_building(self):
        """Test execution plan building."""
        steps = [
            ChainStep(task="summarize", step_id="step1", execution_mode=ChainExecutionMode.SEQUENTIAL),
            ChainStep(task="enhance", step_id="step2", execution_mode=ChainExecutionMode.PARALLEL, parallel_group="group1"),
            ChainStep(task="classify", step_id="step3", execution_mode=ChainExecutionMode.PARALLEL, parallel_group="group1"),
            ChainStep(task="questions", step_id="step4", execution_mode=ChainExecutionMode.CONDITIONAL)
        ]
        
        chain = ProcessingChain(steps)
        plan = chain.execution_plan
        
        assert len(plan["sequential_steps"]) == 1
        assert len(plan["parallel_groups"]["group1"]) == 2
        assert len(plan["conditional_steps"]) == 1
    
    def test_chain_info(self):
        """Test getting chain information."""
        steps = [
            ChainStep(task="summarize", step_id="step1", description="Summarize content"),
            ChainStep(task="enhance", step_id="step2", description="Enhance content")
        ]
        
        chain = ProcessingChain(steps, chain_id="info_test")
        info = chain.get_chain_info()
        
        assert info["chain_id"] == "info_test"
        assert info["total_steps"] == 2
        assert len(info["steps"]) == 2
        assert info["steps"][0]["step_id"] == "step1"
        assert info["steps"][0]["task"] == "summarize"
        assert info["steps"][0]["description"] == "Summarize content"


class TestChainExecution:
    """Test suite for chain execution functionality."""
    
    @pytest.fixture
    def mock_multi_model_processor(self):
        """Create a mock multi-model processor."""
        processor = Mock()
        processor.process = AsyncMock()
        return processor
    
    @pytest.fixture
    def simple_chain(self):
        """Create a simple chain for testing."""
        steps = [
            ChainStep(task="summarize", step_id="step1", description="Summarize"),
            ChainStep(task="enhance", step_id="step2", description="Enhance")
        ]
        return ProcessingChain(steps, chain_id="test_chain")
    
    @pytest.mark.asyncio
    async def test_sequential_execution_success(self, simple_chain, mock_multi_model_processor):
        """Test successful sequential execution."""
        # Mock processor responses
        mock_multi_model_processor.process.side_effect = [
            ProcessorResult(
                success=True,
                content="Summarized content",
                metadata={"model": "llama3.2:1b"}
            ),
            ProcessorResult(
                success=True,
                content="Enhanced content",
                metadata={"model": "llama3.2:3b"}
            )
        ]
        
        # Set the mock processor
        simple_chain.multi_model_processor = mock_multi_model_processor
        
        # Execute chain
        result = await simple_chain.execute("Original content")
        
        # Verify results
        assert result.success is True
        assert result.final_content == "Enhanced content"
        assert result.total_steps == 2
        assert result.successful_steps == 2
        assert result.failed_steps == 0
        assert len(result.step_results) == 2
        
        # Verify processor was called correctly
        assert mock_multi_model_processor.process.call_count == 2
        
        # Check first call
        first_call = mock_multi_model_processor.process.call_args_list[0]
        assert first_call[0][0] == "Original content"
        assert first_call[1]["task"] == "summarize"
        
        # Check second call
        second_call = mock_multi_model_processor.process.call_args_list[1]
        assert second_call[0][0] == "Summarized content"
        assert second_call[1]["task"] == "enhance"
    
    @pytest.mark.asyncio
    async def test_sequential_execution_failure(self, simple_chain, mock_multi_model_processor):
        """Test sequential execution with failure."""
        # Mock processor responses - first succeeds, second fails
        mock_multi_model_processor.process.side_effect = [
            ProcessorResult(
                success=True,
                content="Summarized content",
                metadata={"model": "llama3.2:1b"}
            ),
            ProcessorResult(
                success=False,
                content="",
                metadata={},
                error="Processing failed"
            )
        ]
        
        # Set the mock processor
        simple_chain.multi_model_processor = mock_multi_model_processor
        
        # Execute chain
        result = await simple_chain.execute("Original content")
        
        # Verify results
        assert result.success is False
        assert result.error == "Step step2 failed: Processing failed"
        assert result.failed_step == "step2"
        assert result.total_steps == 2
        assert result.successful_steps == 1
        assert result.failed_steps == 1
        assert len(result.step_results) == 2
    
    @pytest.mark.asyncio
    async def test_parallel_execution(self, mock_multi_model_processor):
        """Test parallel execution."""
        steps = [
            ChainStep(
                task="summarize", 
                step_id="step1", 
                execution_mode=ChainExecutionMode.PARALLEL,
                parallel_group="analysis"
            ),
            ChainStep(
                task="classify", 
                step_id="step2", 
                execution_mode=ChainExecutionMode.PARALLEL,
                parallel_group="analysis"
            )
        ]
        
        chain = ProcessingChain(steps)
        
        # Mock processor responses
        mock_multi_model_processor.process.side_effect = [
            ProcessorResult(
                success=True,
                content="Summary result",
                metadata={"model": "llama3.2:1b"}
            ),
            ProcessorResult(
                success=True,
                content="Classification result",
                metadata={"model": "llama3.2:1b"}
            )
        ]
        
        # Set the mock processor
        chain.multi_model_processor = mock_multi_model_processor
        
        # Execute chain
        result = await chain.execute("Original content")
        
        # Verify results
        assert result.success is True
        assert result.total_steps == 2
        assert result.successful_steps == 2
        assert result.failed_steps == 0
        
        # Verify both tasks were called with original content (parallel)
        assert mock_multi_model_processor.process.call_count == 2
        
        # Both calls should have original content
        first_call = mock_multi_model_processor.process.call_args_list[0]
        second_call = mock_multi_model_processor.process.call_args_list[1]
        
        assert first_call[0][0] == "Original content"
        assert second_call[0][0] == "Original content"
        
        # Results should be aggregated
        assert "Summary result" in result.final_content
        assert "Classification result" in result.final_content
    
    @pytest.mark.asyncio
    async def test_conditional_execution(self, mock_multi_model_processor):
        """Test conditional execution."""
        steps = [
            ChainStep(task="summarize", step_id="step1"),
            ChainStep(
                task="questions", 
                step_id="step2",
                execution_mode=ChainExecutionMode.CONDITIONAL,
                condition=ChainStepCondition.SUCCESS
            )
        ]
        
        chain = ProcessingChain(steps)
        
        # Mock processor responses
        mock_multi_model_processor.process.side_effect = [
            ProcessorResult(
                success=True,
                content="Summary result",
                metadata={"model": "llama3.2:1b"}
            ),
            ProcessorResult(
                success=True,
                content="Questions result",
                metadata={"model": "llama3.2:1b"}
            )
        ]
        
        # Set the mock processor
        chain.multi_model_processor = mock_multi_model_processor
        
        # Execute chain
        result = await chain.execute("Original content")
        
        # Verify results
        assert result.success is True
        assert result.total_steps == 2
        assert result.successful_steps == 2
        assert result.final_content == "Questions result"
        
        # Both steps should have been executed
        assert mock_multi_model_processor.process.call_count == 2
    
    @pytest.mark.asyncio
    async def test_retry_mechanism(self, mock_multi_model_processor):
        """Test retry mechanism for failed steps."""
        steps = [
            ChainStep(
                task="summarize", 
                step_id="step1",
                retry_count=2
            )
        ]
        
        chain = ProcessingChain(steps)
        
        # Mock processor to fail twice, then succeed
        mock_multi_model_processor.process.side_effect = [
            ProcessorResult(success=False, content="", metadata={}, error="First failure"),
            ProcessorResult(success=False, content="", metadata={}, error="Second failure"),
            ProcessorResult(success=True, content="Success on third try", metadata={})
        ]
        
        # Set the mock processor
        chain.multi_model_processor = mock_multi_model_processor
        
        # Execute chain
        result = await chain.execute("Original content")
        
        # Verify results
        assert result.success is True
        assert result.final_content == "Success on third try"
        assert result.step_results[0].retry_attempts == 2
        
        # Processor should have been called 3 times
        assert mock_multi_model_processor.process.call_count == 3
    
    @pytest.mark.asyncio
    async def test_skip_on_failure(self, mock_multi_model_processor):
        """Test skip_on_failure functionality."""
        steps = [
            ChainStep(
                task="summarize", 
                step_id="step1",
                skip_on_failure=True
            ),
            ChainStep(task="enhance", step_id="step2")
        ]
        
        chain = ProcessingChain(steps)
        
        # Mock processor - first fails, second succeeds
        mock_multi_model_processor.process.side_effect = [
            ProcessorResult(success=False, content="", metadata={}, error="First step failed"),
            ProcessorResult(success=True, content="Enhanced content", metadata={})
        ]
        
        # Set the mock processor
        chain.multi_model_processor = mock_multi_model_processor
        
        # Execute chain
        result = await chain.execute("Original content")
        
        # Verify results
        assert result.success is True
        assert result.final_content == "Enhanced content"
        assert result.total_steps == 2
        assert result.successful_steps == 1
        assert result.failed_steps == 1
        
        # Second step should have been called with original content
        second_call = mock_multi_model_processor.process.call_args_list[1]
        assert second_call[0][0] == "Original content"
    
    @pytest.mark.asyncio
    async def test_content_transformation(self, mock_multi_model_processor):
        """Test input/output content transformation."""
        steps = [
            ChainStep(
                task="summarize", 
                step_id="step1",
                input_transform="Transform: {content}",
                output_transform="Result: {content}"
            )
        ]
        
        chain = ProcessingChain(steps)
        
        # Mock processor response
        mock_multi_model_processor.process.return_value = ProcessorResult(
            success=True,
            content="Summary",
            metadata={}
        )
        
        # Set the mock processor
        chain.multi_model_processor = mock_multi_model_processor
        
        # Execute chain
        result = await chain.execute("Original content")
        
        # Verify input transformation
        call_args = mock_multi_model_processor.process.call_args_list[0]
        assert call_args[0][0] == "Transform: Original content"
        
        # Verify output transformation
        assert result.final_content == "Result: Summary"


class TestChainResultAggregation:
    """Test suite for chain result aggregation."""
    
    def test_chain_result_creation(self):
        """Test ChainResult creation."""
        step_results = [
            ChainStepResult(
                step_id="step1",
                step=ChainStep(task="summarize", step_id="step1"),
                result=ProcessorResult(success=True, content="Summary", metadata={}),
                execution_time=1.0
            ),
            ChainStepResult(
                step_id="step2",
                step=ChainStep(task="enhance", step_id="step2"),
                result=ProcessorResult(success=False, content="", metadata={}, error="Failed"),
                execution_time=0.5
            )
        ]
        
        chain = ProcessingChain([ChainStep(task="test", step_id="test")])
        
        result = chain._create_chain_result(
            success=False,
            step_results=step_results,
            final_content="Final content",
            execution_time=2.0,
            error="Test error",
            failed_step="step2"
        )
        
        assert result.success is False
        assert result.final_content == "Final content"
        assert result.total_execution_time == 2.0
        assert result.error == "Test error"
        assert result.failed_step == "step2"
        assert result.total_steps == 2
        assert result.successful_steps == 1
        assert result.failed_steps == 1
        assert result.skipped_steps == 0
    
    def test_parallel_result_aggregation(self):
        """Test aggregation of parallel results."""
        parallel_results = [
            ChainStepResult(
                step_id="step1",
                step=ChainStep(task="summarize", step_id="step1", description="Summary"),
                result=ProcessorResult(success=True, content="Summary content", metadata={}),
                execution_time=1.0
            ),
            ChainStepResult(
                step_id="step2",
                step=ChainStep(task="classify", step_id="step2", description="Classification"),
                result=ProcessorResult(success=True, content="Classification content", metadata={}),
                execution_time=1.5
            )
        ]
        
        chain = ProcessingChain([ChainStep(task="test", step_id="test")])
        aggregated = chain._aggregate_parallel_results(parallel_results)
        
        assert "Summary:" in aggregated
        assert "Classification:" in aggregated
        assert "Summary content" in aggregated
        assert "Classification content" in aggregated


if __name__ == "__main__":
    pytest.main([__file__])