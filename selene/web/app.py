"""
FastAPI application for Selene Second Brain Processing System.
"""

import asyncio
import os
from pathlib import Path
from typing import Optional

from fastapi import BackgroundTasks, FastAPI, HTTPException
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from loguru import logger

from ..monitoring import FileWatcher, MonitorConfig
from ..processors import LLMProcessor, OllamaProcessor, VectorProcessor
from ..prompts.manager import PromptTemplateManager
from ..prompts.models import PromptCategory, TemplateVariable
from ..prompts.builtin_templates import register_builtin_templates
from ..queue import ProcessingQueue, QueueManager
from .models import (
    AddDirectoryRequest,
    ConfigurationResponse,
    CreateTemplateRequest,
    MonitorStatusResponse,
    ProcessRequest,
    ProcessResponse,
    RemoveDirectoryRequest,
    RenderTemplateRequest,
    RenderTemplateResponse,
    SuccessResponse,
    TemplateAnalyticsResponse,
    TemplateListRequest,
    TemplateListResponse,
    TemplateResponse,
    UpdateTemplateRequest,
    VectorSearchRequest,
    VectorSearchResponse,
    VectorStoreRequest,
)


def create_app() -> FastAPI:
    """Create and configure FastAPI application."""

    app = FastAPI(
        title="Selene Second Brain Processing System",
        description="Web interface for AI-powered note processing and monitoring",
        version="0.1.0",
        docs_url="/api/docs",
        redoc_url="/api/redoc",
    )

    # Mount static files
    static_path = Path(__file__).parent / "static"
    if static_path.exists():
        app.mount("/static", StaticFiles(directory=str(static_path)), name="static")

    # Global state (in production, would use proper state management)
    app.state.file_watcher = None
    app.state.queue_manager = None
    app.state.processing_queue = None
    app.state.prompt_manager = None

    @app.on_event("startup")
    async def startup_event():
        """Initialize application state on startup."""
        logger.info("Starting Selene web application")

        try:
            # Initialize processing queue and manager
            app.state.processing_queue = ProcessingQueue(max_size=100, max_concurrent=3)
            app.state.queue_manager = QueueManager(
                app.state.processing_queue, max_workers=3
            )
            
            # Initialize prompt template manager
            app.state.prompt_manager = PromptTemplateManager()
            register_builtin_templates(app.state.prompt_manager)
            
            logger.info("Selene web application started successfully")
        except Exception as e:
            logger.error(f"Failed to start web application: {e}")

    @app.on_event("shutdown")
    async def shutdown_event():
        """Clean up resources on shutdown."""
        logger.info("Shutting down Selene web application")

        try:
            if app.state.file_watcher and app.state.file_watcher.is_watching():
                await app.state.file_watcher.stop_watching()

            if app.state.queue_manager:
                await app.state.queue_manager.stop_processing()

            logger.info("Selene web application shut down")
        except Exception as e:
            logger.error(f"Error during shutdown: {e}")

    # API Routes

    @app.get("/", response_class=HTMLResponse)
    async def root():
        """Serve the main dashboard page."""
        template_path = Path(__file__).parent / "templates" / "index.html"
        if template_path.exists():
            return FileResponse(str(template_path))
        else:
            return HTMLResponse(
                """
            <html>
                <head><title>Selene</title></head>
                <body>
                    <h1>Selene Second Brain Processing System</h1>
                    <p>Template not found. Please check installation.</p>
                    <p><a href="/api/docs">API Documentation</a></p>
                </body>
            </html>
            """
            )

    @app.get("/health")
    async def health_check():
        """Health check endpoint."""
        return {"status": "healthy", "message": "Selene Second Brain Processing System"}

    @app.post("/api/process", response_model=ProcessResponse)
    async def process_content(request: ProcessRequest):
        """Process content using AI processors."""
        try:
            # Validate request
            if not request.content and not request.file_path:
                raise HTTPException(400, "Either content or file_path must be provided")

            # Get content from file if needed
            content = request.content
            if request.file_path:
                file_path = Path(request.file_path)
                if not file_path.exists():
                    raise HTTPException(404, f"File not found: {request.file_path}")
                content = file_path.read_text(encoding="utf-8")

            # Initialize processor
            processor_instance = await _get_processor(request.processor, request.model)

            # Process content
            if request.file_path:
                result = await processor_instance.process_file(
                    Path(request.file_path), task=request.task, model=request.model
                )
            else:
                result = await processor_instance.process(
                    content, task=request.task, model=request.model
                )

            return ProcessResponse(
                success=result.success,
                content=result.content if result.success else None,
                error=result.error if not result.success else None,
                processing_time=result.processing_time,
                metadata=result.metadata,
            )

        except Exception as e:
            logger.error(f"Processing failed: {e}")
            raise HTTPException(500, f"Processing failed: {str(e)}")

    @app.post("/api/vector/search", response_model=VectorSearchResponse)
    async def search_vector_database(request: VectorSearchRequest):
        """Search the vector database."""
        try:
            vector_processor = VectorProcessor(
                {"db_path": "./chroma_db", "collection_name": request.collection}
            )

            result = await vector_processor.process(
                request.query, task="search", n_results=request.n_results
            )

            if result.success:
                # Extract search results from metadata
                results = result.metadata.get("results", [])

                return VectorSearchResponse(
                    success=True,
                    results=results,
                    total_results=len(results),
                    processing_time=result.processing_time,
                )
            else:
                return VectorSearchResponse(
                    success=False,
                    error=result.error,
                    processing_time=result.processing_time,
                )

        except Exception as e:
            logger.error(f"Vector search failed: {e}")
            raise HTTPException(500, f"Search failed: {str(e)}")

    @app.post("/api/vector/store", response_model=SuccessResponse)
    async def store_in_vector_database(request: VectorStoreRequest):
        """Store content in vector database."""
        try:
            # Get content from file if needed
            content = request.content
            if request.file_path:
                file_path = Path(request.file_path)
                if not file_path.exists():
                    raise HTTPException(404, f"File not found: {request.file_path}")
                content = file_path.read_text(encoding="utf-8")

            if not content:
                raise HTTPException(400, "Either content or file_path must be provided")

            vector_processor = VectorProcessor(
                {"db_path": "./chroma_db", "collection_name": request.collection}
            )

            result = await vector_processor.process(
                content,
                task="store",
                metadata=request.metadata,
                doc_id=request.doc_id,
                file_path=request.file_path,
            )

            if result.success:
                return SuccessResponse(
                    success=True,
                    message="Content stored successfully",
                    data={"doc_id": result.metadata.get("document_id")},
                )
            else:
                raise HTTPException(500, f"Storage failed: {result.error}")

        except Exception as e:
            logger.error(f"Vector storage failed: {e}")
            raise HTTPException(500, f"Storage failed: {str(e)}")

    @app.get("/api/monitor/status", response_model=MonitorStatusResponse)
    async def get_monitor_status():
        """Get file monitoring status."""
        try:
            config = MonitorConfig.from_file(".monitor-config.yaml")

            if app.state.file_watcher:
                status = app.state.file_watcher.get_status_summary()
                return MonitorStatusResponse(
                    is_watching=status["watcher_status"]["is_watching"],
                    watched_directories=status["watcher_status"]["watched_directories"],
                    watched_paths=status["watcher_status"]["watched_paths"],
                    queue_status=status["queue_summary"],
                    statistics=status["statistics"],
                    configuration_summary=status["configuration"],
                )
            else:
                summary = config.get_summary()
                return MonitorStatusResponse(
                    is_watching=False,
                    watched_directories=summary["watched_directories_count"],
                    watched_paths=summary["watched_paths"],
                    queue_status={},
                    statistics={},
                    configuration_summary=summary,
                )

        except Exception as e:
            logger.error(f"Status check failed: {e}")
            raise HTTPException(500, f"Status check failed: {str(e)}")

    @app.get("/api/monitor/config", response_model=ConfigurationResponse)
    async def get_configuration():
        """Get monitoring configuration."""
        try:
            config = MonitorConfig.from_file(".monitor-config.yaml")

            watched_dirs = []
            for wd in config.watched_directories:
                watched_dirs.append(
                    {
                        "path": wd.path,
                        "patterns": wd.patterns,
                        "recursive": wd.recursive,
                        "auto_process": wd.auto_process,
                        "processing_tasks": wd.processing_tasks,
                        "store_in_vector_db": wd.store_in_vector_db,
                        "metadata": wd.metadata,
                    }
                )

            summary = config.get_summary()

            return ConfigurationResponse(
                watched_directories=watched_dirs,
                processing_enabled=summary["processing_enabled"],
                default_processor=summary["default_processor"],
                batch_size=summary["batch_size"],
                max_concurrent_jobs=summary["max_concurrent_jobs"],
                supported_extensions=config.supported_extensions,
            )

        except Exception as e:
            logger.error(f"Configuration retrieval failed: {e}")
            raise HTTPException(500, f"Configuration retrieval failed: {str(e)}")

    @app.post("/api/monitor/add-directory", response_model=SuccessResponse)
    async def add_watched_directory(request: AddDirectoryRequest):
        """Add a directory to watch."""
        try:
            config = MonitorConfig.from_file(".monitor-config.yaml")

            # Validate directory exists
            if not Path(request.path).exists():
                raise HTTPException(404, f"Directory does not exist: {request.path}")

            success = config.add_watched_directory(
                path=request.path,
                patterns=request.patterns,
                recursive=request.recursive,
                auto_process=request.auto_process,
                processing_tasks=request.processing_tasks,
                store_in_vector_db=request.store_in_vector_db,
            )

            if success:
                config.save_to_file(".monitor-config.yaml")

                # Update running watcher if exists
                if app.state.file_watcher:
                    await app.state.file_watcher.add_watched_directory(
                        request.path, request.patterns, request.recursive
                    )

                return SuccessResponse(
                    success=True, message=f"Added watched directory: {request.path}"
                )
            else:
                raise HTTPException(400, f"Failed to add directory: {request.path}")

        except Exception as e:
            logger.error(f"Add directory failed: {e}")
            raise HTTPException(500, f"Add directory failed: {str(e)}")

    @app.post("/api/monitor/remove-directory", response_model=SuccessResponse)
    async def remove_watched_directory(request: RemoveDirectoryRequest):
        """Remove a directory from watching."""
        try:
            config = MonitorConfig.from_file(".monitor-config.yaml")

            success = config.remove_watched_directory(request.path)

            if success:
                config.save_to_file(".monitor-config.yaml")

                # Update running watcher if exists
                if app.state.file_watcher:
                    await app.state.file_watcher.remove_watched_directory(request.path)

                return SuccessResponse(
                    success=True, message=f"Removed watched directory: {request.path}"
                )
            else:
                return SuccessResponse(
                    success=False,
                    message=f"Directory not found in watch list: {request.path}",
                )

        except Exception as e:
            logger.error(f"Remove directory failed: {e}")
            raise HTTPException(500, f"Remove directory failed: {str(e)}")

    @app.post("/api/monitor/start", response_model=SuccessResponse)
    async def start_monitoring():
        """Start file monitoring."""
        try:
            if app.state.file_watcher and app.state.file_watcher.is_watching():
                return SuccessResponse(
                    success=True, message="File monitoring is already running"
                )

            config = MonitorConfig.from_file(".monitor-config.yaml")

            # Validate configuration
            config_issues = config.validate()
            if config_issues:
                raise HTTPException(
                    400, f"Configuration issues: {', '.join(config_issues)}"
                )

            # Start queue manager if not running
            if not app.state.queue_manager or not hasattr(
                app.state.queue_manager, "_workers"
            ):
                await app.state.queue_manager.start_processing()

            # Create and start file watcher
            app.state.file_watcher = FileWatcher(config, app.state.processing_queue)
            success = await app.state.file_watcher.start_watching()

            if success:
                return SuccessResponse(
                    success=True, message="File monitoring started successfully"
                )
            else:
                raise HTTPException(500, "Failed to start file monitoring")

        except Exception as e:
            logger.error(f"Start monitoring failed: {e}")
            raise HTTPException(500, f"Start monitoring failed: {str(e)}")

    @app.post("/api/monitor/stop", response_model=SuccessResponse)
    async def stop_monitoring():
        """Stop file monitoring."""
        try:
            if not app.state.file_watcher or not app.state.file_watcher.is_watching():
                return SuccessResponse(
                    success=True, message="File monitoring is not running"
                )

            await app.state.file_watcher.stop_watching()
            app.state.file_watcher = None

            return SuccessResponse(
                success=True, message="File monitoring stopped successfully"
            )

        except Exception as e:
            logger.error(f"Stop monitoring failed: {e}")
            raise HTTPException(500, f"Stop monitoring failed: {str(e)}")

    # Prompt Template Management Endpoints
    
    @app.get("/api/templates", response_model=TemplateListResponse)
    async def list_templates(
        category: Optional[PromptCategory] = None,
        tags: Optional[str] = None,
        sort_by: str = "name",
        search: Optional[str] = None
    ):
        """List all prompt templates with optional filtering."""
        try:
            tag_list = tags.split(",") if tags else None
            
            if search:
                templates = app.state.prompt_manager.search_templates(search)
            else:
                templates = app.state.prompt_manager.list_templates(
                    category=category,
                    tags=tag_list,
                    sort_by=sort_by
                )
            
            # Convert to response format
            template_responses = []
            for template in templates:
                template_responses.append(TemplateResponse(
                    id=template.id,
                    name=template.name,
                    description=template.description,
                    category=template.category,
                    template=template.template,
                    variables=[var.dict() for var in template.variables],
                    tags=template.tags,
                    author=template.author,
                    version=template.version,
                    created_at=template.created_at.isoformat(),
                    updated_at=template.updated_at.isoformat(),
                    usage_count=template.usage_count,
                    last_used=template.last_used.isoformat() if template.last_used else None,
                    avg_quality_score=template.avg_quality_score,
                    success_rate=template.success_rate
                ))
            
            # Get category counts
            all_templates = app.state.prompt_manager.list_templates()
            categories = {}
            for cat in PromptCategory:
                categories[cat.value] = len([t for t in all_templates if t.category == cat])
            
            return TemplateListResponse(
                templates=template_responses,
                total=len(template_responses),
                categories=categories
            )
            
        except Exception as e:
            logger.error(f"List templates failed: {str(e)}")
            raise HTTPException(500, f"List templates failed: {str(e)}")
    
    @app.get("/api/templates/{template_id}", response_model=TemplateResponse)
    async def get_template(template_id: str):
        """Get a specific template by ID."""
        try:
            template = app.state.prompt_manager.get_template(template_id)
            if not template:
                raise HTTPException(404, f"Template not found: {template_id}")
            
            return TemplateResponse(
                id=template.id,
                name=template.name,
                description=template.description,
                category=template.category,
                template=template.template,
                variables=[var.dict() for var in template.variables],
                tags=template.tags,
                author=template.author,
                version=template.version,
                created_at=template.created_at.isoformat(),
                updated_at=template.updated_at.isoformat(),
                usage_count=template.usage_count,
                last_used=template.last_used.isoformat() if template.last_used else None,
                avg_quality_score=template.avg_quality_score,
                success_rate=template.success_rate
            )
            
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"Get template failed: {str(e)}")
            raise HTTPException(500, f"Get template failed: {str(e)}")
    
    @app.post("/api/templates", response_model=TemplateResponse)
    async def create_template(request: CreateTemplateRequest):
        """Create a new prompt template."""
        try:
            # Convert variable requests to TemplateVariable objects
            variables = []
            for var_req in request.variables:
                variables.append({
                    "name": var_req.name,
                    "description": var_req.description,
                    "required": var_req.required,
                    "default_value": var_req.default_value,
                    "validation_pattern": var_req.validation_pattern
                })
            
            template = app.state.prompt_manager.create_template(
                name=request.name,
                description=request.description,
                category=request.category,
                template=request.template,
                variables=variables,
                tags=request.tags,
                author=request.author
            )
            
            if not template:
                raise HTTPException(400, "Failed to create template")
            
            return TemplateResponse(
                id=template.id,
                name=template.name,
                description=template.description,
                category=template.category,
                template=template.template,
                variables=[var.dict() for var in template.variables],
                tags=template.tags,
                author=template.author,
                version=template.version,
                created_at=template.created_at.isoformat(),
                updated_at=template.updated_at.isoformat(),
                usage_count=template.usage_count,
                last_used=template.last_used.isoformat() if template.last_used else None,
                avg_quality_score=template.avg_quality_score,
                success_rate=template.success_rate
            )
            
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"Create template failed: {str(e)}")
            raise HTTPException(500, f"Create template failed: {str(e)}")
    
    @app.put("/api/templates/{template_id}", response_model=TemplateResponse)
    async def update_template(template_id: str, request: UpdateTemplateRequest):
        """Update an existing template."""
        try:
            # Prepare updates dict
            updates = {}
            if request.name is not None:
                updates["name"] = request.name
            if request.description is not None:
                updates["description"] = request.description
            if request.category is not None:
                updates["category"] = request.category
            if request.template is not None:
                updates["template"] = request.template
            if request.tags is not None:
                updates["tags"] = request.tags
            if request.variables is not None:
                variables = []
                for var_req in request.variables:
                    variables.append(TemplateVariable(
                        name=var_req.name,
                        description=var_req.description,
                        required=var_req.required,
                        default_value=var_req.default_value,
                        validation_pattern=var_req.validation_pattern
                    ))
                updates["variables"] = variables
            
            success = app.state.prompt_manager.update_template(template_id, **updates)
            if not success:
                raise HTTPException(400, f"Failed to update template: {template_id}")
            
            # Return updated template
            template = app.state.prompt_manager.get_template(template_id)
            return TemplateResponse(
                id=template.id,
                name=template.name,
                description=template.description,
                category=template.category,
                template=template.template,
                variables=[var.dict() for var in template.variables],
                tags=template.tags,
                author=template.author,
                version=template.version,
                created_at=template.created_at.isoformat(),
                updated_at=template.updated_at.isoformat(),
                usage_count=template.usage_count,
                last_used=template.last_used.isoformat() if template.last_used else None,
                avg_quality_score=template.avg_quality_score,
                success_rate=template.success_rate
            )
            
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"Update template failed: {str(e)}")
            raise HTTPException(500, f"Update template failed: {str(e)}")
    
    @app.delete("/api/templates/{template_id}", response_model=SuccessResponse)
    async def delete_template(template_id: str):
        """Delete a template."""
        try:
            success = app.state.prompt_manager.delete_template(template_id)
            if not success:
                raise HTTPException(404, f"Template not found: {template_id}")
            
            return SuccessResponse(
                success=True,
                message=f"Template {template_id} deleted successfully"
            )
            
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"Delete template failed: {str(e)}")
            raise HTTPException(500, f"Delete template failed: {str(e)}")
    
    @app.post("/api/templates/render", response_model=RenderTemplateResponse)
    async def render_template(request: RenderTemplateRequest):
        """Render a template with variables."""
        try:
            template = app.state.prompt_manager.get_template(request.template_id)
            if not template:
                raise HTTPException(404, f"Template not found: {request.template_id}")
            
            rendered = app.state.prompt_manager.render_template(
                request.template_id,
                request.variables,
                request.model_name
            )
            
            if rendered is None:
                raise HTTPException(400, "Failed to render template")
            
            return RenderTemplateResponse(
                rendered_prompt=rendered,
                template_name=template.name,
                variables_used=request.variables
            )
            
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"Render template failed: {str(e)}")
            raise HTTPException(500, f"Render template failed: {str(e)}")
    
    @app.get("/api/templates/{template_id}/analytics", response_model=TemplateAnalyticsResponse)
    async def get_template_analytics(template_id: str):
        """Get analytics for a specific template."""
        try:
            analytics = app.state.prompt_manager.get_template_analytics(template_id)
            if not analytics:
                raise HTTPException(404, f"Template not found: {template_id}")
            
            return TemplateAnalyticsResponse(**analytics)
            
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"Get template analytics failed: {str(e)}")
            raise HTTPException(500, f"Get template analytics failed: {str(e)}")

    return app


async def _get_processor(processor_type: str, model: str):
    """Get processor instance based on type."""
    if processor_type == "ollama":
        return OllamaProcessor({"base_url": "http://localhost:11434", "model": model})
    elif processor_type == "openai":
        api_key = os.getenv("OPENAI_API_KEY")
        if not api_key:
            raise HTTPException(400, "OpenAI API key required")
        return LLMProcessor({"openai_api_key": api_key, "model": model})
    elif processor_type == "vector":
        return VectorProcessor(
            {"db_path": "./chroma_db", "collection_name": "selene_notes"}
        )
    else:
        raise HTTPException(400, f"Invalid processor type: {processor_type}")
