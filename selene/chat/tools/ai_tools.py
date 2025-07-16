"""
AI processing tools for SELENE chatbot agent.
These tools integrate with the existing AI processing capabilities.
"""

from typing import List, Optional

from loguru import logger

from ...processors.ollama_processor import OllamaProcessor
from .base import BaseTool, ToolParameter, ToolResult, ToolStatus


class ProcessNoteTool(BaseTool):
    """Tool for AI processing of note content."""
    
    def __init__(self):
        super().__init__()
        self.processor = None
        
    @property
    def name(self) -> str:
        return "ai_process"
        
    @property
    def description(self) -> str:
        return "Process note content with AI (enhance, summarize, extract insights, generate questions)"
        
    @property
    def parameters(self) -> List[ToolParameter]:
        return [
            ToolParameter(
                name="content",
                type="string",
                description="Content to process",
                required=True
            ),
            ToolParameter(
                name="task",
                type="string",
                description="AI processing task to perform",
                required=True,
                enum=["enhance", "summarize", "extract_insights", "questions", "classify"]
            ),
            ToolParameter(
                name="model",
                type="string",
                description="AI model to use",
                required=False,
                default="llama3.2:1b"
            ),
            ToolParameter(
                name="temperature",
                type="float",
                description="Creativity level (0.0 to 1.0)",
                required=False,
                default=0.7
            )
        ]
        
    async def execute(self, **kwargs) -> ToolResult:
        content = kwargs.get("content")
        task = kwargs.get("task")
        model = kwargs.get("model", "llama3.2:1b")
        temperature = kwargs.get("temperature", 0.7)
        
        try:
            # Initialize processor if needed
            if not self.processor:
                self.processor = OllamaProcessor()
                
            # Process the content
            result = await self.processor.process(
                content=content,
                task=task,
                model=model
            )
            
            if result.success:
                return ToolResult(
                    status=ToolStatus.SUCCESS,
                    content=result.content,
                    metadata={
                        "task": task,
                        "model": model,
                        "processing_time": result.metadata.get("processing_time"),
                        "input_tokens": result.metadata.get("input_tokens"),
                        "output_tokens": result.metadata.get("output_tokens"),
                        "original_length": len(content),
                        "processed_length": len(result.content)
                    }
                )
            else:
                return ToolResult(
                    status=ToolStatus.ERROR,
                    error_message=f"AI processing failed: {result.error}"
                )
                
        except Exception as e:
            logger.error(f"AI processing tool failed: {e}")
            return ToolResult(
                status=ToolStatus.ERROR,
                error_message=f"AI processing failed: {e}"
            )