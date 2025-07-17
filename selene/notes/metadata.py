"""
Frontmatter and metadata management for notes.

Handles YAML frontmatter, custom metadata, and Obsidian-specific properties.
"""

import yaml
import re
from datetime import datetime
from typing import Dict, Any, Optional, List, Union
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class NoteMetadata:
    """Represents note metadata and frontmatter."""
    title: Optional[str] = None
    created: Optional[datetime] = None
    modified: Optional[datetime] = None
    tags: List[str] = field(default_factory=list)
    aliases: List[str] = field(default_factory=list)
    author: Optional[str] = None
    source: Optional[str] = None
    status: Optional[str] = None
    priority: Optional[str] = None
    project: Optional[str] = None
    category: Optional[str] = None
    custom_fields: Dict[str, Any] = field(default_factory=dict)
    
    def __post_init__(self):
        """Set default values after initialization."""
        if self.created is None:
            self.created = datetime.now()
        if self.modified is None:
            self.modified = datetime.now()
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert metadata to dictionary for YAML serialization."""
        data = {}
        
        # Standard fields
        if self.title:
            data['title'] = self.title
        if self.created:
            data['created'] = self.created.isoformat()
        if self.modified:
            data['modified'] = self.modified.isoformat()
        if self.tags:
            data['tags'] = self.tags
        if self.aliases:
            data['aliases'] = self.aliases
        if self.author:
            data['author'] = self.author
        if self.source:
            data['source'] = self.source
        if self.status:
            data['status'] = self.status
        if self.priority:
            data['priority'] = self.priority
        if self.project:
            data['project'] = self.project
        if self.category:
            data['category'] = self.category
        
        # Custom fields
        data.update(self.custom_fields)
        
        return data
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "NoteMetadata":
        """Create metadata from dictionary."""
        # Parse datetime fields
        created = None
        if 'created' in data:
            if isinstance(data['created'], str):
                created = datetime.fromisoformat(data['created'])
            elif isinstance(data['created'], datetime):
                created = data['created']
        
        modified = None
        if 'modified' in data:
            if isinstance(data['modified'], str):
                modified = datetime.fromisoformat(data['modified'])
            elif isinstance(data['modified'], datetime):
                modified = data['modified']
        
        # Extract known fields
        known_fields = {
            'title', 'created', 'modified', 'tags', 'aliases', 
            'author', 'source', 'status', 'priority', 'project', 'category'
        }
        
        custom_fields = {k: v for k, v in data.items() if k not in known_fields}
        
        return cls(
            title=data.get('title'),
            created=created,
            modified=modified,
            tags=data.get('tags', []),
            aliases=data.get('aliases', []),
            author=data.get('author'),
            source=data.get('source'),
            status=data.get('status'),
            priority=data.get('priority'),
            project=data.get('project'),
            category=data.get('category'),
            custom_fields=custom_fields
        )
    
    def add_tag(self, tag: str) -> None:
        """Add a tag if not already present."""
        if tag not in self.tags:
            self.tags.append(tag)
    
    def add_alias(self, alias: str) -> None:
        """Add an alias if not already present."""
        if alias not in self.aliases:
            self.aliases.append(alias)
    
    def set_custom_field(self, key: str, value: Any) -> None:
        """Set a custom field."""
        self.custom_fields[key] = value
    
    def get_custom_field(self, key: str, default: Any = None) -> Any:
        """Get a custom field value."""
        return self.custom_fields.get(key, default)


class FrontmatterManager:
    """Manages YAML frontmatter in markdown files."""
    
    FRONTMATTER_REGEX = re.compile(r'^---\n(.*?)\n---\n', re.DOTALL)
    
    def __init__(self):
        """Initialize the frontmatter manager."""
        pass
    
    def extract_frontmatter(self, content: str) -> tuple[Optional[NoteMetadata], str]:
        """
        Extract frontmatter from markdown content.
        
        Args:
            content: The markdown content
            
        Returns:
            Tuple of (metadata, content_without_frontmatter)
        """
        match = self.FRONTMATTER_REGEX.match(content)
        if not match:
            return None, content
        
        try:
            yaml_content = match.group(1)
            frontmatter_data = yaml.safe_load(yaml_content)
            
            if not isinstance(frontmatter_data, dict):
                return None, content
            
            metadata = NoteMetadata.from_dict(frontmatter_data)
            content_without_frontmatter = content[match.end():]
            
            return metadata, content_without_frontmatter
            
        except yaml.YAMLError:
            return None, content
    
    def add_frontmatter(self, content: str, metadata: NoteMetadata) -> str:
        """
        Add frontmatter to markdown content.
        
        Args:
            content: The markdown content
            metadata: The metadata to add
            
        Returns:
            Content with frontmatter prepended
        """
        # Remove existing frontmatter if present
        _, clean_content = self.extract_frontmatter(content)
        
        # Generate YAML frontmatter
        yaml_content = yaml.dump(
            metadata.to_dict(),
            default_flow_style=False,
            allow_unicode=True,
            sort_keys=False
        )
        
        # Format frontmatter
        frontmatter = f"---\n{yaml_content}---\n\n"
        
        return frontmatter + clean_content
    
    def update_frontmatter(self, content: str, metadata: NoteMetadata) -> str:
        """
        Update existing frontmatter or add new frontmatter.
        
        Args:
            content: The markdown content
            metadata: The metadata to set
            
        Returns:
            Content with updated frontmatter
        """
        return self.add_frontmatter(content, metadata)
    
    def remove_frontmatter(self, content: str) -> str:
        """
        Remove frontmatter from markdown content.
        
        Args:
            content: The markdown content
            
        Returns:
            Content without frontmatter
        """
        _, clean_content = self.extract_frontmatter(content)
        return clean_content
    
    def has_frontmatter(self, content: str) -> bool:
        """
        Check if content has frontmatter.
        
        Args:
            content: The markdown content
            
        Returns:
            True if content has frontmatter
        """
        return self.FRONTMATTER_REGEX.match(content) is not None
    
    def create_metadata_from_content(self, content: str, title: Optional[str] = None) -> NoteMetadata:
        """
        Create metadata from content analysis.
        
        Args:
            content: The markdown content
            title: Optional title override
            
        Returns:
            Generated metadata
        """
        metadata = NoteMetadata()
        
        # Set title
        if title:
            metadata.title = title
        else:
            # Try to extract title from first header
            header_match = re.search(r'^#\s+(.+)$', content, re.MULTILINE)
            if header_match:
                metadata.title = header_match.group(1).strip()
        
        # Extract tags from content
        tag_pattern = r'#([a-zA-Z0-9_-]+)'
        tags = re.findall(tag_pattern, content)
        metadata.tags = list(set(tags))  # Remove duplicates
        
        # Set timestamps
        metadata.created = datetime.now()
        metadata.modified = datetime.now()
        
        return metadata
    
    def merge_metadata(self, existing: NoteMetadata, new: NoteMetadata) -> NoteMetadata:
        """
        Merge two metadata objects, with new taking precedence.
        
        Args:
            existing: The existing metadata
            new: The new metadata to merge in
            
        Returns:
            Merged metadata
        """
        merged = NoteMetadata()
        
        # Use new values if present, otherwise use existing
        merged.title = new.title or existing.title
        merged.created = existing.created or new.created  # Keep original creation time
        merged.modified = new.modified or datetime.now()  # Always update modified time
        
        # Merge lists
        merged.tags = list(set(existing.tags + new.tags))
        merged.aliases = list(set(existing.aliases + new.aliases))
        
        # Use new values for other fields
        merged.author = new.author or existing.author
        merged.source = new.source or existing.source
        merged.status = new.status or existing.status
        merged.priority = new.priority or existing.priority
        merged.project = new.project or existing.project
        merged.category = new.category or existing.category
        
        # Merge custom fields
        merged.custom_fields = {**existing.custom_fields, **new.custom_fields}
        
        return merged
    
    def validate_metadata(self, metadata: NoteMetadata) -> List[str]:
        """
        Validate metadata and return list of issues.
        
        Args:
            metadata: The metadata to validate
            
        Returns:
            List of validation issues (empty if valid)
        """
        issues = []
        
        # Check title
        if not metadata.title or not metadata.title.strip():
            issues.append("Title is required")
        
        # Check tags format
        for tag in metadata.tags:
            if not re.match(r'^[a-zA-Z0-9_-]+$', tag):
                issues.append(f"Invalid tag format: {tag}")
        
        # Check dates
        if metadata.created and metadata.modified:
            if metadata.created > metadata.modified:
                issues.append("Created date cannot be after modified date")
        
        return issues