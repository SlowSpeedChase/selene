"""
Pydantic models for web API requests and responses.
"""

from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class ProcessRequest(BaseModel):
    """Request model for content processing."""

    content: Optional[str] = Field(None, description="Content to process directly")
    file_path: Optional[str] = Field(None, description="File path to process")
    task: str = Field("enhance", description="Processing task")
    processor: str = Field("ollama", description="Processor type")
    model: str = Field("llama3.2", description="Model to use")


class ProcessResponse(BaseModel):
    """Response model for content processing."""

    success: bool
    content: Optional[str] = None
    error: Optional[str] = None
    processing_time: float
    metadata: Dict[str, Any] = Field(default_factory=dict)


class VectorSearchRequest(BaseModel):
    """Request model for vector database search."""

    query: str = Field(..., description="Search query")
    n_results: int = Field(5, description="Number of results to return")
    collection: str = Field("selene_notes", description="Collection name")


class VectorSearchResponse(BaseModel):
    """Response model for vector search."""

    success: bool
    results: List[Dict[str, Any]] = Field(default_factory=list)
    error: Optional[str] = None
    total_results: int = 0
    processing_time: float


class VectorStoreRequest(BaseModel):
    """Request model for storing content in vector database."""

    content: Optional[str] = Field(None, description="Content to store")
    file_path: Optional[str] = Field(None, description="File path to store")
    doc_id: Optional[str] = Field(None, description="Document ID")
    metadata: Dict[str, Any] = Field(default_factory=dict)
    collection: str = Field("selene_notes", description="Collection name")


class MonitorStatusResponse(BaseModel):
    """Response model for monitoring status."""

    is_watching: bool
    watched_directories: int
    watched_paths: List[str]
    queue_status: Dict[str, Any]
    statistics: Dict[str, Any]
    configuration_summary: Dict[str, Any]


class ConfigurationResponse(BaseModel):
    """Response model for configuration information."""

    watched_directories: List[Dict[str, Any]]
    processing_enabled: bool
    default_processor: str
    batch_size: int
    max_concurrent_jobs: int
    supported_extensions: List[str]


class AddDirectoryRequest(BaseModel):
    """Request model for adding watched directory."""

    path: str = Field(..., description="Directory path to watch")
    patterns: List[str] = Field(["*.txt", "*.md", "*.pdf"], description="File patterns")
    recursive: bool = Field(True, description="Watch subdirectories")
    auto_process: bool = Field(True, description="Enable automatic processing")
    processing_tasks: List[str] = Field(
        ["summarize", "extract_insights"], description="Processing tasks"
    )
    store_in_vector_db: bool = Field(
        True, description="Store results in vector database"
    )


class RemoveDirectoryRequest(BaseModel):
    """Request model for removing watched directory."""

    path: str = Field(..., description="Directory path to remove")


class SuccessResponse(BaseModel):
    """Generic success response."""

    success: bool
    message: str
    data: Optional[Dict[str, Any]] = None
