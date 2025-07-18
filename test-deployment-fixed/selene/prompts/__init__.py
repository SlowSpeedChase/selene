"""
Prompt Template System for Selene AI Processing

This module provides a comprehensive prompt template system that enables:
- Standardized AI interactions across all processors
- Reusable and optimizable prompt templates
- Template management and versioning
- Multi-model prompt optimization
- Advanced AI workflows with chained prompts
"""

from .models import PromptTemplate, PromptCategory, TemplateVariable
from .manager import PromptTemplateManager
from .builtin_templates import get_builtin_templates, register_builtin_templates

__all__ = [
    "PromptTemplate",
    "PromptCategory", 
    "TemplateVariable",
    "PromptTemplateManager",
    "get_builtin_templates",
    "register_builtin_templates"
]