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
from ..queue import ProcessingQueue, QueueManager
from .models import (
    AddDirectoryRequest,
    ConfigurationResponse,
    MonitorStatusResponse,
    ProcessRequest,
    ProcessResponse,
    RemoveDirectoryRequest,
    SuccessResponse,
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
