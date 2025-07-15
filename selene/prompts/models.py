"""
Core models for the prompt template system.
"""

import re
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional, Set
from uuid import uuid4

from pydantic import BaseModel, Field, validator


class PromptCategory(str, Enum):
    """Categories for organizing prompt templates."""
    
    ANALYSIS = "analysis"
    ENHANCEMENT = "enhancement"
    SUMMARIZATION = "summarization"
    EXTRACTION = "extraction"
    CLASSIFICATION = "classification"
    GENERATION = "generation"
    CUSTOM = "custom"


class TemplateVariable(BaseModel):
    """Represents a variable within a prompt template."""
    
    name: str = Field(..., description="Variable name (without braces)")
    description: str = Field(..., description="Human-readable description")
    required: bool = Field(True, description="Whether this variable is required")
    default_value: Optional[str] = Field(None, description="Default value if not provided")
    validation_pattern: Optional[str] = Field(None, description="Regex pattern for validation")
    
    @validator('name')
    def validate_name(cls, v):
        """Ensure variable name is valid."""
        if not re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', v):
            raise ValueError('Variable name must be a valid identifier')
        return v
    
    def validate_value(self, value: str) -> bool:
        """Validate a value against this variable's constraints."""
        if self.validation_pattern:
            return bool(re.match(self.validation_pattern, value))
        return True


class PromptTemplate(BaseModel):
    """
    A reusable prompt template with variables and metadata.
    
    Templates support variable substitution using {variable_name} syntax.
    """
    
    id: str = Field(default_factory=lambda: str(uuid4()), description="Unique template ID")
    name: str = Field(..., description="Human-readable template name")
    description: str = Field(..., description="Description of what this template does")
    category: PromptCategory = Field(..., description="Template category")
    template: str = Field(..., description="The prompt template with {variables}")
    variables: List[TemplateVariable] = Field(default_factory=list, description="Template variables")
    
    # Metadata
    author: Optional[str] = Field(None, description="Template author")
    version: str = Field("1.0.0", description="Template version")
    tags: List[str] = Field(default_factory=list, description="Searchable tags")
    created_at: datetime = Field(default_factory=datetime.now, description="Creation timestamp")
    updated_at: datetime = Field(default_factory=datetime.now, description="Last update timestamp")
    
    # Usage tracking
    usage_count: int = Field(0, description="Number of times template has been used")
    last_used: Optional[datetime] = Field(None, description="Last usage timestamp")
    
    # Performance metrics
    avg_quality_score: Optional[float] = Field(None, description="Average quality rating (1-5)")
    success_rate: Optional[float] = Field(None, description="Success rate percentage")
    
    # Model-specific optimizations
    model_optimizations: Dict[str, Dict[str, Any]] = Field(
        default_factory=dict, 
        description="Model-specific parameter overrides"
    )
    
    class Config:
        """Pydantic configuration."""
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }
    
    @validator('template')
    def validate_template(cls, v):
        """Ensure template syntax is valid."""
        # Find all variables in template
        variables = set(re.findall(r'\{([^}]+)\}', v))
        return v
    
    def get_template_variables(self) -> Set[str]:
        """Extract all variable names from the template."""
        return set(re.findall(r'\{([^}]+)\}', self.template))
    
    def validate_variables(self) -> List[str]:
        """Validate that all template variables are defined."""
        template_vars = self.get_template_variables()
        defined_vars = {var.name for var in self.variables}
        
        errors = []
        
        # Check for undefined variables
        undefined = template_vars - defined_vars
        if undefined:
            errors.append(f"Undefined variables in template: {', '.join(undefined)}")
        
        # Check for unused variable definitions
        unused = defined_vars - template_vars
        if unused:
            errors.append(f"Unused variable definitions: {', '.join(unused)}")
        
        return errors
    
    def render(self, variables: Dict[str, str], strict: bool = True) -> str:
        """
        Render the template with provided variables.
        
        Args:
            variables: Dictionary of variable values
            strict: If True, raise error for missing required variables
            
        Returns:
            Rendered prompt string
            
        Raises:
            ValueError: If required variables are missing in strict mode
        """
        # Check for required variables
        missing_required = []
        final_variables = {}
        
        for var in self.variables:
            if var.name in variables:
                value = variables[var.name]
                if not var.validate_value(value):
                    raise ValueError(f"Invalid value for variable '{var.name}': {value}")
                final_variables[var.name] = value
            elif var.default_value is not None:
                final_variables[var.name] = var.default_value
            elif var.required:
                missing_required.append(var.name)
            
        if missing_required and strict:
            raise ValueError(f"Missing required variables: {', '.join(missing_required)}")
        
        # Render template
        try:
            return self.template.format(**final_variables)
        except KeyError as e:
            raise ValueError(f"Template contains undefined variable: {e}")
    
    def get_model_config(self, model_name: str) -> Dict[str, Any]:
        """Get model-specific configuration if available."""
        return self.model_optimizations.get(model_name, {})
    
    def update_usage_stats(self, quality_score: Optional[float] = None, success: bool = True):
        """Update template usage statistics."""
        self.usage_count += 1
        self.last_used = datetime.now()
        self.updated_at = datetime.now()
        
        if quality_score is not None:
            if self.avg_quality_score is None:
                self.avg_quality_score = quality_score
            else:
                # Running average
                total_score = self.avg_quality_score * (self.usage_count - 1) + quality_score
                self.avg_quality_score = total_score / self.usage_count
        
        if self.success_rate is None:
            self.success_rate = 100.0 if success else 0.0
        else:
            # Running average
            total_successes = (self.success_rate / 100.0) * (self.usage_count - 1)
            if success:
                total_successes += 1
            self.success_rate = (total_successes / self.usage_count) * 100.0
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for storage/serialization."""
        return self.dict()
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "PromptTemplate":
        """Create instance from dictionary."""
        return cls(**data)


@dataclass
class PromptExecutionContext:
    """Context information for prompt execution."""
    
    template_id: str
    model_name: str
    processor_type: str
    variables: Dict[str, str]
    execution_time: Optional[float] = None
    success: bool = True
    error_message: Optional[str] = None
    quality_score: Optional[float] = None
    output_length: Optional[int] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for logging/analytics."""
        return {
            'template_id': self.template_id,
            'model_name': self.model_name,
            'processor_type': self.processor_type,
            'variables': self.variables,
            'execution_time': self.execution_time,
            'success': self.success,
            'error_message': self.error_message,
            'quality_score': self.quality_score,
            'output_length': self.output_length,
            'timestamp': datetime.now().isoformat()
        }