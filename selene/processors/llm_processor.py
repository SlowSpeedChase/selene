"""
LLM-based note processor using OpenAI API.
"""

import time
from typing import Dict, Any, Optional
from openai import AsyncOpenAI
from loguru import logger

from .base import BaseProcessor, ProcessorResult


class LLMProcessor(BaseProcessor):
    """
    Note processor that uses Large Language Models for content enhancement.
    
    Features:
    - Content summarization
    - Key insight extraction
    - Content enhancement and expansion
    - Question generation
    - Topic classification
    """
    
    def __init__(self, config: Optional[Dict[str, Any]] = None):
        """Initialize LLM processor with OpenAI configuration."""
        super().__init__(config)
        
        self.api_key = self.config.get("openai_api_key")
        self.model = self.config.get("model", "gpt-4o-mini")
        self.max_tokens = self.config.get("max_tokens", 1000)
        self.temperature = self.config.get("temperature", 0.7)
        
        if not self.api_key:
            raise ValueError("OpenAI API key is required in config")
        
        self.client = AsyncOpenAI(api_key=self.api_key)
    
    async def process(self, content: str, **kwargs) -> ProcessorResult:
        """
        Process note content using LLM.
        
        Args:
            content: The note content to process
            **kwargs: Processing parameters:
                - task: Processing task ("summarize", "enhance", "extract_insights", "questions")
                - prompt: Custom prompt override
                - model: Model override
                
        Returns:
            ProcessorResult with LLM-processed content
        """
        start_time = time.time()
        
        if not self.validate_input(content):
            return ProcessorResult(
                success=False,
                content="",
                metadata={},
                error="Invalid or empty content"
            )
        
        try:
            task = kwargs.get("task", "enhance")
            custom_prompt = kwargs.get("prompt")
            model = kwargs.get("model", self.model)
            
            if custom_prompt:
                prompt = custom_prompt
            else:
                prompt = self._get_task_prompt(task)
            
            response = await self.client.chat.completions.create(
                model=model,
                messages=[
                    {"role": "system", "content": prompt},
                    {"role": "user", "content": content}
                ],
                max_tokens=self.max_tokens,
                temperature=self.temperature
            )
            
            processed_content = response.choices[0].message.content
            processing_time = time.time() - start_time
            
            metadata = {
                "task": task,
                "model": model,
                "tokens_used": response.usage.total_tokens if response.usage else 0,
                "prompt_tokens": response.usage.prompt_tokens if response.usage else 0,
                "completion_tokens": response.usage.completion_tokens if response.usage else 0,
                "original_length": len(content),
                "processed_length": len(processed_content),
                **{k: v for k, v in kwargs.items() if k not in ["task", "prompt", "model"]}
            }
            
            logger.info(f"LLM processing completed: {task} task, {processing_time:.2f}s, {metadata['tokens_used']} tokens")
            
            return ProcessorResult(
                success=True,
                content=processed_content,
                metadata=metadata,
                processing_time=processing_time
            )
            
        except Exception as e:
            processing_time = time.time() - start_time
            error_msg = f"LLM processing failed: {str(e)}"
            logger.error(error_msg)
            
            return ProcessorResult(
                success=False,
                content="",
                metadata={"task": kwargs.get("task", "enhance")},
                error=error_msg,
                processing_time=processing_time
            )
    
    def _get_task_prompt(self, task: str) -> str:
        """Get system prompt for specific processing task."""
        prompts = {
            "summarize": (
                "You are an expert at creating concise, insightful summaries. "
                "Summarize the provided note content, capturing the key points and main ideas. "
                "Keep the summary clear and well-structured."
            ),
            "enhance": (
                "You are an expert note-taking assistant. Enhance the provided note content by: "
                "1. Improving clarity and structure "
                "2. Adding relevant context where helpful "
                "3. Organizing information logically "
                "4. Maintaining the original intent and voice "
                "Return the enhanced version of the note."
            ),
            "extract_insights": (
                "You are an expert analyst. Extract key insights, patterns, and important "
                "takeaways from the provided note content. Focus on: "
                "1. Main insights and conclusions "
                "2. Important patterns or trends "
                "3. Actionable items "
                "4. Key relationships between ideas "
                "Present your analysis in a clear, structured format."
            ),
            "questions": (
                "You are an expert at generating thoughtful questions. Based on the provided "
                "note content, generate relevant questions that could: "
                "1. Deepen understanding of the topic "
                "2. Explore implications and connections "
                "3. Identify areas for further research "
                "4. Challenge assumptions or explore alternatives "
                "Provide 5-10 thought-provoking questions."
            ),
            "classify": (
                "You are an expert content classifier. Analyze the provided note content and "
                "classify it by: "
                "1. Main topic/subject area "
                "2. Content type (research, meeting notes, ideas, etc.) "
                "3. Key themes and categories "
                "4. Suggested tags for organization "
                "Provide a structured classification with explanations."
            )
        }
        
        return prompts.get(task, prompts["enhance"])
    
    def get_processor_info(self) -> Dict[str, Any]:
        """Get information about this LLM processor."""
        return {
            "name": "LLM Processor",
            "version": "1.0.0",
            "model": self.model,
            "capabilities": [
                "content_summarization",
                "content_enhancement", 
                "insight_extraction",
                "question_generation",
                "topic_classification"
            ],
            "supported_tasks": [
                "summarize",
                "enhance", 
                "extract_insights",
                "questions",
                "classify"
            ],
            "max_tokens": self.max_tokens,
            "temperature": self.temperature
        }