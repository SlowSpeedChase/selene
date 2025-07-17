"""
Pydantic models for web API requests and responses.
"""

from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field
from ..prompts.models import PromptCategory


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


# Chat API Models

class ChatSessionRequest(BaseModel):
    """Request model for creating a chat session."""
    
    vault_path: Optional[str] = Field(None, description="Path to Obsidian vault")
    session_name: Optional[str] = Field(None, description="Human-readable session name")
    enable_memory: bool = Field(True, description="Enable conversation memory")
    debug_mode: bool = Field(False, description="Enable debug logging")
    use_enhanced_agent: bool = Field(True, description="Use enhanced agent with advanced features")


class ChatSessionResponse(BaseModel):
    """Response model for chat session operations."""
    
    session_id: str
    vault_path: Optional[str] = None
    session_name: Optional[str] = None
    created_at: str
    enable_memory: bool
    debug_mode: bool
    vault_detected: bool = False
    available_tools: List[str] = Field(default_factory=list)


class ChatMessageRequest(BaseModel):
    """Request model for sending a chat message."""
    
    message: str = Field(..., description="User message")
    stream: bool = Field(True, description="Stream response in real-time")


class ChatMessageResponse(BaseModel):
    """Response model for chat messages."""
    
    message_id: str
    content: str
    timestamp: str
    message_type: str  # 'user', 'assistant', 'system', 'tool_result'
    metadata: Dict[str, Any] = Field(default_factory=dict)
    processing_time: Optional[float] = None


class ChatHistoryResponse(BaseModel):
    """Response model for chat conversation history."""
    
    session_id: str
    messages: List[ChatMessageResponse]
    total_messages: int
    session_created_at: str


class ChatSessionListResponse(BaseModel):
    """Response model for listing chat sessions."""
    
    sessions: List[ChatSessionResponse]
    total_sessions: int


class ChatToolExecutionRequest(BaseModel):
    """Request model for executing chat tools."""
    
    tool_name: str = Field(..., description="Name of tool to execute")
    parameters: Dict[str, Any] = Field(default_factory=dict, description="Tool parameters")


class ChatToolExecutionResponse(BaseModel):
    """Response model for chat tool execution."""
    
    success: bool
    tool_name: str
    result: Any = None
    error: Optional[str] = None
    execution_time: float
    metadata: Dict[str, Any] = Field(default_factory=dict)


class SuccessResponse(BaseModel):
    """Generic success response."""

    success: bool
    message: str
    data: Optional[Dict[str, Any]] = None


# Prompt Template Models

class TemplateVariableRequest(BaseModel):
    """Template variable definition."""
    
    name: str = Field(..., description="Variable name")
    description: str = Field(..., description="Variable description")
    required: bool = Field(True, description="Whether variable is required")
    default_value: Optional[str] = Field(None, description="Default value")
    validation_pattern: Optional[str] = Field(None, description="Regex validation pattern")


class CreateTemplateRequest(BaseModel):
    """Request model for creating a prompt template."""
    
    name: str = Field(..., description="Template name")
    description: str = Field(..., description="Template description")
    category: PromptCategory = Field(..., description="Template category")
    template: str = Field(..., description="Prompt template with {variables}")
    variables: List[TemplateVariableRequest] = Field(default_factory=list, description="Template variables")
    tags: List[str] = Field(default_factory=list, description="Searchable tags")
    author: Optional[str] = Field(None, description="Template author")


class UpdateTemplateRequest(BaseModel):
    """Request model for updating a prompt template."""
    
    name: Optional[str] = None
    description: Optional[str] = None
    category: Optional[PromptCategory] = None
    template: Optional[str] = None
    variables: Optional[List[TemplateVariableRequest]] = None
    tags: Optional[List[str]] = None


class RenderTemplateRequest(BaseModel):
    """Request model for rendering a template."""
    
    template_id: str = Field(..., description="Template ID to render")
    variables: Dict[str, str] = Field(..., description="Variable values")
    model_name: Optional[str] = Field(None, description="Model name for optimizations")


class TemplateListRequest(BaseModel):
    """Request model for listing templates."""
    
    category: Optional[PromptCategory] = None
    tags: Optional[List[str]] = None
    sort_by: str = Field("name", description="Sort field")
    search: Optional[str] = None


class TemplateResponse(BaseModel):
    """Response model for prompt template data."""
    
    id: str
    name: str
    description: str
    category: PromptCategory
    template: str
    variables: List[Dict[str, Any]]
    tags: List[str]
    author: Optional[str]
    version: str
    created_at: str
    updated_at: str
    usage_count: int
    last_used: Optional[str]
    avg_quality_score: Optional[float]
    success_rate: Optional[float]


class TemplateListResponse(BaseModel):
    """Response model for template list."""
    
    templates: List[TemplateResponse]
    total: int
    categories: Dict[str, int]


class TemplateAnalyticsResponse(BaseModel):
    """Response model for template analytics."""
    
    template_id: str
    name: str
    usage_count: int
    success_rate: Optional[float]
    avg_quality_score: Optional[float]
    last_used: Optional[str]
    recent_executions: int
    avg_execution_time: Optional[float]


class RenderTemplateResponse(BaseModel):
    """Response model for template rendering."""
    
    rendered_prompt: str
    template_name: str
    variables_used: Dict[str, str]
