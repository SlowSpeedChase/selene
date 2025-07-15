"""
Base processor interface for note processing pipeline.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional


@dataclass
class ProcessorResult:
    """Result of note processing operation."""

    success: bool
    content: str
    metadata: Dict[str, Any]
    error: Optional[str] = None
    processing_time: Optional[float] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert result to dictionary."""
        return {
            "success": self.success,
            "content": self.content,
            "metadata": self.metadata,
            "error": self.error,
            "processing_time": self.processing_time,
        }


class BaseProcessor(ABC):
    """Abstract base class for note processors."""

    def __init__(self, config: Optional[Dict[str, Any]] = None):
        """Initialize processor with configuration."""
        self.config = config or {}

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
