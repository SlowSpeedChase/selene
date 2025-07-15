"""
Prompt Template Manager for CRUD operations and storage.
"""

import json
from pathlib import Path
from typing import Any, Dict, List, Optional

from loguru import logger

from .models import PromptTemplate, PromptCategory, PromptExecutionContext


class PromptTemplateManager:
    """
    Manager for prompt template storage, retrieval, and lifecycle management.
    
    Features:
    - File-based storage with JSON serialization
    - Template validation and versioning
    - Usage analytics and performance tracking
    - Search and filtering capabilities
    - Template optimization recommendations
    """
    
    def __init__(self, storage_path: str = "prompt_templates"):
        """
        Initialize the template manager.
        
        Args:
            storage_path: Directory path for storing template files
        """
        self.storage_path = Path(storage_path)
        self.storage_path.mkdir(exist_ok=True)
        
        # In-memory cache for faster access
        self._templates: Dict[str, PromptTemplate] = {}
        self._execution_log: List[PromptExecutionContext] = []
        
        # Load existing templates
        self._load_templates()
        
        logger.info(f"PromptTemplateManager initialized with {len(self._templates)} templates")
    
    def _load_templates(self) -> None:
        """Load all templates from storage."""
        self._templates.clear()
        
        if not self.storage_path.exists():
            return
        
        for template_file in self.storage_path.glob("*.json"):
            try:
                with open(template_file, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                
                # Convert ISO strings back to datetime objects
                from datetime import datetime
                if 'created_at' in data and isinstance(data['created_at'], str):
                    data['created_at'] = datetime.fromisoformat(data['created_at'])
                if 'updated_at' in data and isinstance(data['updated_at'], str):
                    data['updated_at'] = datetime.fromisoformat(data['updated_at'])
                if 'last_used' in data and data['last_used'] and isinstance(data['last_used'], str):
                    data['last_used'] = datetime.fromisoformat(data['last_used'])
                
                template = PromptTemplate.from_dict(data)
                self._templates[template.id] = template
                
            except Exception as e:
                logger.error(f"Failed to load template from {template_file}: {e}")
    
    def _save_template(self, template: PromptTemplate) -> bool:
        """Save a single template to storage."""
        try:
            file_path = self.storage_path / f"{template.id}.json"
            with open(file_path, 'w', encoding='utf-8') as f:
                data = template.to_dict()
                # Convert datetime objects to ISO strings
                if 'created_at' in data and hasattr(data['created_at'], 'isoformat'):
                    data['created_at'] = data['created_at'].isoformat()
                if 'updated_at' in data and hasattr(data['updated_at'], 'isoformat'):
                    data['updated_at'] = data['updated_at'].isoformat()
                if 'last_used' in data and data['last_used'] and hasattr(data['last_used'], 'isoformat'):
                    data['last_used'] = data['last_used'].isoformat()
                json.dump(data, f, indent=2, ensure_ascii=False)
            
            logger.debug(f"Saved template {template.name} ({template.id})")
            return True
            
        except Exception as e:
            logger.error(f"Failed to save template {template.id}: {e}")
            return False
    
    def create_template(self, 
                       name: str,
                       description: str,
                       category: PromptCategory,
                       template: str,
                       variables: Optional[List[Dict[str, Any]]] = None,
                       **kwargs) -> Optional[PromptTemplate]:
        """
        Create a new prompt template.
        
        Args:
            name: Template name
            description: Template description
            category: Template category
            template: The prompt template string
            variables: List of variable definitions
            **kwargs: Additional template metadata
            
        Returns:
            Created PromptTemplate or None if creation failed
        """
        try:
            # Convert variable dicts to TemplateVariable objects if provided
            from .models import TemplateVariable
            
            template_vars = []
            if variables:
                for var_data in variables:
                    template_vars.append(TemplateVariable(**var_data))
            
            # Create new template
            new_template = PromptTemplate(
                name=name,
                description=description,
                category=category,
                template=template,
                variables=template_vars,
                **kwargs
            )
            
            # Validate template
            validation_errors = new_template.validate_variables()
            if validation_errors:
                logger.error(f"Template validation failed: {validation_errors}")
                return None
            
            # Save to storage and cache
            if self._save_template(new_template):
                self._templates[new_template.id] = new_template
                logger.info(f"Created template: {name} ({new_template.id})")
                return new_template
            
            return None
            
        except Exception as e:
            logger.error(f"Failed to create template: {e}")
            return None
    
    def get_template(self, template_id: str) -> Optional[PromptTemplate]:
        """Get a template by ID."""
        return self._templates.get(template_id)
    
    def get_template_by_name(self, name: str) -> Optional[PromptTemplate]:
        """Get a template by name (returns first match)."""
        for template in self._templates.values():
            if template.name == name:
                return template
        return None
    
    def list_templates(self, 
                      category: Optional[PromptCategory] = None,
                      tags: Optional[List[str]] = None,
                      sort_by: str = "name") -> List[PromptTemplate]:
        """
        List templates with optional filtering and sorting.
        
        Args:
            category: Filter by category
            tags: Filter by tags (template must have all specified tags)
            sort_by: Sort field ("name", "created_at", "usage_count", "avg_quality_score")
            
        Returns:
            List of matching templates
        """
        templates = list(self._templates.values())
        
        # Apply filters
        if category:
            templates = [t for t in templates if t.category == category]
        
        if tags:
            templates = [t for t in templates if all(tag in t.tags for tag in tags)]
        
        # Sort templates
        if sort_by == "name":
            templates.sort(key=lambda t: t.name.lower())
        elif sort_by == "created_at":
            templates.sort(key=lambda t: t.created_at, reverse=True)
        elif sort_by == "usage_count":
            templates.sort(key=lambda t: t.usage_count, reverse=True)
        elif sort_by == "avg_quality_score":
            templates.sort(key=lambda t: t.avg_quality_score or 0, reverse=True)
        
        return templates
    
    def update_template(self, template_id: str, **updates) -> bool:
        """
        Update an existing template.
        
        Args:
            template_id: Template ID to update
            **updates: Fields to update
            
        Returns:
            True if update successful, False otherwise
        """
        template = self.get_template(template_id)
        if not template:
            logger.error(f"Template not found: {template_id}")
            return False
        
        try:
            # Update fields
            for field, value in updates.items():
                if hasattr(template, field):
                    setattr(template, field, value)
            
            # Update timestamp
            from datetime import datetime
            template.updated_at = datetime.now()
            
            # Validate if template or variables were changed
            if 'template' in updates or 'variables' in updates:
                validation_errors = template.validate_variables()
                if validation_errors:
                    logger.error(f"Template validation failed: {validation_errors}")
                    return False
            
            # Save updated template
            if self._save_template(template):
                logger.info(f"Updated template: {template.name} ({template_id})")
                return True
            
            return False
            
        except Exception as e:
            logger.error(f"Failed to update template {template_id}: {e}")
            return False
    
    def delete_template(self, template_id: str) -> bool:
        """
        Delete a template.
        
        Args:
            template_id: Template ID to delete
            
        Returns:
            True if deletion successful, False otherwise
        """
        template = self.get_template(template_id)
        if not template:
            logger.error(f"Template not found: {template_id}")
            return False
        
        try:
            # Remove from storage
            file_path = self.storage_path / f"{template_id}.json"
            if file_path.exists():
                file_path.unlink()
            
            # Remove from cache
            del self._templates[template_id]
            
            logger.info(f"Deleted template: {template.name} ({template_id})")
            return True
            
        except Exception as e:
            logger.error(f"Failed to delete template {template_id}: {e}")
            return False
    
    def render_template(self, 
                       template_id: str, 
                       variables: Dict[str, str],
                       model_name: Optional[str] = None) -> Optional[str]:
        """
        Render a template with variables.
        
        Args:
            template_id: Template ID to render
            variables: Variable values
            model_name: Model name for model-specific optimizations
            
        Returns:
            Rendered prompt string or None if rendering failed
        """
        template = self.get_template(template_id)
        if not template:
            logger.error(f"Template not found: {template_id}")
            return None
        
        try:
            rendered = template.render(variables)
            
            # Apply model-specific optimizations if available
            if model_name:
                model_config = template.get_model_config(model_name)
                if model_config:
                    # Model-specific prompt modifications could be applied here
                    # For now, we just log that optimizations are available
                    logger.debug(f"Applied {model_name} optimizations to template {template_id}")
            
            return rendered
            
        except Exception as e:
            logger.error(f"Failed to render template {template_id}: {e}")
            return None
    
    def log_execution(self, context: PromptExecutionContext) -> None:
        """Log template execution for analytics."""
        self._execution_log.append(context)
        
        # Update template usage statistics
        template = self.get_template(context.template_id)
        if template:
            template.update_usage_stats(
                quality_score=context.quality_score,
                success=context.success
            )
            self._save_template(template)
    
    def get_template_analytics(self, template_id: str) -> Optional[Dict[str, Any]]:
        """Get analytics for a specific template."""
        template = self.get_template(template_id)
        if not template:
            return None
        
        # Filter execution log for this template
        executions = [ctx for ctx in self._execution_log if ctx.template_id == template_id]
        
        return {
            'template_id': template_id,
            'name': template.name,
            'usage_count': template.usage_count,
            'success_rate': template.success_rate,
            'avg_quality_score': template.avg_quality_score,
            'last_used': template.last_used.isoformat() if template.last_used else None,
            'recent_executions': len([e for e in executions if e.success]),
            'avg_execution_time': sum(e.execution_time for e in executions if e.execution_time) / len(executions) if executions else None
        }
    
    def get_popular_templates(self, limit: int = 10) -> List[PromptTemplate]:
        """Get most popular templates by usage count."""
        return self.list_templates(sort_by="usage_count")[:limit]
    
    def get_top_rated_templates(self, limit: int = 10) -> List[PromptTemplate]:
        """Get highest rated templates by quality score."""
        return self.list_templates(sort_by="avg_quality_score")[:limit]
    
    def search_templates(self, query: str) -> List[PromptTemplate]:
        """
        Search templates by name, description, or tags.
        
        Args:
            query: Search query string
            
        Returns:
            List of matching templates
        """
        query_lower = query.lower()
        matches = []
        
        for template in self._templates.values():
            # Search in name, description, and tags
            if (query_lower in template.name.lower() or
                query_lower in template.description.lower() or
                any(query_lower in tag.lower() for tag in template.tags)):
                matches.append(template)
        
        return matches
    
    def export_templates(self, export_path: str, template_ids: Optional[List[str]] = None) -> bool:
        """
        Export templates to a JSON file.
        
        Args:
            export_path: Path to export file
            template_ids: Specific template IDs to export (all if None)
            
        Returns:
            True if export successful, False otherwise
        """
        try:
            templates_to_export = []
            
            if template_ids:
                for template_id in template_ids:
                    template = self.get_template(template_id)
                    if template:
                        templates_to_export.append(template.to_dict())
            else:
                templates_to_export = [t.to_dict() for t in self._templates.values()]
            
            export_data = {
                'export_version': '1.0',
                'export_timestamp': str(self._get_timestamp()),
                'templates': templates_to_export
            }
            
            with open(export_path, 'w', encoding='utf-8') as f:
                json.dump(export_data, f, indent=2, ensure_ascii=False)
            
            logger.info(f"Exported {len(templates_to_export)} templates to {export_path}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to export templates: {e}")
            return False
    
    def import_templates(self, import_path: str, overwrite: bool = False) -> int:
        """
        Import templates from a JSON file.
        
        Args:
            import_path: Path to import file
            overwrite: Whether to overwrite existing templates
            
        Returns:
            Number of templates imported
        """
        try:
            with open(import_path, 'r', encoding='utf-8') as f:
                import_data = json.load(f)
            
            templates_data = import_data.get('templates', [])
            imported_count = 0
            
            for template_data in templates_data:
                try:
                    template = PromptTemplate.from_dict(template_data)
                    
                    # Check if template already exists
                    if template.id in self._templates and not overwrite:
                        logger.warning(f"Template {template.id} already exists, skipping")
                        continue
                    
                    # Save template
                    if self._save_template(template):
                        self._templates[template.id] = template
                        imported_count += 1
                        
                except Exception as e:
                    logger.error(f"Failed to import template: {e}")
                    continue
            
            logger.info(f"Imported {imported_count} templates from {import_path}")
            return imported_count
            
        except Exception as e:
            logger.error(f"Failed to import templates: {e}")
            return 0
    
    def _get_timestamp(self):
        """Get current timestamp."""
        from datetime import datetime
        return datetime.now()
    
    def get_stats(self) -> Dict[str, Any]:
        """Get overall template manager statistics."""
        # Calculate average quality score safely
        templates_with_scores = [t for t in self._templates.values() if t.avg_quality_score]
        avg_quality_score = 0
        if templates_with_scores:
            avg_quality_score = sum(t.avg_quality_score for t in templates_with_scores) / len(templates_with_scores)
        
        return {
            'total_templates': len(self._templates),
            'categories': {cat.value: len([t for t in self._templates.values() if t.category == cat]) 
                          for cat in PromptCategory},
            'total_executions': len(self._execution_log),
            'avg_quality_score': avg_quality_score,
            'most_used_template': max(self._templates.values(), key=lambda t: t.usage_count).name if self._templates else None
        }