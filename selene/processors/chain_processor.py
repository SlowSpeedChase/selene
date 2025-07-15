"""
Chain Processor for SMS-19 Phase 2: Advanced AI Chain Processing.

This module implements sequential and parallel AI task chaining, allowing
complex multi-step workflows with conditional branching and result aggregation.
"""

import asyncio
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional, Union

from loguru import logger

from .base import BaseProcessor, ProcessorResult
from .multi_model_processor import MultiModelProcessor


class ChainExecutionMode(Enum):
    """Execution modes for chain processing."""
    SEQUENTIAL = "sequential"
    PARALLEL = "parallel"
    CONDITIONAL = "conditional"


class ChainStepCondition(Enum):
    """Condition types for conditional branching."""
    SUCCESS = "success"
    FAILURE = "failure"
    CONTAINS = "contains"
    EQUALS = "equals"
    ALWAYS = "always"


@dataclass
class ChainStep:
    """A single step in a processing chain."""
    
    # Core step configuration
    task: str
    step_id: str
    
    # Model configuration
    model: Optional[str] = None
    processor_type: str = "multi_model"
    
    # Execution configuration
    execution_mode: ChainExecutionMode = ChainExecutionMode.SEQUENTIAL
    parallel_group: Optional[str] = None
    
    # Conditional branching
    condition: Optional[ChainStepCondition] = None
    condition_value: Optional[str] = None
    skip_on_failure: bool = False
    
    # Step metadata
    description: Optional[str] = None
    timeout: Optional[float] = None
    retry_count: int = 0
    
    # Input/output transformation
    input_transform: Optional[str] = None  # Template for input transformation
    output_transform: Optional[str] = None  # Template for output transformation
    
    # Additional processing parameters
    parameters: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ChainStepResult:
    """Result of executing a single chain step."""
    
    step_id: str
    step: ChainStep
    result: ProcessorResult
    execution_time: float
    retry_attempts: int = 0
    skipped: bool = False
    condition_met: bool = True
    
    # Parallel processing metadata
    parallel_group: Optional[str] = None
    parallel_execution_time: Optional[float] = None


@dataclass
class ChainResult:
    """Result of executing a complete processing chain."""
    
    chain_id: str
    success: bool
    total_execution_time: float
    step_results: List[ChainStepResult]
    
    # Aggregated results
    final_content: str
    aggregated_metadata: Dict[str, Any] = field(default_factory=dict)
    
    # Error information
    error: Optional[str] = None
    failed_step: Optional[str] = None
    
    # Performance metrics
    total_steps: int = 0
    successful_steps: int = 0
    failed_steps: int = 0
    skipped_steps: int = 0


class ProcessingChain:
    """
    Advanced AI processing chain that supports sequential and parallel execution,
    conditional branching, and result aggregation.
    """
    
    def __init__(self, steps: List[ChainStep], chain_id: Optional[str] = None):
        """Initialize processing chain."""
        self.chain_id = chain_id or f"chain_{int(time.time())}"
        self.steps = steps
        self.multi_model_processor = None
        
        # Validate chain configuration
        self._validate_chain()
        
        # Build execution plan
        self.execution_plan = self._build_execution_plan()
        
        logger.info(f"ProcessingChain initialized: {self.chain_id} with {len(steps)} steps")
    
    def _validate_chain(self) -> None:
        """Validate chain configuration."""
        if not self.steps:
            raise ValueError("Chain must have at least one step")
        
        # Check for duplicate step IDs
        step_ids = [step.step_id for step in self.steps]
        if len(step_ids) != len(set(step_ids)):
            raise ValueError("All step IDs must be unique")
        
        # Validate parallel groups
        parallel_groups = {}
        for step in self.steps:
            if step.parallel_group:
                if step.parallel_group not in parallel_groups:
                    parallel_groups[step.parallel_group] = []
                parallel_groups[step.parallel_group].append(step)
        
        # Ensure parallel groups have valid execution modes
        for group_name, group_steps in parallel_groups.items():
            for step in group_steps:
                if step.execution_mode != ChainExecutionMode.PARALLEL:
                    logger.warning(f"Step {step.step_id} in parallel group {group_name} should have PARALLEL execution mode")
    
    def _build_execution_plan(self) -> Dict[str, Any]:
        """Build execution plan from chain steps."""
        plan = {
            "sequential_steps": [],
            "parallel_groups": {},
            "conditional_steps": []
        }
        
        for step in self.steps:
            if step.execution_mode == ChainExecutionMode.SEQUENTIAL:
                plan["sequential_steps"].append(step)
            elif step.execution_mode == ChainExecutionMode.PARALLEL:
                group_name = step.parallel_group or "default_parallel"
                if group_name not in plan["parallel_groups"]:
                    plan["parallel_groups"][group_name] = []
                plan["parallel_groups"][group_name].append(step)
            elif step.execution_mode == ChainExecutionMode.CONDITIONAL:
                plan["conditional_steps"].append(step)
        
        return plan
    
    async def execute(self, initial_content: str, **kwargs) -> ChainResult:
        """
        Execute the processing chain.
        
        Args:
            initial_content: Initial content to process
            **kwargs: Additional parameters for processing
            
        Returns:
            ChainResult with execution results
        """
        start_time = time.time()
        step_results = []
        current_content = initial_content
        
        logger.info(f"Starting chain execution: {self.chain_id}")
        
        try:
            # Initialize multi-model processor if needed
            if not self.multi_model_processor:
                self.multi_model_processor = MultiModelProcessor()
            
            # Execute sequential steps
            for step in self.execution_plan["sequential_steps"]:
                step_result = await self._execute_step(step, current_content, **kwargs)
                step_results.append(step_result)
                
                # Update current content for next step
                if step_result.result.success and not step_result.skipped:
                    current_content = step_result.result.content
                elif not step.skip_on_failure and not step_result.result.success:
                    # Chain failed, return result
                    return self._create_chain_result(
                        success=False,
                        step_results=step_results,
                        final_content=current_content,
                        error=f"Step {step.step_id} failed: {step_result.result.error}",
                        failed_step=step.step_id,
                        execution_time=time.time() - start_time
                    )
            
            # Execute parallel groups
            for group_name, group_steps in self.execution_plan["parallel_groups"].items():
                parallel_results = await self._execute_parallel_group(
                    group_steps, current_content, **kwargs
                )
                step_results.extend(parallel_results)
                
                # Aggregate results from parallel execution
                current_content = self._aggregate_parallel_results(parallel_results)
            
            # Execute conditional steps
            for step in self.execution_plan["conditional_steps"]:
                if self._should_execute_conditional_step(step, step_results):
                    step_result = await self._execute_step(step, current_content, **kwargs)
                    step_results.append(step_result)
                    
                    if step_result.result.success and not step_result.skipped:
                        current_content = step_result.result.content
            
            # Create successful result
            return self._create_chain_result(
                success=True,
                step_results=step_results,
                final_content=current_content,
                execution_time=time.time() - start_time
            )
            
        except Exception as e:
            logger.error(f"Chain execution failed: {e}")
            return self._create_chain_result(
                success=False,
                step_results=step_results,
                final_content=current_content,
                error=str(e),
                execution_time=time.time() - start_time
            )
    
    async def _execute_step(self, step: ChainStep, content: str, **kwargs) -> ChainStepResult:
        """Execute a single chain step."""
        start_time = time.time()
        retry_attempts = 0
        
        logger.info(f"Executing step: {step.step_id} ({step.task})")
        
        # Check if step should be skipped based on conditions
        if step.condition and not self._evaluate_condition(step, content):
            logger.info(f"Step {step.step_id} skipped due to condition")
            return ChainStepResult(
                step_id=step.step_id,
                step=step,
                result=ProcessorResult(
                    success=True,
                    content=content,
                    metadata={"skipped": True, "reason": "condition_not_met"}
                ),
                execution_time=time.time() - start_time,
                skipped=True,
                condition_met=False
            )
        
        # Transform input if specified
        if step.input_transform:
            content = self._transform_content(content, step.input_transform)
        
        # Execute step with retries
        while retry_attempts <= step.retry_count:
            try:
                # Prepare processing parameters
                processing_params = {
                    "task": step.task,
                    **step.parameters,
                    **kwargs
                }
                
                # Add model if specified
                if step.model:
                    processing_params["model"] = step.model
                
                # Execute processing
                result = await self.multi_model_processor.process(content, **processing_params)
                
                # Transform output if specified
                if step.output_transform and result.success:
                    result.content = self._transform_content(result.content, step.output_transform)
                
                # Check if result is successful or we should retry
                if result.success or retry_attempts >= step.retry_count:
                    # Return result (either successful or no more retries)
                    return ChainStepResult(
                        step_id=step.step_id,
                        step=step,
                        result=result,
                        execution_time=time.time() - start_time,
                        retry_attempts=retry_attempts
                    )
                else:
                    # Failed result, retry
                    retry_attempts += 1
                    logger.warning(f"Step {step.step_id} failed (attempt {retry_attempts}): {result.error}")
                    
                    if retry_attempts <= step.retry_count:
                        # Wait before retry
                        await asyncio.sleep(0.5 * retry_attempts)
                
            except Exception as e:
                retry_attempts += 1
                logger.warning(f"Step {step.step_id} exception (attempt {retry_attempts}): {e}")
                
                if retry_attempts > step.retry_count:
                    # All retries exhausted
                    return ChainStepResult(
                        step_id=step.step_id,
                        step=step,
                        result=ProcessorResult(
                            success=False,
                            content="",
                            metadata={"error": "retry_exhausted"},
                            error=str(e)
                        ),
                        execution_time=time.time() - start_time,
                        retry_attempts=retry_attempts - 1
                    )
                
                # Wait before retry
                await asyncio.sleep(0.5 * retry_attempts)
    
    async def _execute_parallel_group(self, steps: List[ChainStep], content: str, **kwargs) -> List[ChainStepResult]:
        """Execute a group of steps in parallel."""
        logger.info(f"Executing parallel group with {len(steps)} steps")
        
        # Create tasks for parallel execution
        tasks = []
        for step in steps:
            task = self._execute_step(step, content, **kwargs)
            tasks.append(task)
        
        # Execute all tasks in parallel
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Process results
        step_results = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                # Handle exception
                step = steps[i]
                step_results.append(ChainStepResult(
                    step_id=step.step_id,
                    step=step,
                    result=ProcessorResult(
                        success=False,
                        content="",
                        metadata={"error": "parallel_execution_failed"},
                        error=str(result)
                    ),
                    execution_time=0.0,
                    parallel_group=step.parallel_group
                ))
            else:
                result.parallel_group = steps[i].parallel_group
                step_results.append(result)
        
        return step_results
    
    def _aggregate_parallel_results(self, parallel_results: List[ChainStepResult]) -> str:
        """Aggregate results from parallel execution."""
        successful_results = [r for r in parallel_results if r.result.success and not r.skipped]
        
        if not successful_results:
            return ""
        
        # Simple aggregation: combine all successful results
        combined_content = []
        for result in successful_results:
            if result.result.content:
                combined_content.append(f"**{result.step.description or result.step_id}:**\n{result.result.content}")
        
        return "\n\n".join(combined_content)
    
    def _should_execute_conditional_step(self, step: ChainStep, previous_results: List[ChainStepResult]) -> bool:
        """Determine if a conditional step should be executed."""
        if not step.condition:
            return True
        
        # For now, implement simple condition checking
        # This can be expanded with more sophisticated condition evaluation
        
        if step.condition == ChainStepCondition.ALWAYS:
            return True
        
        # Check conditions based on previous results
        if step.condition == ChainStepCondition.SUCCESS:
            return any(r.result.success for r in previous_results)
        elif step.condition == ChainStepCondition.FAILURE:
            return any(not r.result.success for r in previous_results)
        
        return True
    
    def _evaluate_condition(self, step: ChainStep, content: str) -> bool:
        """Evaluate step condition."""
        if not step.condition:
            return True
        
        if step.condition == ChainStepCondition.ALWAYS:
            return True
        elif step.condition == ChainStepCondition.CONTAINS:
            return step.condition_value in content if step.condition_value else True
        elif step.condition == ChainStepCondition.EQUALS:
            return content == step.condition_value if step.condition_value else True
        
        return True
    
    def _transform_content(self, content: str, transform_template: str) -> str:
        """Transform content using a template."""
        # Simple template transformation
        # This can be expanded with more sophisticated template processing
        return transform_template.replace("{content}", content)
    
    def _create_chain_result(self, success: bool, step_results: List[ChainStepResult], 
                           final_content: str, execution_time: float,
                           error: Optional[str] = None, failed_step: Optional[str] = None) -> ChainResult:
        """Create a chain result."""
        
        # Calculate statistics
        total_steps = len(step_results)
        successful_steps = sum(1 for r in step_results if r.result.success and not r.skipped)
        failed_steps = sum(1 for r in step_results if not r.result.success and not r.skipped)
        skipped_steps = sum(1 for r in step_results if r.skipped)
        
        # Aggregate metadata
        aggregated_metadata = {
            "chain_id": self.chain_id,
            "execution_plan": self.execution_plan,
            "step_count": total_steps,
            "performance_metrics": {
                "successful_steps": successful_steps,
                "failed_steps": failed_steps,
                "skipped_steps": skipped_steps,
                "total_execution_time": execution_time
            }
        }
        
        return ChainResult(
            chain_id=self.chain_id,
            success=success,
            total_execution_time=execution_time,
            step_results=step_results,
            final_content=final_content,
            aggregated_metadata=aggregated_metadata,
            error=error,
            failed_step=failed_step,
            total_steps=total_steps,
            successful_steps=successful_steps,
            failed_steps=failed_steps,
            skipped_steps=skipped_steps
        )
    
    def get_chain_info(self) -> Dict[str, Any]:
        """Get information about the processing chain."""
        return {
            "chain_id": self.chain_id,
            "total_steps": len(self.steps),
            "execution_plan": self.execution_plan,
            "steps": [
                {
                    "step_id": step.step_id,
                    "task": step.task,
                    "execution_mode": step.execution_mode.value,
                    "parallel_group": step.parallel_group,
                    "condition": step.condition.value if step.condition else None,
                    "description": step.description
                }
                for step in self.steps
            ]
        }