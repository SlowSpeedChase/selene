"""
Main note formatting system for SMS-23.

Provides comprehensive note formatting capabilities for transforming AI-processed
content into well-structured Obsidian-compatible notes.
"""

import re
from datetime import datetime
from typing import Dict, Any, Optional, List, Union, Callable
from dataclasses import dataclass, field
from pathlib import Path
from enum import Enum

from .metadata import NoteMetadata, FrontmatterManager
from .structure import NoteBuilder, NoteStructure, NoteSection, SectionType


class NoteFormat(Enum):
    """Note formatting styles."""
    STANDARD = "standard"
    RESEARCH = "research"
    MEETING = "meeting"
    DAILY = "daily"
    PROJECT = "project"
    REFERENCE = "reference"
    TEMPLATE = "template"


@dataclass
class NoteTemplate:
    """Represents a note template."""
    name: str
    format: NoteFormat
    sections: List[str] = field(default_factory=list)
    metadata_template: Optional[Dict[str, Any]] = None
    content_template: Optional[str] = None
    
    def __post_init__(self):
        """Set default sections based on format."""
        if not self.sections:
            self.sections = self._get_default_sections()
    
    def _get_default_sections(self) -> List[str]:
        """Get default sections for the format."""
        defaults = {
            NoteFormat.STANDARD: ["Summary", "Content", "References"],
            NoteFormat.RESEARCH: ["Abstract", "Key Points", "Analysis", "Questions", "References"],
            NoteFormat.MEETING: ["Attendees", "Agenda", "Discussion", "Action Items", "Next Steps"],
            NoteFormat.DAILY: ["Goals", "Completed", "Notes", "Tomorrow"],
            NoteFormat.PROJECT: ["Overview", "Objectives", "Tasks", "Timeline", "Resources"],
            NoteFormat.REFERENCE: ["Definition", "Usage", "Examples", "Related"],
            NoteFormat.TEMPLATE: ["Header", "Content", "Footer"]
        }
        return defaults.get(self.format, ["Content"])


class NoteFormatter:
    """Main note formatting system for SMS-23."""
    
    def __init__(self):
        """Initialize the note formatter."""
        self.frontmatter_manager = FrontmatterManager()
        self.templates: Dict[str, NoteTemplate] = {}
        self.formatters: Dict[str, Callable] = {}
        self._load_default_templates()
        self._load_default_formatters()
    
    def _load_default_templates(self):
        """Load default note templates."""
        templates = [
            NoteTemplate(
                name="standard",
                format=NoteFormat.STANDARD,
                sections=["Summary", "Content", "References"]
            ),
            NoteTemplate(
                name="research",
                format=NoteFormat.RESEARCH,
                sections=["Abstract", "Key Points", "Analysis", "Questions", "References"],
                metadata_template={"category": "research", "status": "draft"}
            ),
            NoteTemplate(
                name="meeting",
                format=NoteFormat.MEETING,
                sections=["Attendees", "Agenda", "Discussion", "Action Items", "Next Steps"],
                metadata_template={"category": "meeting", "status": "completed"}
            ),
            NoteTemplate(
                name="daily",
                format=NoteFormat.DAILY,
                sections=["Goals", "Completed", "Notes", "Tomorrow"],
                metadata_template={"category": "daily", "status": "active"}
            ),
            NoteTemplate(
                name="project",
                format=NoteFormat.PROJECT,
                sections=["Overview", "Objectives", "Tasks", "Timeline", "Resources"],
                metadata_template={"category": "project", "status": "planning"}
            ),
            NoteTemplate(
                name="reference",
                format=NoteFormat.REFERENCE,
                sections=["Definition", "Usage", "Examples", "Related"],
                metadata_template={"category": "reference", "status": "complete"}
            )
        ]
        
        for template in templates:
            self.templates[template.name] = template
    
    def _load_default_formatters(self):
        """Load default content formatters."""
        self.formatters.update({
            "ai_summary": self._format_ai_summary,
            "ai_insights": self._format_ai_insights,
            "ai_questions": self._format_ai_questions,
            "ai_enhanced": self._format_ai_enhanced,
            "meeting_notes": self._format_meeting_notes,
            "research_notes": self._format_research_notes
        })
    
    def format_note(
        self,
        content: str,
        template_name: str = "standard",
        metadata: Optional[NoteMetadata] = None,
        title: Optional[str] = None,
        formatter_name: Optional[str] = None,
        **kwargs
    ) -> str:
        """
        Format content into a well-structured note.
        
        Args:
            content: The raw content to format
            template_name: Name of the template to use
            metadata: Optional metadata to include
            title: Optional title for the note
            formatter_name: Optional specific formatter to use
            **kwargs: Additional formatting options
            
        Returns:
            Formatted note content with frontmatter
        """
        # Get template
        template = self.templates.get(template_name, self.templates["standard"])
        
        # Create or update metadata
        if metadata is None:
            metadata = NoteMetadata()
        
        # Set title if provided
        if title:
            metadata.title = title
        elif not metadata.title:
            metadata.title = self._extract_title(content)
        
        # Apply template metadata
        if template.metadata_template:
            for key, value in template.metadata_template.items():
                if not hasattr(metadata, key) or getattr(metadata, key) is None:
                    setattr(metadata, key, value)
        
        # Format content using specific formatter if provided
        if formatter_name and formatter_name in self.formatters:
            formatted_content = self.formatters[formatter_name](content, template, **kwargs)
        else:
            formatted_content = self._format_with_template(content, template, **kwargs)
        
        # Add frontmatter
        final_content = self.frontmatter_manager.add_frontmatter(formatted_content, metadata)
        
        return final_content
    
    def _format_with_template(self, content: str, template: NoteTemplate, **kwargs) -> str:
        """Format content using a template structure."""
        builder = NoteBuilder()
        
        # Add title if available
        if template.metadata_template and template.metadata_template.get("title"):
            builder.add_header(template.metadata_template["title"], level=1)
        
        # Split content into sections based on template
        if len(template.sections) == 1:
            # Single section template
            builder.add_header(template.sections[0], level=2)
            builder.add_content(content)
        else:
            # Multi-section template
            content_parts = self._split_content_for_sections(content, template.sections)
            
            for section_name, section_content in zip(template.sections, content_parts):
                builder.add_header(section_name, level=2)
                if section_content:
                    builder.add_content(section_content)
                else:
                    builder.add_content("_To be added_")
        
        return builder.build()
    
    def _split_content_for_sections(self, content: str, sections: List[str]) -> List[str]:
        """Split content into parts for template sections."""
        # For now, put all content in the first section
        # TODO: Implement intelligent content splitting based on section types
        result = [content if i == 0 else "" for i in range(len(sections))]
        return result
    
    def _extract_title(self, content: str) -> str:
        """Extract title from content."""
        # Try to find first header
        header_match = re.search(r'^#\s+(.+)$', content, re.MULTILINE)
        if header_match:
            return header_match.group(1).strip()
        
        # Try to find first line that looks like a title
        lines = content.split('\n')
        for line in lines:
            line = line.strip()
            if line and len(line) < 100 and not line.startswith('#'):
                return line
        
        return "Untitled Note"
    
    def _format_ai_summary(self, content: str, template: NoteTemplate, **kwargs) -> str:
        """Format AI summary content."""
        builder = NoteBuilder()
        builder.add_header("Summary", level=1)
        builder.add_content(content)
        
        # Add metadata section
        if kwargs.get("source_file"):
            builder.add_header("Source", level=2)
            builder.add_content(f"Original file: {kwargs['source_file']}")
        
        return builder.build()
    
    def _format_ai_insights(self, content: str, template: NoteTemplate, **kwargs) -> str:
        """Format AI insights content."""
        builder = NoteBuilder()
        builder.add_header("Key Insights", level=1)
        
        # Try to split insights into a list if they're numbered or bulleted
        insights = self._extract_list_items(content)
        if insights:
            builder.add_list(insights)
        else:
            builder.add_content(content)
        
        return builder.build()
    
    def _format_ai_questions(self, content: str, template: NoteTemplate, **kwargs) -> str:
        """Format AI questions content."""
        builder = NoteBuilder()
        builder.add_header("Questions", level=1)
        
        # Try to extract questions as a list
        questions = self._extract_list_items(content)
        if questions:
            builder.add_list(questions)
        else:
            builder.add_content(content)
        
        return builder.build()
    
    def _format_ai_enhanced(self, content: str, template: NoteTemplate, **kwargs) -> str:
        """Format AI enhanced content."""
        # Enhanced content should maintain its structure
        return content
    
    def _format_meeting_notes(self, content: str, template: NoteTemplate, **kwargs) -> str:
        """Format meeting notes content."""
        builder = NoteBuilder()
        
        # Add meeting header
        meeting_date = kwargs.get("date", datetime.now().strftime("%Y-%m-%d"))
        builder.add_header(f"Meeting Notes - {meeting_date}", level=1)
        
        # Add template sections
        for section in template.sections:
            builder.add_header(section, level=2)
            if section == "Discussion":
                builder.add_content(content)
            else:
                builder.add_content("_To be added_")
        
        return builder.build()
    
    def _format_research_notes(self, content: str, template: NoteTemplate, **kwargs) -> str:
        """Format research notes content."""
        builder = NoteBuilder()
        builder.add_header("Research Notes", level=1)
        
        # Add abstract
        builder.add_header("Abstract", level=2)
        abstract = self._extract_abstract(content)
        builder.add_content(abstract)
        
        # Add key points
        builder.add_header("Key Points", level=2)
        key_points = self._extract_key_points(content)
        if key_points:
            builder.add_list(key_points)
        else:
            builder.add_content(content)
        
        # Add analysis section
        builder.add_header("Analysis", level=2)
        builder.add_content("_Analysis to be added_")
        
        return builder.build()
    
    def _extract_list_items(self, content: str) -> List[str]:
        """Extract list items from content."""
        items = []
        
        # Try numbered lists
        numbered_pattern = r'^\s*\d+\.\s*(.+)$'
        numbered_matches = re.findall(numbered_pattern, content, re.MULTILINE)
        if numbered_matches:
            return [item.strip() for item in numbered_matches]
        
        # Try bullet lists
        bullet_pattern = r'^\s*[-*•]\s*(.+)$'
        bullet_matches = re.findall(bullet_pattern, content, re.MULTILINE)
        if bullet_matches:
            return [item.strip() for item in bullet_matches]
        
        # Try to split by sentences if no lists found
        sentences = re.split(r'[.!?]+', content)
        if len(sentences) > 1:
            return [s.strip() for s in sentences if s.strip()]
        
        return []
    
    def _extract_abstract(self, content: str) -> str:
        """Extract abstract from content."""
        # Take first paragraph or first 200 characters
        paragraphs = content.split('\n\n')
        if paragraphs:
            abstract = paragraphs[0].strip()
            if len(abstract) > 200:
                abstract = abstract[:200] + "..."
            return abstract
        return content[:200] + "..." if len(content) > 200 else content
    
    def _extract_key_points(self, content: str) -> List[str]:
        """Extract key points from content."""
        # Try to find existing list items first
        items = self._extract_list_items(content)
        if items:
            return items
        
        # Split into sentences and take first few
        sentences = re.split(r'[.!?]+', content)
        key_sentences = [s.strip() for s in sentences[:5] if s.strip()]
        return key_sentences
    
    def add_template(self, template: NoteTemplate) -> None:
        """Add a custom template."""
        self.templates[template.name] = template
    
    def add_formatter(self, name: str, formatter: Callable) -> None:
        """Add a custom formatter."""
        self.formatters[name] = formatter
    
    def get_template(self, name: str) -> Optional[NoteTemplate]:
        """Get a template by name."""
        return self.templates.get(name)
    
    def list_templates(self) -> List[str]:
        """List available template names."""
        return list(self.templates.keys())
    
    def list_formatters(self) -> List[str]:
        """List available formatter names."""
        return list(self.formatters.keys())
    
    def update_note(
        self,
        existing_content: str,
        new_content: str,
        merge_strategy: str = "append",
        section_name: Optional[str] = None
    ) -> str:
        """
        Update an existing note with new content.
        
        Args:
            existing_content: The existing note content
            new_content: The new content to add
            merge_strategy: How to merge ("append", "prepend", "replace", "merge_sections")
            section_name: Specific section to update
            
        Returns:
            Updated note content
        """
        # Extract existing frontmatter
        existing_metadata, existing_body = self.frontmatter_manager.extract_frontmatter(existing_content)
        
        if merge_strategy == "replace":
            # Replace entire content
            if existing_metadata:
                existing_metadata.modified = datetime.now()
                return self.frontmatter_manager.add_frontmatter(new_content, existing_metadata)
            else:
                return new_content
        
        elif merge_strategy == "append":
            # Append to end
            combined_content = existing_body + "\n\n" + new_content
            if existing_metadata:
                existing_metadata.modified = datetime.now()
                return self.frontmatter_manager.add_frontmatter(combined_content, existing_metadata)
            else:
                return combined_content
        
        elif merge_strategy == "prepend":
            # Prepend to beginning
            combined_content = new_content + "\n\n" + existing_body
            if existing_metadata:
                existing_metadata.modified = datetime.now()
                return self.frontmatter_manager.add_frontmatter(combined_content, existing_metadata)
            else:
                return combined_content
        
        elif merge_strategy == "merge_sections" and section_name:
            # Merge into specific section
            structure = NoteStructure(existing_body)
            sections = structure.sections
            
            # Find the target section
            target_section_index = None
            for i, section in enumerate(sections):
                if section.type == SectionType.HEADER and section.content == section_name:
                    target_section_index = i
                    break
            
            if target_section_index is not None:
                # Add content after the target header
                new_content_section = NoteSection(
                    type=SectionType.CONTENT,
                    content=new_content
                )
                sections.insert(target_section_index + 1, new_content_section)
                
                # Rebuild content
                combined_content = "\n\n".join(section.to_markdown() for section in sections)
                
                if existing_metadata:
                    existing_metadata.modified = datetime.now()
                    return self.frontmatter_manager.add_frontmatter(combined_content, existing_metadata)
                else:
                    return combined_content
            else:
                # Section not found, append to end
                return self.update_note(existing_content, new_content, "append")
        
        else:
            # Default to append
            return self.update_note(existing_content, new_content, "append")
    
    def validate_note(self, content: str) -> Dict[str, Any]:
        """
        Validate a note and return validation results.
        
        Args:
            content: The note content to validate
            
        Returns:
            Validation results with issues and suggestions
        """
        issues = []
        suggestions = []
        
        # Check frontmatter
        metadata, body = self.frontmatter_manager.extract_frontmatter(content)
        if metadata:
            metadata_issues = self.frontmatter_manager.validate_metadata(metadata)
            issues.extend(metadata_issues)
        else:
            suggestions.append("Consider adding frontmatter with metadata")
        
        # Check structure
        structure = NoteStructure(body)
        
        # Check for title
        headers = structure.get_headers()
        if not headers:
            issues.append("Note has no headers")
        elif headers[0][0] != 1:
            suggestions.append("Consider starting with a level 1 header")
        
        # Check for empty sections
        empty_sections = 0
        for section in structure.sections:
            if section.type == SectionType.CONTENT and not section.content.strip():
                empty_sections += 1
        
        if empty_sections > 0:
            suggestions.append(f"Found {empty_sections} empty content sections")
        
        # Generate summary
        summary = structure.summary()
        
        return {
            "valid": len(issues) == 0,
            "issues": issues,
            "suggestions": suggestions,
            "structure_summary": summary,
            "has_frontmatter": metadata is not None,
            "title": metadata.title if metadata else None
        }