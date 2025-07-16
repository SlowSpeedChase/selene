"""
Base tool system for SELENE chatbot agent.

This module provides the foundation for tool-calling capabilities,
allowing the agent to interact with files, search, and AI processing.
"""

import json
from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import Enum
from typing import Any, Dict, List, Optional, Type, Union

from loguru import logger
from pydantic import BaseModel, Field


class ToolStatus(Enum):
    """Status of tool execution."""
    SUCCESS = "success"
    ERROR = "error"
    CANCELLED = "cancelled"
    REQUIRES_CONFIRMATION = "requires_confirmation"


@dataclass
class ToolResult:
    """Result of tool execution."""
    status: ToolStatus
    content: Any = None
    error_message: Optional[str] = None
    metadata: Dict[str, Any] = None
    
    def __post_init__(self):
        if self.metadata is None:
            self.metadata = {}
    
    @property
    def is_success(self) -> bool:
        """Check if tool execution was successful."""
        return self.status == ToolStatus.SUCCESS
    
    @property
    def is_error(self) -> bool:
        """Check if tool execution failed."""
        return self.status == ToolStatus.ERROR
    
    @property
    def requires_confirmation(self) -> bool:
        """Check if tool execution requires user confirmation."""
        return self.status == ToolStatus.REQUIRES_CONFIRMATION
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert result to dictionary."""
        return {
            "status": self.status.value,
            "content": self.content,
            "error_message": self.error_message,
            "metadata": self.metadata
        }


class ToolParameter(BaseModel):
    """Definition of a tool parameter."""
    name: str = Field(description="Parameter name")
    type: str = Field(description="Parameter type (string, int, bool, etc.)")
    description: str = Field(description="Parameter description")
    required: bool = Field(default=True, description="Whether parameter is required")
    default: Any = Field(default=None, description="Default value if not required")
    enum: Optional[List[str]] = Field(default=None, description="Allowed values for enum parameters")


class BaseTool(ABC):
    """Base class for all chatbot tools."""
    
    def __init__(self):
        """Initialize the tool."""
        self._name = self.__class__.__name__.lower().replace("tool", "")
        
    @property
    @abstractmethod
    def name(self) -> str:
        """Tool name for identification."""
        pass
    
    @property
    @abstractmethod
    def description(self) -> str:
        """Tool description for the AI agent."""
        pass
    
    @property
    @abstractmethod
    def parameters(self) -> List[ToolParameter]:
        """Tool parameters definition."""
        pass
    
    @abstractmethod
    async def execute(self, **kwargs) -> ToolResult:
        """Execute the tool with given parameters."""
        pass
    
    def validate_parameters(self, **kwargs) -> List[str]:
        """Validate provided parameters against tool definition."""
        errors = []
        
        # Check required parameters
        for param in self.parameters:
            if param.required and param.name not in kwargs:
                errors.append(f"Missing required parameter: {param.name}")
                
        # Check parameter types (basic validation)
        for param_name, param_value in kwargs.items():
            param_def = next((p for p in self.parameters if p.name == param_name), None)
            if not param_def:
                errors.append(f"Unknown parameter: {param_name}")
                continue
                
            # Basic type checking
            if param_def.type == "string" and not isinstance(param_value, str):
                errors.append(f"Parameter {param_name} must be a string")
            elif param_def.type == "int" and not isinstance(param_value, int):
                errors.append(f"Parameter {param_name} must be an integer")
            elif param_def.type == "bool" and not isinstance(param_value, bool):
                errors.append(f"Parameter {param_name} must be a boolean")
            elif param_def.enum and param_value not in param_def.enum:
                errors.append(f"Parameter {param_name} must be one of: {param_def.enum}")
                
        return errors
    
    def get_schema(self) -> Dict[str, Any]:
        """Get tool schema for AI function calling."""
        return {
            "name": self.name,
            "description": self.description,
            "parameters": {
                "type": "object",
                "properties": {
                    param.name: {
                        "type": param.type,
                        "description": param.description,
                        **({"enum": param.enum} if param.enum else {}),
                        **({"default": param.default} if param.default is not None else {})
                    }
                    for param in self.parameters
                },
                "required": [param.name for param in self.parameters if param.required]
            }
        }
    
    def __str__(self) -> str:
        """String representation of the tool."""
        return f"{self.name}: {self.description}"


class ToolRegistry:
    """Registry for managing available tools."""
    
    def __init__(self):
        """Initialize tool registry."""
        self._tools: Dict[str, BaseTool] = {}
        self._enabled_tools: List[str] = []
        
    def register(self, tool: BaseTool) -> None:
        """Register a tool in the registry."""
        if not isinstance(tool, BaseTool):
            raise ValueError(f"Tool must inherit from BaseTool: {type(tool)}")
            
        self._tools[tool.name] = tool
        logger.debug(f"Registered tool: {tool.name}")
        
    def unregister(self, tool_name: str) -> None:
        """Unregister a tool from the registry."""
        if tool_name in self._tools:
            del self._tools[tool_name]
            logger.debug(f"Unregistered tool: {tool_name}")
            
    def get_tool(self, tool_name: str) -> Optional[BaseTool]:
        """Get a tool by name."""
        return self._tools.get(tool_name)
        
    def list_tools(self, enabled_only: bool = True) -> List[str]:
        """List available tool names."""
        if enabled_only:
            return [name for name in self._tools.keys() if name in self._enabled_tools]
        return list(self._tools.keys())
        
    def get_schemas(self, enabled_only: bool = True) -> List[Dict[str, Any]]:
        """Get schemas for all tools."""
        tools = self.list_tools(enabled_only)
        return [self._tools[name].get_schema() for name in tools]
        
    def enable_tool(self, tool_name: str) -> bool:
        """Enable a tool for use."""
        if tool_name not in self._tools:
            logger.warning(f"Cannot enable unknown tool: {tool_name}")
            return False
            
        if tool_name not in self._enabled_tools:
            self._enabled_tools.append(tool_name)
            logger.debug(f"Enabled tool: {tool_name}")
            
        return True
        
    def disable_tool(self, tool_name: str) -> bool:
        """Disable a tool from use."""
        if tool_name in self._enabled_tools:
            self._enabled_tools.remove(tool_name)
            logger.debug(f"Disabled tool: {tool_name}")
            return True
            
        return False
        
    def enable_tools(self, tool_names: List[str]) -> int:
        """Enable multiple tools. Returns count of successfully enabled tools."""
        enabled_count = 0
        for tool_name in tool_names:
            if self.enable_tool(tool_name):
                enabled_count += 1
        return enabled_count
        
    def is_enabled(self, tool_name: str) -> bool:
        """Check if a tool is enabled."""
        return tool_name in self._enabled_tools
        
    async def execute_tool(self, tool_name: str, **kwargs) -> ToolResult:
        """Execute a tool with given parameters."""
        # Check if tool exists
        tool = self.get_tool(tool_name)
        if not tool:
            return ToolResult(
                status=ToolStatus.ERROR,
                error_message=f"Unknown tool: {tool_name}"
            )
            
        # Check if tool is enabled
        if not self.is_enabled(tool_name):
            return ToolResult(
                status=ToolStatus.ERROR,
                error_message=f"Tool is disabled: {tool_name}"
            )
            
        # Validate parameters
        validation_errors = tool.validate_parameters(**kwargs)
        if validation_errors:
            return ToolResult(
                status=ToolStatus.ERROR,
                error_message=f"Parameter validation failed: {'; '.join(validation_errors)}"
            )
            
        # Execute tool
        try:
            logger.debug(f"Executing tool {tool_name} with parameters: {kwargs}")
            result = await tool.execute(**kwargs)
            logger.debug(f"Tool {tool_name} completed with status: {result.status}")
            return result
            
        except Exception as e:
            logger.error(f"Tool {tool_name} execution failed: {e}")
            return ToolResult(
                status=ToolStatus.ERROR,
                error_message=f"Tool execution failed: {str(e)}"
            )
            
    def get_tool_info(self) -> Dict[str, Any]:
        """Get information about all registered tools."""
        return {
            "total_tools": len(self._tools),
            "enabled_tools": len(self._enabled_tools),
            "tools": {
                name: {
                    "description": tool.description,
                    "enabled": name in self._enabled_tools,
                    "parameters": [param.dict() for param in tool.parameters]
                }
                for name, tool in self._tools.items()
            }
        }
    
    def __len__(self) -> int:
        """Number of registered tools."""
        return len(self._tools)
        
    def __contains__(self, tool_name: str) -> bool:
        """Check if tool is registered."""
        return tool_name in self._tools