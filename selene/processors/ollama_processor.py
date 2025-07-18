"""
Ollama-based note processor for local AI processing.
"""

import time
from typing import Any, Dict, List, Optional

import httpx
from loguru import logger

from .base import BaseProcessor, ProcessorResult
from ..prompts.builtin_templates import get_template_for_task
from .monitoring import ProcessingStage
from ..connection.ollama_manager import OllamaConnectionManager, OllamaConfig


class OllamaProcessor(BaseProcessor):
    """
    Note processor that uses Ollama for local LLM processing.

    Features:
    - Completely local processing (no API keys needed)
    - Privacy-focused (data never leaves your machine)
    - Supports multiple local models (llama3.2, mistral, etc.)
    - No usage costs or rate limits
    """

    def __init__(self, config: Optional[Dict[str, Any]] = None):
        """Initialize Ollama processor with connection manager."""
        super().__init__(config)

        self.model = self.config.get("model", "llama3.2")
        self.max_tokens = self.config.get("max_tokens", 1000)
        self.temperature = self.config.get("temperature", 0.7)
        self.validate_on_init = self.config.get("validate_on_init", True)

        # Create connection manager configuration
        ollama_config = OllamaConfig(
            base_url=self.config.get("base_url", "http://localhost:11434"),
            timeout=self.config.get("timeout", 120.0),
            max_connections=self.config.get("max_connections", 10),
            health_check_interval=self.config.get("health_check_interval", 30),
            max_retries=self.config.get("max_retries", 3),
            retry_delay=self.config.get("retry_delay", 1.0),
            connection_timeout=self.config.get("connection_timeout", 10.0),
            read_timeout=self.config.get("read_timeout", 60.0),
            validate_on_init=self.validate_on_init
        )

        # Initialize connection manager
        self.connection_manager = OllamaConnectionManager(ollama_config)
        self._manager_started = False

        # For backward compatibility
        self.base_url = ollama_config.base_url
        self.timeout = ollama_config.timeout

    async def _ensure_connection_manager(self):
        """Ensure connection manager is started."""
        if not self._manager_started:
            await self.connection_manager.start()
            self._manager_started = True

    async def get_client(self) -> httpx.AsyncClient:
        """Get HTTP client from connection manager."""
        await self._ensure_connection_manager()
        return await self.connection_manager.get_client()

    async def process(self, content: str, **kwargs) -> ProcessorResult:
        """
        Process note content using local Ollama LLM.

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
        
        # Start monitoring session
        task = kwargs.get("task", "enhance")
        model = kwargs.get("model", self.model)
        session_id = self.start_monitoring_session(content, task, model)
        
        # Emit validation stage
        self.emit_stage(session_id, ProcessingStage.VALIDATING_INPUT, "Validating input content")
        
        if not self.validate_input(content):
            self.emit_stage(session_id, ProcessingStage.FAILED, "Input validation failed", 
                          error="Invalid or empty content")
            return ProcessorResult(
                success=False, content="", metadata={}, error="Invalid or empty content",
                session_id=session_id
            )

        try:
            custom_prompt = kwargs.get("prompt")
            template_id = kwargs.get("template_id")
            # Use self.model (which may have been updated by validation) unless explicitly overridden
            model = kwargs.get("model", self.model)
            
            # Emit template resolution stage
            self.emit_stage(session_id, ProcessingStage.RESOLVING_TEMPLATE, "Resolving prompt template")

            # Get prompt using template system or fallback
            if custom_prompt:
                full_prompt = custom_prompt
                used_template_id = None
            elif template_id:
                # Use specific template
                template = self.prompt_manager.get_template(template_id)
                if template:
                    template_vars = {"content": content}
                    template_vars.update(kwargs.get("template_variables", {}))
                    full_prompt = template.render(template_vars, strict=False)
                    used_template_id = template_id
                else:
                    # Fallback if template not found
                    template_vars = {k: v for k, v in kwargs.items() 
                                   if k not in ["task", "prompt", "model", "template_id", "template_variables"]}
                    full_prompt = self.get_prompt_for_task(task, content, **template_vars)
                    used_template_id = None
            else:
                # Use default template for task
                # Filter out conflicting parameters
                template_vars = {k: v for k, v in kwargs.items() 
                               if k not in ["task", "prompt", "model", "template_id", "template_variables"]}
                full_prompt = self.get_prompt_for_task(task, content, **template_vars)
                template_name = get_template_for_task(task)
                template = self.prompt_manager.get_template_by_name(template_name)
                used_template_id = template.id if template else None

            # Emit prompt generation stage
            self.emit_stage(session_id, ProcessingStage.GENERATING_PROMPT, 
                          f"Generated prompt ({len(full_prompt)} characters)",
                          {"prompt_length": len(full_prompt), "template_id": used_template_id})
            
            # Emit connection stage
            self.emit_stage(session_id, ProcessingStage.CONNECTING_TO_MODEL, 
                          f"Connecting to Ollama model: {model}")

            # Make request to Ollama
            payload = {
                "model": model,
                "prompt": full_prompt,
                "stream": False,
                "options": {
                    "temperature": self.temperature,
                    "num_predict": self.max_tokens,
                },
            }

            # Emit request sending stage
            self.emit_stage(session_id, ProcessingStage.SENDING_REQUEST, 
                          f"Sending request to {model}")
            
            client = await self.get_client()
            response = await client.post("/api/generate", json=payload)
            response.raise_for_status()

            # Emit response processing stage
            self.emit_stage(session_id, ProcessingStage.PROCESSING_RESPONSE, 
                          "Processing LLM response")
            
            result_data = response.json()
            processed_content = result_data.get("response", "").strip()

            processing_time = time.time() - start_time

            # Calculate approximate token usage (rough estimate)
            input_tokens = len(full_prompt.split())
            output_tokens = len(processed_content.split())
            total_tokens = input_tokens + output_tokens

            metadata = {
                "task": task,
                "model": model,
                "estimated_tokens": total_tokens,
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
                "original_length": len(content),
                "processed_length": len(processed_content),
                "base_url": self.base_url,
                "processor_type": "ollama_local",
                **{
                    k: v
                    for k, v in kwargs.items()
                    if k not in ["task", "prompt", "model"]
                },
            }

            # Emit final metadata collection stage
            self.emit_stage(session_id, ProcessingStage.COLLECTING_METADATA, 
                          f"Collected metadata: {total_tokens} tokens, {processing_time:.2f}s")
            
            logger.info(
                f"Ollama processing completed: {task} task, {processing_time:.2f}s, ~{total_tokens} tokens, model: {model}"
            )

            # Log template usage for analytics
            if used_template_id:
                template_vars = {"content": content}
                template_vars.update(kwargs.get("template_variables", {}))
                self.log_template_usage(
                    template_id=used_template_id,
                    model_name=model,
                    processor_type="ollama",
                    variables=template_vars,
                    execution_time=processing_time,
                    success=True,
                    output_length=len(processed_content)
                )

            # Finish monitoring session
            self.finish_monitoring_session(session_id, success=True, final_result=processed_content)

            return ProcessorResult(
                success=True,
                content=processed_content,
                metadata=metadata,
                processing_time=processing_time,
                session_id=session_id,
            )

        except httpx.ConnectError:
            processing_time = time.time() - start_time
            error_msg = (
                f"Failed to connect to Ollama at {self.base_url}. "
                "Make sure Ollama is running: 'ollama serve'"
            )
            logger.error(error_msg)
            
            # Mark connection as unhealthy in manager
            try:
                await self.connection_manager._handle_connection_error("default", error_msg)
            except Exception:
                pass  # Don't let connection manager errors affect main error handling

            self.finish_monitoring_session(session_id, success=False)
            return ProcessorResult(
                success=False,
                content="",
                metadata={
                    "task": kwargs.get("task", "enhance"),
                    "processor_type": "ollama_local",
                },
                error=error_msg,
                processing_time=processing_time,
                session_id=session_id,
            )

        except httpx.HTTPStatusError as e:
            processing_time = time.time() - start_time
            error_msg = (
                f"Ollama HTTP error: {e.response.status_code} - {e.response.text}"
            )
            logger.error(error_msg)

            self.finish_monitoring_session(session_id, success=False)
            return ProcessorResult(
                success=False,
                content="",
                metadata={
                    "task": kwargs.get("task", "enhance"),
                    "processor_type": "ollama_local",
                },
                error=error_msg,
                processing_time=processing_time,
                session_id=session_id,
            )

        except Exception as e:
            processing_time = time.time() - start_time
            error_msg = f"Ollama processing failed: {str(e)}"
            logger.error(error_msg)

            self.finish_monitoring_session(session_id, success=False)
            return ProcessorResult(
                success=False,
                content="",
                metadata={
                    "task": kwargs.get("task", "enhance"),
                    "processor_type": "ollama_local",
                },
                error=error_msg,
                processing_time=processing_time,
                session_id=session_id,
            )

    def _get_task_prompt(self, task: str) -> str:
        """Get system prompt for specific processing task (optimized for local models)."""
        prompts = {
            "summarize": (
                "You are a helpful assistant that creates clear, concise summaries. "
                "Summarize the following content, capturing the key points and main ideas. "
                "Keep the summary well-structured and focused."
            ),
            "enhance": (
                "You are a helpful assistant that improves note quality. "
                "Enhance the following content by: "
                "1. Improving clarity and organization "
                "2. Adding structure where helpful "
                "3. Maintaining the original meaning "
                "Return the enhanced version."
            ),
            "extract_insights": (
                "You are a helpful assistant that analyzes content for insights. "
                "Extract key insights from the following content. Focus on: "
                "1. Main conclusions and takeaways "
                "2. Important patterns "
                "3. Actionable items "
                "Present insights in a clear, organized way."
            ),
            "questions": (
                "You are a helpful assistant that generates thoughtful questions. "
                "Based on the following content, generate 5-7 relevant questions that: "
                "1. Deepen understanding "
                "2. Explore implications "
                "3. Identify areas for further thought "
                "List the questions clearly."
            ),
            "classify": (
                "You are a helpful assistant that categorizes content. "
                "Analyze the following content and provide: "
                "1. Main topic/category "
                "2. Content type "
                "3. Key themes "
                "4. Suggested tags "
                "Present the classification clearly."
            ),
        }

        return prompts.get(task, prompts["enhance"])

    def _validate_ollama_setup(self) -> None:
        """
        Validate Ollama setup during initialization.
        Provides helpful error messages if setup is incomplete.
        """
        import asyncio

        try:
            # Check if we can connect to Ollama using connection manager
            async def validate():
                try:
                    await self._ensure_connection_manager()
                    
                    # Use connection manager for health check
                    health_check_result = await self.connection_manager.health_check()
                    
                    if health_check_result:
                        available_models = await self.connection_manager.get_available_models()
                        return {
                            "connected": True,
                            "base_url": self.base_url,
                            "available_models": available_models,
                            "current_model": self.model,
                            "model_available": self.model in available_models,
                        }
                    else:
                        connection_info = await self.connection_manager.get_connection_info()
                        default_info = connection_info.get("default", {})
                        return {
                            "connected": False,
                            "base_url": self.base_url,
                            "error": default_info.get("last_error", "Unknown error"),
                            "suggestion": "Run 'ollama serve' to start Ollama",
                        }
                        
                except Exception as e:
                    return {
                        "connected": False,
                        "base_url": self.base_url,
                        "error": str(e),
                        "suggestion": "Run 'ollama serve' to start Ollama",
                    }

            # Check if we're in an event loop already
            try:
                loop = asyncio.get_running_loop()
                # We're already in an event loop, skip validation to avoid conflicts
                logger.warning("Skipping Ollama validation (running in event loop context)")
                return
            except RuntimeError:
                # No event loop running, safe to use asyncio.run
                connection_info = asyncio.run(validate())

            if not connection_info.get("connected"):
                error_msg = connection_info.get("error", "Unknown connection error")
                self._raise_setup_error("connection", error_msg)

            # Check if the default model is available, or select best alternative
            available_models = connection_info.get("available_models", [])
            if available_models and self.model not in available_models:
                # Try to find a good alternative
                fallback_model = self._find_best_available_model(available_models)
                if fallback_model:
                    logger.warning(
                        f"⚠️  Model '{self.model}' not found, using '{fallback_model}' instead"
                    )
                    self.model = fallback_model
                else:
                    self._raise_setup_error(
                        "model", f"Model '{self.model}' not found", available_models
                    )

            logger.info(
                f"✅ Ollama validation successful: {len(available_models)} models available, using {self.model}"
            )

        except Exception as e:
            # If validation fails completely, provide helpful guidance
            self._raise_setup_error("validation", str(e))

    def _raise_setup_error(
        self, error_type: str, details: str, available_models: list = None
    ) -> None:
        """Raise a helpful setup error with actionable instructions."""

        if error_type == "connection":
            message = f"""
❌ Cannot connect to Ollama at {self.base_url}

🔧 Quick Setup Guide:
1. Install Ollama: https://ollama.ai/download
2. Start Ollama service: 'ollama serve'
3. Pull a model: 'ollama pull llama3.2'
4. Try again: 'selene process --content "test"'

💡 Alternative: Use cloud processor with --processor openai --api-key YOUR_KEY

Details: {details}
            """.strip()

        elif error_type == "model":
            available_str = ", ".join(available_models) if available_models else "none"
            message = f"""
❌ Model '{self.model}' not found in Ollama

📦 Available models: {available_str}

🔧 Quick Fix:
1. Pull the model: 'ollama pull {self.model}'
2. Or use available model: 'selene process --model {available_models[0] if available_models else "llama3.2"} --content "test"'
3. Or list all models: 'ollama list'

💡 Recommended models: llama3.2 (fast), mistral (high quality)
            """.strip()

        else:  # validation error
            message = f"""
❌ Ollama setup validation failed

🔧 Setup Steps:
1. Install Ollama: https://ollama.ai/download  
2. Start service: 'ollama serve'
3. Pull a model: 'ollama pull llama3.2'
4. Check status: 'ollama list'

💡 Or use cloud: 'selene process --processor openai --api-key YOUR_KEY --content "test"'

Error details: {details}
            """.strip()

        raise RuntimeError(message)

    def _find_best_available_model(self, available_models: List[str]) -> Optional[str]:
        """
        Find the best available model from the available list.
        Prioritizes models by performance and size.
        """
        # Model preference order (best to fallback)
        preference_order = [
            # Llama family (recommended)
            "llama3.2",
            "llama3.2:3b",
            "llama3.1",
            "llama3.1:8b",
            "llama3",
            "llama3.2:1b",
            "llama2",
            # Other good models
            "mistral",
            "mistral:7b",
            "mixtral",
            "phi3",
            "phi3:mini",
            "qwen2",
            "gemma",
            "codellama",
            # Lightweight fallbacks
            "tinyllama",
            "phi",
            "orca-mini",
        ]

        # First try exact matches
        for preferred in preference_order:
            if preferred in available_models:
                return preferred

        # Then try partial matches (e.g., llama3.2:latest matches llama3.2)
        for preferred in preference_order:
            for available in available_models:
                if (
                    available.startswith(preferred + ":")
                    or preferred in available.lower()
                ):
                    return available

        # If no preferred models, return the first available
        return available_models[0] if available_models else None

    def get_processor_info(self) -> Dict[str, Any]:
        """Get information about this Ollama processor."""
        return {
            "name": "Ollama Local Processor",
            "version": "1.0.0",
            "model": self.model,
            "base_url": self.base_url,
            "processor_type": "local",
            "capabilities": [
                "content_summarization",
                "content_enhancement",
                "insight_extraction",
                "question_generation",
                "topic_classification",
            ],
            "supported_tasks": [
                "summarize",
                "enhance",
                "extract_insights",
                "questions",
                "classify",
            ],
            "max_tokens": self.max_tokens,
            "temperature": self.temperature,
            "privacy": "local_only",
            "cost": "free",
            "requires_internet": False,
        }

    async def check_connection(self) -> Dict[str, Any]:
        """Check if Ollama is running and accessible."""
        try:
            await self._ensure_connection_manager()
            
            # Use connection manager for health check
            health_check_result = await self.connection_manager.health_check()
            
            if health_check_result:
                available_models = await self.connection_manager.get_available_models()
                return {
                    "connected": True,
                    "base_url": self.base_url,
                    "available_models": available_models,
                    "current_model": self.model,
                    "model_available": self.model in available_models,
                }
            else:
                connection_info = await self.connection_manager.get_connection_info()
                default_info = connection_info.get("default", {})
                return {
                    "connected": False,
                    "base_url": self.base_url,
                    "error": default_info.get("last_error", "Unknown error"),
                    "suggestion": "Run 'ollama serve' to start Ollama",
                }

        except Exception as e:
            return {
                "connected": False,
                "base_url": self.base_url,
                "error": str(e),
                "suggestion": "Run 'ollama serve' to start Ollama",
            }

    async def pull_model(self, model_name: str) -> Dict[str, Any]:
        """Pull/download a model if not available locally."""
        try:
            client = await self.get_client()
            payload = {"name": model_name}
            response = await client.post("/api/pull", json=payload)
            response.raise_for_status()

            return {
                "success": True,
                "model": model_name,
                "message": f"Successfully pulled model {model_name}",
            }

        except Exception as e:
            return {"success": False, "model": model_name, "error": str(e)}
    
    async def cleanup(self):
        """Clean up resources when processor is destroyed."""
        if self._manager_started:
            await self.connection_manager.stop()
            self._manager_started = False
