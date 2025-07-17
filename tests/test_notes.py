"""
Tests for the note formatting system (SMS-23).
"""

import pytest
from datetime import datetime
from unittest.mock import patch

from selene.notes import (
    NoteFormatter, NoteTemplate, NoteStructure, NoteBuilder,
    FrontmatterManager, NoteMetadata, NoteSection, SectionType,
    NoteFormat
)


class TestNoteMetadata:
    """Test NoteMetadata class."""
    
    def test_default_metadata(self):
        """Test default metadata creation."""
        metadata = NoteMetadata()
        assert metadata.title is None
        assert metadata.created is not None
        assert metadata.modified is not None
        assert metadata.tags == []
        assert metadata.aliases == []
        assert metadata.custom_fields == {}
    
    def test_metadata_with_values(self):
        """Test metadata with custom values."""
        metadata = NoteMetadata(
            title="Test Note",
            tags=["test", "example"],
            aliases=["test-note"],
            author="Test Author",
            status="draft"
        )
        assert metadata.title == "Test Note"
        assert metadata.tags == ["test", "example"]
        assert metadata.aliases == ["test-note"]
        assert metadata.author == "Test Author"
        assert metadata.status == "draft"
    
    def test_to_dict(self):
        """Test metadata to dictionary conversion."""
        metadata = NoteMetadata(
            title="Test Note",
            tags=["test"],
            custom_fields={"priority": "high"}
        )
        data = metadata.to_dict()
        assert data["title"] == "Test Note"
        assert data["tags"] == ["test"]
        assert data["priority"] == "high"
        assert "created" in data
        assert "modified" in data
    
    def test_from_dict(self):
        """Test metadata from dictionary creation."""
        data = {
            "title": "Test Note",
            "tags": ["test"],
            "author": "Test Author",
            "custom_field": "value"
        }
        metadata = NoteMetadata.from_dict(data)
        assert metadata.title == "Test Note"
        assert metadata.tags == ["test"]
        assert metadata.author == "Test Author"
        assert metadata.custom_fields["custom_field"] == "value"
    
    def test_add_tag(self):
        """Test adding tags."""
        metadata = NoteMetadata()
        metadata.add_tag("test")
        metadata.add_tag("example")
        metadata.add_tag("test")  # Duplicate
        assert metadata.tags == ["test", "example"]
    
    def test_add_alias(self):
        """Test adding aliases."""
        metadata = NoteMetadata()
        metadata.add_alias("test-note")
        metadata.add_alias("example-note")
        metadata.add_alias("test-note")  # Duplicate
        assert metadata.aliases == ["test-note", "example-note"]
    
    def test_custom_fields(self):
        """Test custom field operations."""
        metadata = NoteMetadata()
        metadata.set_custom_field("priority", "high")
        metadata.set_custom_field("project", "selene")
        
        assert metadata.get_custom_field("priority") == "high"
        assert metadata.get_custom_field("project") == "selene"
        assert metadata.get_custom_field("nonexistent") is None
        assert metadata.get_custom_field("nonexistent", "default") == "default"


class TestFrontmatterManager:
    """Test FrontmatterManager class."""
    
    def test_extract_frontmatter(self):
        """Test frontmatter extraction."""
        content = """---
title: Test Note
tags: [test, example]
author: Test Author
---

This is the content of the note.
"""
        manager = FrontmatterManager()
        metadata, body = manager.extract_frontmatter(content)
        
        assert metadata is not None
        assert metadata.title == "Test Note"
        assert metadata.tags == ["test", "example"]
        assert metadata.author == "Test Author"
        assert body.strip() == "This is the content of the note."
    
    def test_extract_no_frontmatter(self):
        """Test extraction when no frontmatter exists."""
        content = "This is just regular content."
        manager = FrontmatterManager()
        metadata, body = manager.extract_frontmatter(content)
        
        assert metadata is None
        assert body == content
    
    def test_add_frontmatter(self):
        """Test adding frontmatter to content."""
        content = "This is the content."
        metadata = NoteMetadata(title="Test Note", tags=["test"])
        manager = FrontmatterManager()
        
        result = manager.add_frontmatter(content, metadata)
        
        assert result.startswith("---\n")
        assert "title: Test Note" in result
        assert "tags:\n- test" in result
        assert result.endswith("This is the content.")
    
    def test_update_frontmatter(self):
        """Test updating existing frontmatter."""
        content = """---
title: Old Title
tags: [old]
---

Content here.
"""
        new_metadata = NoteMetadata(title="New Title", tags=["new"])
        manager = FrontmatterManager()
        
        result = manager.update_frontmatter(content, new_metadata)
        
        assert "title: New Title" in result
        assert "tags:\n- new" in result
        assert "Content here." in result
    
    def test_remove_frontmatter(self):
        """Test removing frontmatter."""
        content = """---
title: Test Note
---

Content here.
"""
        manager = FrontmatterManager()
        result = manager.remove_frontmatter(content)
        
        assert result.strip() == "Content here."
    
    def test_has_frontmatter(self):
        """Test frontmatter detection."""
        manager = FrontmatterManager()
        
        with_frontmatter = """---
title: Test
---
Content"""
        without_frontmatter = "Just content"
        
        assert manager.has_frontmatter(with_frontmatter) is True
        assert manager.has_frontmatter(without_frontmatter) is False
    
    def test_create_metadata_from_content(self):
        """Test metadata creation from content analysis."""
        content = """# Test Note

This is a note about #testing and #examples.
"""
        manager = FrontmatterManager()
        metadata = manager.create_metadata_from_content(content)
        
        assert metadata.title == "Test Note"
        assert "testing" in metadata.tags
        assert "examples" in metadata.tags
    
    def test_merge_metadata(self):
        """Test metadata merging."""
        existing = NoteMetadata(
            title="Old Title",
            tags=["old"],
            created=datetime(2023, 1, 1)
        )
        new = NoteMetadata(
            title="New Title",
            tags=["new"],
            author="New Author"
        )
        
        manager = FrontmatterManager()
        merged = manager.merge_metadata(existing, new)
        
        assert merged.title == "New Title"
        assert merged.created == datetime(2023, 1, 1)  # Keep original
        assert "old" in merged.tags
        assert "new" in merged.tags
        assert merged.author == "New Author"
    
    def test_validate_metadata(self):
        """Test metadata validation."""
        manager = FrontmatterManager()
        
        # Valid metadata
        valid_metadata = NoteMetadata(title="Valid Title", tags=["valid"])
        issues = manager.validate_metadata(valid_metadata)
        assert len(issues) == 0
        
        # Invalid metadata
        invalid_metadata = NoteMetadata(title="", tags=["invalid@tag"])
        issues = manager.validate_metadata(invalid_metadata)
        assert len(issues) > 0
        assert any("Title is required" in issue for issue in issues)
        assert any("Invalid tag format" in issue for issue in issues)


class TestNoteSection:
    """Test NoteSection class."""
    
    def test_header_section(self):
        """Test header section creation."""
        section = NoteSection(
            type=SectionType.HEADER,
            content="Test Header",
            level=2
        )
        markdown = section.to_markdown()
        assert markdown == "## Test Header"
    
    def test_content_section(self):
        """Test content section creation."""
        section = NoteSection(
            type=SectionType.CONTENT,
            content="This is content."
        )
        markdown = section.to_markdown()
        assert markdown == "This is content."
    
    def test_quote_section(self):
        """Test quote section creation."""
        section = NoteSection(
            type=SectionType.QUOTE,
            content="This is a quote\nwith multiple lines"
        )
        markdown = section.to_markdown()
        assert markdown == "> This is a quote\n> with multiple lines"
    
    def test_code_section(self):
        """Test code section creation."""
        section = NoteSection(
            type=SectionType.CODE,
            content="print('Hello')",
            metadata={"language": "python"}
        )
        markdown = section.to_markdown()
        assert markdown == "```python\nprint('Hello')\n```"
    
    def test_divider_section(self):
        """Test divider section creation."""
        section = NoteSection(
            type=SectionType.DIVIDER,
            content=""
        )
        markdown = section.to_markdown()
        assert markdown == "---"


class TestNoteBuilder:
    """Test NoteBuilder class."""
    
    def test_empty_builder(self):
        """Test empty builder."""
        builder = NoteBuilder()
        result = builder.build()
        assert result == ""
    
    def test_add_header(self):
        """Test adding headers."""
        builder = NoteBuilder()
        builder.add_header("Title", 1)
        builder.add_header("Subtitle", 2)
        
        result = builder.build()
        assert "# Title" in result
        assert "## Subtitle" in result
    
    def test_add_content(self):
        """Test adding content."""
        builder = NoteBuilder()
        builder.add_content("This is content.")
        
        result = builder.build()
        assert "This is content." in result
    
    def test_add_list(self):
        """Test adding lists."""
        builder = NoteBuilder()
        builder.add_list(["Item 1", "Item 2", "Item 3"])
        builder.add_list(["First", "Second"], ordered=True)
        
        result = builder.build()
        assert "- Item 1" in result
        assert "- Item 2" in result
        assert "1. First" in result
        assert "2. Second" in result
    
    def test_add_table(self):
        """Test adding tables."""
        builder = NoteBuilder()
        builder.add_table(
            headers=["Name", "Age"],
            rows=[["Alice", "25"], ["Bob", "30"]]
        )
        
        result = builder.build()
        assert "| Name | Age |" in result
        assert "| --- | --- |" in result
        assert "| Alice | 25 |" in result
        assert "| Bob | 30 |" in result
    
    def test_add_quote(self):
        """Test adding quotes."""
        builder = NoteBuilder()
        builder.add_quote("This is a quote")
        
        result = builder.build()
        assert "> This is a quote" in result
    
    def test_add_code(self):
        """Test adding code blocks."""
        builder = NoteBuilder()
        builder.add_code("print('Hello')", "python")
        
        result = builder.build()
        assert "```python" in result
        assert "print('Hello')" in result
        assert "```" in result
    
    def test_add_divider(self):
        """Test adding dividers."""
        builder = NoteBuilder()
        builder.add_divider()
        
        result = builder.build()
        assert "---" in result
    
    def test_complex_note(self):
        """Test building a complex note."""
        builder = NoteBuilder()
        builder.add_header("My Note", 1)
        builder.add_content("This is the introduction.")
        builder.add_header("Section 1", 2)
        builder.add_list(["Point 1", "Point 2"])
        builder.add_divider()
        builder.add_header("Code Example", 2)
        builder.add_code("print('Hello')", "python")
        
        result = builder.build()
        
        assert "# My Note" in result
        assert "## Section 1" in result
        assert "- Point 1" in result
        assert "---" in result
        assert "```python" in result
    
    def test_clear_builder(self):
        """Test clearing the builder."""
        builder = NoteBuilder()
        builder.add_header("Title", 1)
        builder.add_content("Content")
        
        builder.clear()
        result = builder.build()
        assert result == ""


class TestNoteStructure:
    """Test NoteStructure class."""
    
    def test_parse_headers(self):
        """Test parsing headers from markdown."""
        content = """# Title
## Subtitle
### Subsubtitle
Content here.
"""
        structure = NoteStructure(content)
        headers = structure.get_headers()
        
        assert len(headers) == 3
        assert headers[0] == (1, "Title")
        assert headers[1] == (2, "Subtitle")
        assert headers[2] == (3, "Subsubtitle")
    
    def test_parse_content(self):
        """Test parsing content sections."""
        content = """# Title
This is content.

## Section
More content here.
"""
        structure = NoteStructure(content)
        sections = structure.sections
        
        # Should have header, content, header, content
        assert len(sections) >= 4
        assert sections[0].type == SectionType.HEADER
        assert sections[1].type == SectionType.CONTENT
        assert sections[2].type == SectionType.HEADER
        assert sections[3].type == SectionType.CONTENT
    
    def test_parse_code_blocks(self):
        """Test parsing code blocks."""
        content = """# Title
```python
print('Hello')
```
"""
        structure = NoteStructure(content)
        code_sections = [s for s in structure.sections if s.type == SectionType.CODE]
        
        assert len(code_sections) == 1
        assert code_sections[0].content == "print('Hello')"
        assert code_sections[0].metadata["language"] == "python"
    
    def test_parse_dividers(self):
        """Test parsing dividers."""
        content = """# Title
Content above.
---
Content below.
"""
        structure = NoteStructure(content)
        dividers = [s for s in structure.sections if s.type == SectionType.DIVIDER]
        
        assert len(dividers) == 1
    
    def test_table_of_contents(self):
        """Test table of contents generation."""
        content = """# Title
## Section 1
### Subsection 1.1
## Section 2
"""
        structure = NoteStructure(content)
        toc = structure.get_table_of_contents()
        
        assert "- [Title](#title)" in toc
        assert "  - [Section 1](#section-1)" in toc
        assert "    - [Subsection 1.1](#subsection-11)" in toc
        assert "  - [Section 2](#section-2)" in toc
    
    def test_get_content_after_header(self):
        """Test getting content after specific header."""
        content = """# Title
Introduction.

## Section 1
Content for section 1.
More content.

## Section 2
Different content.
"""
        structure = NoteStructure(content)
        section1_content = structure.get_content_after_header("Section 1")
        
        assert "Content for section 1." in section1_content
        assert "More content." in section1_content
        assert "Different content." not in section1_content
    
    def test_rebuild(self):
        """Test rebuilding markdown from structure."""
        content = """# Title
Content here.

## Section
More content.
"""
        structure = NoteStructure(content)
        rebuilt = structure.rebuild()
        
        # Should contain the same information
        assert "# Title" in rebuilt
        assert "## Section" in rebuilt
        assert "Content here." in rebuilt
        assert "More content." in rebuilt
    
    def test_summary(self):
        """Test structure summary."""
        content = """# Title
Content.

## Section
More content.

```python
code()
```

> Quote

---
"""
        structure = NoteStructure(content)
        summary = structure.summary()
        
        assert summary["headers"] == 2
        assert summary["content_sections"] >= 2
        assert summary["code_blocks"] == 1
        assert summary["quotes"] == 1
        assert summary["dividers"] == 1


class TestNoteTemplate:
    """Test NoteTemplate class."""
    
    def test_default_template(self):
        """Test default template creation."""
        template = NoteTemplate(
            name="test",
            format=NoteFormat.STANDARD
        )
        
        assert template.name == "test"
        assert template.format == NoteFormat.STANDARD
        assert template.sections == ["Summary", "Content", "References"]
    
    def test_custom_template(self):
        """Test custom template creation."""
        template = NoteTemplate(
            name="custom",
            format=NoteFormat.MEETING,
            sections=["Custom Section 1", "Custom Section 2"],
            metadata_template={"status": "draft"}
        )
        
        assert template.name == "custom"
        assert template.sections == ["Custom Section 1", "Custom Section 2"]
        assert template.metadata_template["status"] == "draft"
    
    def test_format_defaults(self):
        """Test default sections for different formats."""
        research_template = NoteTemplate("research", NoteFormat.RESEARCH)
        meeting_template = NoteTemplate("meeting", NoteFormat.MEETING)
        
        assert "Abstract" in research_template.sections
        assert "Attendees" in meeting_template.sections


class TestNoteFormatter:
    """Test NoteFormatter class."""
    
    def test_basic_formatting(self):
        """Test basic note formatting."""
        formatter = NoteFormatter()
        content = "This is some content to format."
        
        result = formatter.format_note(content)
        
        assert "---" in result  # Has frontmatter
        assert "This is some content to format." in result
        assert "## Content" in result or "## Summary" in result
    
    def test_format_with_template(self):
        """Test formatting with specific template."""
        formatter = NoteFormatter()
        content = "Meeting discussion content."
        
        result = formatter.format_note(content, template_name="meeting")
        
        assert "## Attendees" in result
        assert "## Discussion" in result
        assert "## Action Items" in result
    
    def test_format_with_metadata(self):
        """Test formatting with custom metadata."""
        formatter = NoteFormatter()
        content = "Content here."
        metadata = NoteMetadata(title="Custom Title", tags=["custom"])
        
        result = formatter.format_note(content, metadata=metadata)
        
        assert "title: Custom Title" in result
        assert "tags:\n- custom" in result
    
    def test_format_with_title(self):
        """Test formatting with specific title."""
        formatter = NoteFormatter()
        content = "Content here."
        
        result = formatter.format_note(content, title="Specific Title")
        
        assert "title: Specific Title" in result
    
    def test_ai_summary_formatter(self):
        """Test AI summary formatter."""
        formatter = NoteFormatter()
        content = "This is a summary of the content."
        
        result = formatter.format_note(
            content,
            formatter_name="ai_summary",
            source_file="original.md"
        )
        
        assert "# Summary" in result
        assert "## Source" in result
        assert "original.md" in result
    
    def test_ai_insights_formatter(self):
        """Test AI insights formatter."""
        formatter = NoteFormatter()
        content = "1. First insight\n2. Second insight\n3. Third insight"
        
        result = formatter.format_note(content, formatter_name="ai_insights")
        
        assert "# Key Insights" in result
        assert "- First insight" in result
        assert "- Second insight" in result
    
    def test_ai_questions_formatter(self):
        """Test AI questions formatter."""
        formatter = NoteFormatter()
        content = "- What is the main point?\n- How does this relate?\n- What are the implications?"
        
        result = formatter.format_note(content, formatter_name="ai_questions")
        
        assert "# Questions" in result
        assert "- What is the main point?" in result
    
    def test_update_note_append(self):
        """Test updating note with append strategy."""
        formatter = NoteFormatter()
        existing = """---
title: Original Note
---

Original content."""
        
        new_content = "New content to add."
        
        result = formatter.update_note(existing, new_content, "append")
        
        assert "Original content." in result
        assert "New content to add." in result
        assert result.index("Original content.") < result.index("New content to add.")
    
    def test_update_note_prepend(self):
        """Test updating note with prepend strategy."""
        formatter = NoteFormatter()
        existing = """---
title: Original Note
---

Original content."""
        
        new_content = "New content to add."
        
        result = formatter.update_note(existing, new_content, "prepend")
        
        assert "Original content." in result
        assert "New content to add." in result
        assert result.index("New content to add.") < result.index("Original content.")
    
    def test_update_note_replace(self):
        """Test updating note with replace strategy."""
        formatter = NoteFormatter()
        existing = """---
title: Original Note
---

Original content."""
        
        new_content = "Replacement content."
        
        result = formatter.update_note(existing, new_content, "replace")
        
        assert "Replacement content." in result
        assert "Original content." not in result
        assert "title: Original Note" in result
    
    def test_update_note_merge_sections(self):
        """Test updating note with section merge strategy."""
        formatter = NoteFormatter()
        existing = """---
title: Original Note
---

# Title

## Section 1
Original content.

## Section 2
Other content."""
        
        new_content = "New content for section 1."
        
        result = formatter.update_note(
            existing, 
            new_content, 
            "merge_sections", 
            section_name="Section 1"
        )
        
        assert "Original content." in result
        assert "New content for section 1." in result
        assert "Other content." in result
    
    def test_validate_note(self):
        """Test note validation."""
        formatter = NoteFormatter()
        
        # Valid note
        valid_note = """---
title: Valid Note
tags: [test]
---

# Valid Note

Content here."""
        
        result = formatter.validate_note(valid_note)
        assert result["valid"] is True
        assert result["has_frontmatter"] is True
        assert result["title"] == "Valid Note"
    
    def test_validate_invalid_note(self):
        """Test validation of invalid note."""
        formatter = NoteFormatter()
        
        # Invalid note (no title in frontmatter)
        invalid_note = """---
title: ""
---

Content without headers."""
        
        result = formatter.validate_note(invalid_note)
        assert result["valid"] is False
        assert len(result["issues"]) > 0
    
    def test_custom_template(self):
        """Test adding and using custom template."""
        formatter = NoteFormatter()
        
        custom_template = NoteTemplate(
            name="custom",
            format=NoteFormat.STANDARD,
            sections=["Custom Section 1", "Custom Section 2"]
        )
        
        formatter.add_template(custom_template)
        
        result = formatter.format_note("Content", template_name="custom")
        
        assert "## Custom Section 1" in result
        assert "## Custom Section 2" in result
    
    def test_list_templates(self):
        """Test listing available templates."""
        formatter = NoteFormatter()
        templates = formatter.list_templates()
        
        assert "standard" in templates
        assert "research" in templates
        assert "meeting" in templates
    
    def test_list_formatters(self):
        """Test listing available formatters."""
        formatter = NoteFormatter()
        formatters = formatter.list_formatters()
        
        assert "ai_summary" in formatters
        assert "ai_insights" in formatters
        assert "ai_questions" in formatters