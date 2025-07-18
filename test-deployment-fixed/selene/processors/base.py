"""
Base processor interface for note processing pipeline.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional
import time

from ..prompts.manager import PromptTemplateManager
from ..prompts.builtin_templates import get_template_for_task, register_builtin_templates
from ..prompts.models import PromptExecutionContext
from .monitoring import get_monitor, auto_emit_stage, ProcessingStage


@dataclass
class ProcessorResult:
    """Result of note processing operation."""

    success: bool
    content: str
    metadata: Dict[str, Any]
    error: Optional[str] = None
    processing_time: Optional[float] = None
    session_id: Optional[str] = None  # For monitoring

    def to_dict(self) -> Dict[str, Any]:
        """Convert result to dictionary."""
        return {
            "success": self.success,
            "content": self.content,
            "metadata": self.metadata,
            "error": self.error,
            "processing_time": self.processing_time,
            "session_id": self.session_id,
        }


class BaseProcessor(ABC):
    """Abstract base class for note processors."""

    def __init__(self, config: Optional[Dict[str, Any]] = None):
        """Initialize processor with configuration."""
        self.config = config or {}
        
        # Initialize prompt template manager
        self.prompt_manager = PromptTemplateManager(
            storage_path=self.config.get("prompt_templates_path", "prompt_templates")
        )
        
        # Register built-in templates if not already present
        register_builtin_templates(self.prompt_manager)
        
        # Monitoring setup
        self.monitor = get_monitor()
        self.enable_monitoring = self.config.get("enable_monitoring", True)

    @abstractmethod
    async def process(self, content: str, **kwargs) -> ProcessorResult:
        """
        Process note content.

        Args:
            content: The note content to process
            **kwargs: Additional processing parameters

        Returns:
            ProcessorResult containing processed content and metadata
        """
        pass

    @abstractmethod
    def get_processor_info(self) -> Dict[str, Any]:
        """
        Get information about this processor.

        Returns:
            Dictionary with processor name, version, capabilities, etc.
        """
        pass

    def validate_input(self, content: str) -> bool:
        """
        Validate input content before processing.

        Args:
            content: Content to validate

        Returns:
            True if content is valid for processing
        """
        if not content or not content.strip():
            return False
        return True

    async def process_file(self, file_path: Path, **kwargs) -> ProcessorResult:
        """
        Process a file's content.

        Args:
            file_path: Path to file to process
            **kwargs: Additional processing parameters

        Returns:
            ProcessorResult with processed content
        """
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()

            if not self.validate_input(content):
                return ProcessorResult(
                    success=False,
                    content="",
                    metadata={"file_path": str(file_path)},
                    error="Invalid or empty file content",
                )

            result = await self.process(content, file_path=str(file_path), **kwargs)
            result.metadata["file_path"] = str(file_path)
            return result

        except Exception as e:
            return ProcessorResult(
                success=False,
                content="",
                metadata={"file_path": str(file_path)},
                error=f"Failed to process file: {str(e)}",
            )

    async def process_batch(
        self, contents: List[str], **kwargs
    ) -> List[ProcessorResult]:
        """
        Process multiple contents in batch.

        Args:
            contents: List of content strings to process
            **kwargs: Additional processing parameters

        Returns:
            List of ProcessorResults
        """
        results = []
        for i, content in enumerate(contents):
            try:
                result = await self.process(content, batch_index=i, **kwargs)
                results.append(result)
            except Exception as e:
                results.append(
                    ProcessorResult(
                        success=False,
                        content="",
                        metadata={"batch_index": i},
                        error=f"Batch processing failed: {str(e)}",
                    )
                )
        return results
    
    def get_prompt_for_task(self, task: str, content: str, **variables) -> str:
        """
        Get rendered prompt for a specific task using templates.
        
        Args:
            task: Task name (e.g., "summarize", "enhance", "extract_insights")
            content: Content to include in prompt
            **variables: Additional template variables
            
        Returns:
            Rendered prompt string
        """
        template_name = get_template_for_task(task)
        template = self.prompt_manager.get_template_by_name(template_name)
        
        if not template:
            # Fallback to simple prompt if template not found
            return f"Please {task.replace('_', ' ')} the following content:\n\n{content}"
        
        # Prepare variables
        template_vars = {"content": content}
        template_vars.update(variables)
        
        try:
            return template.render(template_vars, strict=False)
        except Exception as e:
            # Fallback if template rendering fails
            return f"Please {task.replace('_', ' ')} the following content:\n\n{content}"
    
    def log_template_usage(self, template_id: str, model_name: str, 
                          processor_type: str, variables: Dict[str, str],
                          execution_time: Optional[float] = None,
                          success: bool = True, error_message: Optional[str] = None,
                          quality_score: Optional[float] = None,
                          output_length: Optional[int] = None):
        """
        Log template usage for analytics.
        
        Args:
            template_id: Template ID used
            model_name: Model name used for processing
            processor_type: Type of processor (e.g., "ollama", "openai")
            variables: Variables used in template
            execution_time: Processing time in seconds
            success: Whether processing was successful
            error_message: Error message if failed
            quality_score: Quality score (1-5) if available
            output_length: Length of generated output
        """
        context = PromptExecutionContext(
            template_id=template_id,
            model_name=model_name,
            processor_type=processor_type,
            variables=variables,
            execution_time=execution_time,
            success=success,
            error_message=error_message,
            quality_score=quality_score,
            output_length=output_length
        )
        
        self.prompt_manager.log_execution(context)
    
    def start_monitoring_session(self, content: str, task: str, model: str) -> Optional[str]:
        """Start a monitoring session for processing."""
        if not self.enable_monitoring:
            return None
        
        processor_type = self.__class__.__name__.replace("Processor", "").lower()
        return self.monitor.start_session(content, task, model, processor_type)
    
    def emit_stage(self, session_id: Optional[str], stage: ProcessingStage, 
                  message: str, metadata: Optional[Dict[str, Any]] = None):
        """Emit a processing stage event."""
        if not self.enable_monitoring or not session_id:
            return
        
        auto_emit_stage(session_id, stage, message, metadata)
    
    def emit_streaming_token(self, session_id: Optional[str], token: str, 
                           token_count: int, is_final: bool = False,
                           total_tokens: Optional[int] = None,
                           tokens_per_second: Optional[float] = None):
        """Emit a streaming token event."""
        if not self.enable_monitoring or not session_id:
            return
        
        from .monitoring import StreamingToken
        streaming_token = StreamingToken(
            token=token,
            is_final=is_final,
            token_count=token_count,
            total_tokens=total_tokens,
            tokens_per_second=tokens_per_second
        )
        
        self.monitor.emit_streaming_token(session_id, streaming_token)
    
    def finish_monitoring_session(self, session_id: Optional[str], success: bool = True,
                                final_result: Optional[str] = None):
        """Finish a monitoring session."""
        if not self.enable_monitoring or not session_id:
            return
        
        self.monitor.finish_session(session_id, success, final_result)
