"""
Multi-model processor for advanced AI features.
Supports multiple models, task routing, and model comparison.
"""

import asyncio
import time
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple, Union

from loguru import logger

from .base import BaseProcessor, ProcessorResult
from .ollama_processor import OllamaProcessor
from .llm_processor import LLMProcessor


@dataclass
class ModelConfig:
    """Configuration for a model in the multi-model system."""
    name: str
    type: str  # "ollama" or "openai"
    config: Dict[str, Any]
    tasks: List[str]  # Tasks this model is optimized for
    priority: int = 1  # Lower = higher priority
    max_concurrent: int = 1  # Max concurrent requests
    enabled: bool = True


@dataclass
class ModelComparisonResult:
    """Result of comparing multiple models on the same task."""
    task: str
    content: str
    model_results: List[Tuple[str, ProcessorResult]]  # (model_name, result)
    best_model: Optional[str] = None
    processing_time: float = 0.0
    comparison_metadata: Dict[str, Any] = None


class MultiModelProcessor(BaseProcessor):
    """
    Advanced processor that manages multiple AI models.
    
    Features:
    - Model pool management
    - Task-specific model routing
    - Model comparison and benchmarking
    - Fallback chains for reliability
    - Performance monitoring
    """
    
    def __init__(self, config: Optional[Dict[str, Any]] = None):
        """Initialize multi-model processor."""
        super().__init__(config)
        
        # Model pool and configuration
        self.models: Dict[str, BaseProcessor] = {}
        self.model_configs: Dict[str, ModelConfig] = {}
        self.routing_rules: Dict[str, str] = {}  # task -> preferred model
        
        # Performance tracking
        self.model_stats: Dict[str, Dict[str, Any]] = {}
        
        # Load configuration
        self._load_model_configs()
        
        # Initialize models later (lazy initialization)
        self._models_initialized = False
    
    def _load_model_configs(self) -> None:
        """Load model configurations from config."""
        model_configs = self.config.get("models", [])
        
        # Default configuration if none provided
        if not model_configs:
            model_configs = [
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
                }
            ]
        
        # Parse configurations
        for config_data in model_configs:
            model_config = ModelConfig(**config_data)
            self.model_configs[model_config.name] = model_config
            
            # Initialize stats
            self.model_stats[model_config.name] = {
                "total_requests": 0,
                "successful_requests": 0,
                "failed_requests": 0,
                "avg_processing_time": 0.0,
                "last_used": None
            }
        
        # Build routing rules (task -> preferred model)
        self._build_routing_rules()
        
        logger.info(f"Loaded {len(self.model_configs)} model configurations")
    
    def _build_routing_rules(self) -> None:
        """Build routing rules based on model configurations."""
        self.routing_rules = {}
        
        # Group models by task and sort by priority
        task_models = {}
        for model_name, config in self.model_configs.items():
            if not config.enabled:
                continue
                
            for task in config.tasks:
                if task not in task_models:
                    task_models[task] = []
                task_models[task].append((model_name, config.priority))
        
        # Select best model for each task
        for task, models in task_models.items():
            # Sort by priority (lower = higher priority)
            models.sort(key=lambda x: x[1])
            if models:
                self.routing_rules[task] = models[0][0]
        
        logger.info(f"Built routing rules for {len(self.routing_rules)} tasks")
    
    async def _ensure_models_initialized(self) -> None:
        """Ensure all models are initialized (lazy initialization)."""
        if self._models_initialized:
            return
            
        await self._initialize_models()
        self._models_initialized = True
    
    async def _initialize_models(self) -> None:
        """Initialize all configured models."""
        for model_name, config in self.model_configs.items():
            if not config.enabled:
                continue
                
            # Skip initialization if model is already set (for tests)
            if model_name in self.models:
                logger.info(f"Model {model_name} already initialized (skipping)")
                continue
                
            try:
                if config.type == "ollama":
                    processor = OllamaProcessor(config.config)
                elif config.type == "openai":
                    processor = LLMProcessor(config.config)
                else:
                    logger.error(f"Unknown model type: {config.type}")
                    continue
                
                self.models[model_name] = processor
                logger.info(f"Initialized model: {model_name}")
                
            except Exception as e:
                logger.error(f"Failed to initialize model {model_name}: {e}")
                config.enabled = False
    
    async def process(self, content: str, **kwargs) -> ProcessorResult:
        """
        Process content using the multi-model system.
        
        Args:
            content: Content to process
            **kwargs: Processing parameters including:
                - task: Processing task
                - model: Specific model to use (optional)
                - compare_models: List of models to compare (optional)
                - fallback: Enable fallback chain (default: True)
        
        Returns:
            ProcessorResult with processing results
        """
        start_time = time.time()
        task = kwargs.get("task", "enhance")
        
        # Remove task from kwargs to avoid duplicate parameter issues
        filtered_kwargs = {k: v for k, v in kwargs.items() if k != "task"}
        
        # Ensure models are initialized
        await self._ensure_models_initialized()
        
        # Handle model comparison
        if kwargs.get("compare_models"):
            return await self._compare_models(content, task, kwargs["compare_models"], **filtered_kwargs)
        
        # Handle specific model request
        if kwargs.get("model"):
            return await self._process_with_model(content, kwargs["model"], task, **filtered_kwargs)
        
        # Handle routing with fallback
        return await self._process_with_routing(content, task, **filtered_kwargs)
    
    async def _process_with_routing(self, content: str, task: str, **kwargs) -> ProcessorResult:
        """Process content using task routing with fallback."""
        # Get preferred model for task
        preferred_model = self.routing_rules.get(task)
        
        if not preferred_model:
            return ProcessorResult(
                success=False,
                content="",
                metadata={"task": task, "error": "no_model_for_task"},
                error=f"No model configured for task: {task}",
                processing_time=0.0
            )
        
        # Try preferred model
        result = await self._process_with_model(content, preferred_model, task, **kwargs)
        
        # If failed and fallback enabled, try other models
        if not result.success and kwargs.get("fallback", True):
            result = await self._try_fallback_models(content, task, preferred_model, **kwargs)
        
        return result
    
    async def _process_with_model(self, content: str, model_name: str, task: str, **kwargs) -> ProcessorResult:
        """Process content with a specific model."""
        start_time = time.time()
        
        # Check if model exists and is enabled
        if model_name not in self.models:
            return ProcessorResult(
                success=False,
                content="",
                metadata={"task": task, "model": model_name, "error": "model_not_found"},
                error=f"Model not found: {model_name}",
                processing_time=0.0
            )
        
        processor = self.models[model_name]
        
        try:
            # Update stats
            self.model_stats[model_name]["total_requests"] += 1
            self.model_stats[model_name]["last_used"] = time.time()
            
            # Process with the model
            result = await processor.process(content, task=task, **kwargs)
            
            # Update success stats
            processing_time = time.time() - start_time
            
            if result.success:
                self.model_stats[model_name]["successful_requests"] += 1
            else:
                self.model_stats[model_name]["failed_requests"] += 1
            
            # Update average processing time
            stats = self.model_stats[model_name]
            total_requests = stats["total_requests"]
            current_avg = stats["avg_processing_time"]
            stats["avg_processing_time"] = (current_avg * (total_requests - 1) + processing_time) / total_requests
            
            # Add multi-model metadata
            result.metadata.update({
                "multi_model_processor": True,
                "selected_model": model_name,
                "routing_used": True,
                "model_stats": self.model_stats[model_name].copy()
            })
            
            return result
            
        except Exception as e:
            self.model_stats[model_name]["failed_requests"] += 1
            logger.error(f"Error processing with model {model_name}: {e}")
            
            return ProcessorResult(
                success=False,
                content="",
                metadata={"task": task, "model": model_name, "error": "processing_failed"},
                error=f"Processing failed with model {model_name}: {str(e)}",
                processing_time=time.time() - start_time
            )
    
    async def _try_fallback_models(self, content: str, task: str, failed_model: str, **kwargs) -> ProcessorResult:
        """Try fallback models when primary model fails."""
        # Get all models that can handle this task
        fallback_models = []
        for model_name, config in self.model_configs.items():
            if (config.enabled and 
                task in config.tasks and 
                model_name != failed_model and
                model_name in self.models):
                fallback_models.append((model_name, config.priority))
        
        # Sort by priority
        fallback_models.sort(key=lambda x: x[1])
        
        logger.info(f"Trying {len(fallback_models)} fallback models for task: {task}")
        
        # Try each fallback model
        for model_name, _ in fallback_models:
            result = await self._process_with_model(content, model_name, task, **kwargs)
            
            if result.success:
                result.metadata.update({
                    "fallback_used": True,
                    "failed_model": failed_model,
                    "fallback_model": model_name
                })
                return result
        
        # All models failed
        return ProcessorResult(
            success=False,
            content="",
            metadata={"task": task, "error": "all_models_failed"},
            error=f"All models failed for task: {task}",
            processing_time=0.0
        )
    
    async def _compare_models(self, content: str, task: str, model_names: List[str], **kwargs) -> ProcessorResult:
        """Compare multiple models on the same task."""
        start_time = time.time()
        
        # Process with all specified models
        tasks = []
        for model_name in model_names:
            if model_name in self.models:
                tasks.append(self._process_with_model(content, model_name, task, **kwargs))
        
        # Run all models in parallel
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Process results
        model_results = []
        successful_results = []
        
        for i, result in enumerate(results):
            model_name = model_names[i]
            
            if isinstance(result, Exception):
                # Handle exceptions
                error_result = ProcessorResult(
                    success=False,
                    content="",
                    metadata={"task": task, "model": model_name},
                    error=str(result),
                    processing_time=0.0
                )
                model_results.append((model_name, error_result))
            else:
                model_results.append((model_name, result))
                if result.success:
                    successful_results.append((model_name, result))
        
        # Determine best model (for now, just use first successful one)
        best_model = None
        best_result = None
        
        if successful_results:
            # For now, use the first successful result
            # TODO: Implement more sophisticated ranking
            best_model, best_result = successful_results[0]
        
        # Create comparison result
        comparison_result = ModelComparisonResult(
            task=task,
            content=content,
            model_results=model_results,
            best_model=best_model,
            processing_time=time.time() - start_time,
            comparison_metadata={
                "total_models": len(model_names),
                "successful_models": len(successful_results),
                "failed_models": len(model_names) - len(successful_results)
            }
        )
        
        # Return the best result with comparison metadata
        if best_result:
            best_result.metadata.update({
                "comparison_result": comparison_result,
                "models_compared": model_names,
                "best_model": best_model
            })
            return best_result
        else:
            return ProcessorResult(
                success=False,
                content="",
                metadata={"task": task, "error": "all_models_failed_comparison"},
                error=f"All models failed in comparison for task: {task}",
                processing_time=comparison_result.processing_time
            )
    
    def get_model_stats(self) -> Dict[str, Dict[str, Any]]:
        """Get statistics for all models."""
        return self.model_stats.copy()
    
    def get_available_models(self) -> List[str]:
        """Get list of available model names."""
        return list(self.models.keys())
    
    def get_tasks_for_model(self, model_name: str) -> List[str]:
        """Get tasks that a model can handle."""
        if model_name in self.model_configs:
            return self.model_configs[model_name].tasks.copy()
        return []
    
    def get_model_for_task(self, task: str) -> Optional[str]:
        """Get the preferred model for a specific task."""
        return self.routing_rules.get(task)
    
    def get_processor_info(self) -> Dict[str, Any]:
        """Get information about this processor."""
        return {
            "name": "MultiModelProcessor",
            "version": "1.0.0",
            "description": "Advanced processor with multiple AI models",
            "capabilities": [
                "multi_model_processing",
                "task_routing",
                "model_comparison",
                "fallback_chains",
                "performance_monitoring"
            ],
            "models": {
                name: {
                    "type": config.type,
                    "tasks": config.tasks,
                    "priority": config.priority,
                    "enabled": config.enabled
                }
                for name, config in self.model_configs.items()
            },
            "routing_rules": self.routing_rules.copy(),
            "model_stats": self.get_model_stats()
        }