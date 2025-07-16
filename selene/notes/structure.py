"""
Note structure and building utilities.

Provides tools for creating well-structured markdown notes with sections,
headers, and consistent formatting.
"""

import re
from typing import List, Dict, Any, Optional, Union
from dataclasses import dataclass, field
from enum import Enum


class SectionType(Enum):
    """Types of note sections."""
    HEADER = "header"
    CONTENT = "content"
    LIST = "list"
    TABLE = "table"
    QUOTE = "quote"
    CODE = "code"
    DIVIDER = "divider"


@dataclass
class NoteSection:
    """Represents a section of a note."""
    type: SectionType
    content: str
    level: int = 1  # For headers, this is the header level (1-6)
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    def to_markdown(self) -> str:
        """Convert section to markdown format."""
        if self.type == SectionType.HEADER:
            return f"{'#' * self.level} {self.content}"
        elif self.type == SectionType.CONTENT:
            return self.content
        elif self.type == SectionType.LIST:
            return self.content
        elif self.type == SectionType.TABLE:
            return self.content
        elif self.type == SectionType.QUOTE:
            lines = self.content.split('\n')
            return '\n'.join(f"> {line}" for line in lines)
        elif self.type == SectionType.CODE:
            language = self.metadata.get('language', '')
            return f"```{language}\n{self.content}\n```"
        elif self.type == SectionType.DIVIDER:
            return "---"
        else:
            return self.content


class NoteBuilder:
    """Builder for creating structured notes."""
    
    def __init__(self):
        """Initialize the note builder."""
        self.sections: List[NoteSection] = []
        self.current_level = 1
    
    def add_header(self, text: str, level: int = None) -> "NoteBuilder":
        """Add a header section."""
        if level is None:
            level = self.current_level
        
        section = NoteSection(
            type=SectionType.HEADER,
            content=text,
            level=level
        )
        self.sections.append(section)
        self.current_level = level
        return self
    
    def add_content(self, text: str) -> "NoteBuilder":
        """Add a content section."""
        section = NoteSection(
            type=SectionType.CONTENT,
            content=text
        )
        self.sections.append(section)
        return self
    
    def add_list(self, items: List[str], ordered: bool = False) -> "NoteBuilder":
        """Add a list section."""
        if ordered:
            list_content = '\n'.join(f"{i+1}. {item}" for i, item in enumerate(items))
        else:
            list_content = '\n'.join(f"- {item}" for item in items)
        
        section = NoteSection(
            type=SectionType.LIST,
            content=list_content,
            metadata={"ordered": ordered}
        )
        self.sections.append(section)
        return self
    
    def add_table(self, headers: List[str], rows: List[List[str]]) -> "NoteBuilder":
        """Add a table section."""
        # Create table markdown
        header_row = "| " + " | ".join(headers) + " |"
        separator = "| " + " | ".join(["---"] * len(headers)) + " |"
        
        table_rows = []
        for row in rows:
            table_rows.append("| " + " | ".join(row) + " |")
        
        table_content = "\n".join([header_row, separator] + table_rows)
        
        section = NoteSection(
            type=SectionType.TABLE,
            content=table_content,
            metadata={"headers": headers, "rows": rows}
        )
        self.sections.append(section)
        return self
    
    def add_quote(self, text: str) -> "NoteBuilder":
        """Add a quote section."""
        section = NoteSection(
            type=SectionType.QUOTE,
            content=text
        )
        self.sections.append(section)
        return self
    
    def add_code(self, code: str, language: str = "") -> "NoteBuilder":
        """Add a code section."""
        section = NoteSection(
            type=SectionType.CODE,
            content=code,
            metadata={"language": language}
        )
        self.sections.append(section)
        return self
    
    def add_divider(self) -> "NoteBuilder":
        """Add a divider section."""
        section = NoteSection(
            type=SectionType.DIVIDER,
            content=""
        )
        self.sections.append(section)
        return self
    
    def add_section(self, section: NoteSection) -> "NoteBuilder":
        """Add a custom section."""
        self.sections.append(section)
        return self
    
    def build(self) -> str:
        """Build the final markdown content."""
        return "\n\n".join(section.to_markdown() for section in self.sections)
    
    def clear(self) -> "NoteBuilder":
        """Clear all sections."""
        self.sections.clear()
        self.current_level = 1
        return self
    
    def get_structure(self) -> List[NoteSection]:
        """Get the current structure."""
        return self.sections.copy()


class NoteStructure:
    """Analyzes and represents the structure of existing notes."""
    
    def __init__(self, content: str):
        """Initialize with markdown content."""
        self.content = content
        self.sections = self._parse_structure()
    
    def _parse_structure(self) -> List[NoteSection]:
        """Parse the markdown content into sections."""
        sections = []
        lines = self.content.split('\n')
        current_content = []
        i = 0
        
        while i < len(lines):
            line = lines[i]
            
            # Check for headers
            header_match = re.match(r'^(#{1,6})\s+(.+)$', line)
            if header_match:
                # Add any accumulated content
                if current_content:
                    content_text = '\n'.join(current_content).strip()
                    if content_text:
                        sections.append(NoteSection(
                            type=SectionType.CONTENT,
                            content=content_text
                        ))
                    current_content = []
                
                # Add header
                level = len(header_match.group(1))
                text = header_match.group(2)
                sections.append(NoteSection(
                    type=SectionType.HEADER,
                    content=text,
                    level=level
                ))
                i += 1
            
            # Check for dividers
            elif re.match(r'^---+$', line.strip()):
                # Add any accumulated content
                if current_content:
                    content_text = '\n'.join(current_content).strip()
                    if content_text:
                        sections.append(NoteSection(
                            type=SectionType.CONTENT,
                            content=content_text
                        ))
                    current_content = []
                
                sections.append(NoteSection(
                    type=SectionType.DIVIDER,
                    content=""
                ))
                i += 1
            
            # Check for quotes
            elif line.strip().startswith('>'):
                # Add any accumulated content
                if current_content:
                    content_text = '\n'.join(current_content).strip()
                    if content_text:
                        sections.append(NoteSection(
                            type=SectionType.CONTENT,
                            content=content_text
                        ))
                    current_content = []
                
                # Collect quote lines
                quote_lines = []
                while i < len(lines) and lines[i].strip().startswith('>'):
                    quote_line = lines[i].strip()
                    if quote_line.startswith('> '):
                        quote_lines.append(quote_line[2:])
                    elif quote_line == '>':
                        quote_lines.append('')
                    else:
                        quote_lines.append(quote_line[1:])
                    i += 1
                
                sections.append(NoteSection(
                    type=SectionType.QUOTE,
                    content='\n'.join(quote_lines)
                ))
                continue
            
            # Check for code blocks
            elif line.strip().startswith('```'):
                # Add any accumulated content
                if current_content:
                    content_text = '\n'.join(current_content).strip()
                    if content_text:
                        sections.append(NoteSection(
                            type=SectionType.CONTENT,
                            content=content_text
                        ))
                    current_content = []
                
                # Find end of code block
                language = line.strip()[3:].strip()
                code_lines = []
                
                # Continue reading until we find the closing ```
                i += 1
                while i < len(lines):
                    if lines[i].strip() == '```':
                        break
                    code_lines.append(lines[i])
                    i += 1
                
                # Only add code section if we found both opening and closing
                if i < len(lines):  # Found closing ```
                    sections.append(NoteSection(
                        type=SectionType.CODE,
                        content='\n'.join(code_lines),
                        metadata={"language": language}
                    ))
                    i += 1  # Skip the closing ```
                else:
                    # No closing ```, treat as regular content
                    current_content.append(line)
                    i += 1
            
            else:
                current_content.append(line)
                i += 1
        
        # Add any remaining content
        if current_content:
            content_text = '\n'.join(current_content).strip()
            if content_text:
                sections.append(NoteSection(
                    type=SectionType.CONTENT,
                    content=content_text
                ))
        
        return sections
    
    def get_headers(self) -> List[tuple[int, str]]:
        """Get all headers as (level, text) tuples."""
        return [(s.level, s.content) for s in self.sections if s.type == SectionType.HEADER]
    
    def get_table_of_contents(self) -> str:
        """Generate a table of contents from headers."""
        toc_lines = []
        for level, text in self.get_headers():
            indent = "  " * (level - 1)
            # Create proper anchor link
            link = text.lower().replace(' ', '-')
            link = re.sub(r'[^a-z0-9-]', '', link)
            link = re.sub(r'-+', '-', link)  # Replace multiple dashes with single dash
            link = link.strip('-')  # Remove leading/trailing dashes
            toc_lines.append(f"{indent}- [{text}](#{link})")
        
        return '\n'.join(toc_lines)
    
    def get_section_by_header(self, header_text: str) -> Optional[NoteSection]:
        """Get a section by its header text."""
        for section in self.sections:
            if section.type == SectionType.HEADER and section.content == header_text:
                return section
        return None
    
    def get_content_after_header(self, header_text: str) -> Optional[str]:
        """Get content that appears after a specific header."""
        header_found = False
        content_sections = []
        
        for section in self.sections:
            if section.type == SectionType.HEADER:
                if section.content == header_text:
                    header_found = True
                    continue
                elif header_found:
                    # Found another header, stop collecting
                    break
            elif header_found and section.type == SectionType.CONTENT:
                content_sections.append(section.content)
        
        return '\n\n'.join(content_sections) if content_sections else None
    
    def rebuild(self) -> str:
        """Rebuild the markdown from the parsed structure."""
        return '\n\n'.join(section.to_markdown() for section in self.sections)
    
    def summary(self) -> Dict[str, Any]:
        """Get a summary of the note structure."""
        return {
            "total_sections": len(self.sections),
            "headers": len([s for s in self.sections if s.type == SectionType.HEADER]),
            "content_sections": len([s for s in self.sections if s.type == SectionType.CONTENT]),
            "code_blocks": len([s for s in self.sections if s.type == SectionType.CODE]),
            "tables": len([s for s in self.sections if s.type == SectionType.TABLE]),
            "quotes": len([s for s in self.sections if s.type == SectionType.QUOTE]),
            "dividers": len([s for s in self.sections if s.type == SectionType.DIVIDER])
        }