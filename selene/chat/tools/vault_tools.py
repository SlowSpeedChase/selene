"""
Vault interaction tools for SELENE chatbot agent.
These tools handle reading, writing, and updating notes in Obsidian vaults.
"""

import os
import shutil
from datetime import datetime
from pathlib import Path
from typing import List, Optional

from loguru import logger

from .base import BaseTool, ToolParameter, ToolResult, ToolStatus


class ReadNoteTool(BaseTool):
    """Tool for reading notes from the vault."""
    
    def __init__(self, vault_path: Optional[Path] = None):
        super().__init__()
        self.vault_path = vault_path
        
    @property
    def name(self) -> str:
        return "read_note"
        
    @property
    def description(self) -> str:
        return "Read the contents of a note from the vault"
        
    @property
    def parameters(self) -> List[ToolParameter]:
        return [
            ToolParameter(
                name="note_path",
                type="string",
                description="Path or name of the note to read (can be relative path or just filename)",
                required=True
            )
        ]
        
    async def execute(self, **kwargs) -> ToolResult:
        note_path = kwargs.get("note_path")
        
        if not self.vault_path:
            return ToolResult(
                status=ToolStatus.ERROR,
                error_message="No vault configured"
            )
            
        try:
            # Try to find the note
            full_path = self._find_note_path(note_path)
            if not full_path:
                return ToolResult(
                    status=ToolStatus.ERROR,
                    error_message=f"Note not found: {note_path}"
                )
                
            # Read the file
            with open(full_path, 'r', encoding='utf-8') as f:
                content = f.read()
                
            return ToolResult(
                status=ToolStatus.SUCCESS,
                content=content,
                metadata={
                    "file_path": str(full_path),
                    "file_size": len(content),
                    "last_modified": datetime.fromtimestamp(full_path.stat().st_mtime).isoformat()
                }
            )
            
        except Exception as e:
            logger.error(f"Error reading note {note_path}: {e}")
            return ToolResult(
                status=ToolStatus.ERROR,
                error_message=f"Failed to read note: {e}"
            )
            
    def _find_note_path(self, note_path: str) -> Optional[Path]:
        """Find the full path to a note given a path or filename."""
        if not self.vault_path:
            return None
            
        # If it's already a full path, check if it exists
        full_path = Path(note_path)
        if full_path.is_absolute() and full_path.exists():
            return full_path
            
        # Try as relative to vault
        vault_relative = self.vault_path / note_path
        if vault_relative.exists():
            return vault_relative
            
        # Try adding .md extension
        if not note_path.endswith('.md'):
            md_path = self.vault_path / f"{note_path}.md"
            if md_path.exists():
                return md_path
                
        # Search in subdirectories
        for md_file in self.vault_path.glob(f"**/{note_path}"):
            if md_file.is_file():
                return md_file
                
        # Search for files with .md extension
        if not note_path.endswith('.md'):
            for md_file in self.vault_path.glob(f"**/{note_path}.md"):
                if md_file.is_file():
                    return md_file
                    
        return None


class WriteNoteTool(BaseTool):
    """Tool for creating new notes in the vault."""
    
    def __init__(self, vault_path: Optional[Path] = None):
        super().__init__()
        self.vault_path = vault_path
        
    @property
    def name(self) -> str:
        return "write_note"
        
    @property
    def description(self) -> str:
        return "Create a new note with the specified content"
        
    @property
    def parameters(self) -> List[ToolParameter]:
        return [
            ToolParameter(
                name="note_path",
                type="string", 
                description="Path where the note should be created (relative to vault root)",
                required=True
            ),
            ToolParameter(
                name="content",
                type="string",
                description="Content of the note",
                required=True
            ),
            ToolParameter(
                name="overwrite",
                type="bool",
                description="Whether to overwrite existing file",
                required=False,
                default=False
            )
        ]
        
    async def execute(self, **kwargs) -> ToolResult:
        note_path = kwargs.get("note_path")
        content = kwargs.get("content")
        overwrite = kwargs.get("overwrite", False)
        
        if not self.vault_path:
            return ToolResult(
                status=ToolStatus.ERROR,
                error_message="No vault configured"
            )
            
        try:
            # Ensure .md extension
            if not note_path.endswith('.md'):
                note_path = f"{note_path}.md"
                
            full_path = self.vault_path / note_path
            
            # Check if file already exists
            if full_path.exists() and not overwrite:
                return ToolResult(
                    status=ToolStatus.REQUIRES_CONFIRMATION,
                    content=f"File already exists: {full_path}. Use overwrite=True to replace it."
                )
                
            # Create directory if needed
            full_path.parent.mkdir(parents=True, exist_ok=True)
            
            # Write the file
            with open(full_path, 'w', encoding='utf-8') as f:
                f.write(content)
                
            return ToolResult(
                status=ToolStatus.SUCCESS,
                content=f"Note created successfully: {full_path}",
                metadata={
                    "file_path": str(full_path),
                    "file_size": len(content),
                    "created_at": datetime.now().isoformat()
                }
            )
            
        except Exception as e:
            logger.error(f"Error writing note {note_path}: {e}")
            return ToolResult(
                status=ToolStatus.ERROR,
                error_message=f"Failed to write note: {e}"
            )


class UpdateNoteTool(BaseTool):
    """Tool for updating existing notes."""
    
    def __init__(self, vault_path: Optional[Path] = None):
        super().__init__()
        self.vault_path = vault_path
        
    @property
    def name(self) -> str:
        return "update_note"
        
    @property
    def description(self) -> str:
        return "Update an existing note by appending, prepending, or replacing content"
        
    @property
    def parameters(self) -> List[ToolParameter]:
        return [
            ToolParameter(
                name="note_path",
                type="string",
                description="Path or name of the note to update",
                required=True
            ),
            ToolParameter(
                name="content",
                type="string",
                description="Content to add",
                required=True
            ),
            ToolParameter(
                name="mode",
                type="string",
                description="Update mode: append, prepend, or replace",
                required=False,
                default="append",
                enum=["append", "prepend", "replace"]
            ),
            ToolParameter(
                name="backup",
                type="bool",
                description="Create backup before updating",
                required=False,
                default=True
            )
        ]
        
    async def execute(self, **kwargs) -> ToolResult:
        note_path = kwargs.get("note_path")
        content = kwargs.get("content")
        mode = kwargs.get("mode", "append")
        backup = kwargs.get("backup", True)
        
        if not self.vault_path:
            return ToolResult(
                status=ToolStatus.ERROR,
                error_message="No vault configured"
            )
            
        try:
            # Find the note
            read_tool = ReadNoteTool(self.vault_path)
            full_path = read_tool._find_note_path(note_path)
            
            if not full_path:
                return ToolResult(
                    status=ToolStatus.ERROR,
                    error_message=f"Note not found: {note_path}"
                )
                
            # Create backup if requested
            if backup:
                backup_path = full_path.with_suffix(f".{datetime.now().strftime('%Y%m%d_%H%M%S')}.bak")
                shutil.copy2(full_path, backup_path)
                
            # Read current content
            with open(full_path, 'r', encoding='utf-8') as f:
                current_content = f.read()
                
            # Update based on mode
            if mode == "append":
                new_content = current_content + "\n\n" + content
            elif mode == "prepend":
                new_content = content + "\n\n" + current_content
            elif mode == "replace":
                new_content = content
            else:
                return ToolResult(
                    status=ToolStatus.ERROR,
                    error_message=f"Invalid mode: {mode}"
                )
                
            # Write updated content
            with open(full_path, 'w', encoding='utf-8') as f:
                f.write(new_content)
                
            return ToolResult(
                status=ToolStatus.SUCCESS,
                content=f"Note updated successfully ({mode} mode): {full_path}",
                metadata={
                    "file_path": str(full_path),
                    "mode": mode,
                    "backup_created": backup,
                    "new_size": len(new_content),
                    "updated_at": datetime.now().isoformat()
                }
            )
            
        except Exception as e:
            logger.error(f"Error updating note {note_path}: {e}")
            return ToolResult(
                status=ToolStatus.ERROR,
                error_message=f"Failed to update note: {e}"
            )


class ListNotesTool(BaseTool):
    """Tool for listing notes in the vault."""
    
    def __init__(self, vault_path: Optional[Path] = None):
        super().__init__()
        self.vault_path = vault_path
        
    @property
    def name(self) -> str:
        return "list_notes"
        
    @property
    def description(self) -> str:
        return "List all notes in the vault with optional filtering"
        
    @property
    def parameters(self) -> List[ToolParameter]:
        return [
            ToolParameter(
                name="pattern",
                type="string",
                description="Optional filename pattern to filter results",
                required=False
            ),
            ToolParameter(
                name="sort_by",
                type="string",
                description="Sort criteria: name, modified, size",
                required=False,
                default="name",
                enum=["name", "modified", "size"]
            ),
            ToolParameter(
                name="limit",
                type="int",
                description="Maximum number of results",
                required=False,
                default=50
            )
        ]
        
    async def execute(self, **kwargs) -> ToolResult:
        pattern = kwargs.get("pattern", "*.md")
        sort_by = kwargs.get("sort_by", "name")
        limit = kwargs.get("limit", 50)
        
        if not self.vault_path:
            return ToolResult(
                status=ToolStatus.ERROR,
                error_message="No vault configured"
            )
            
        try:
            # Find all markdown files
            if pattern and not pattern.endswith('.md'):
                pattern = f"**/*{pattern}*.md"
            elif not pattern:
                pattern = "**/*.md"
                
            files = list(self.vault_path.glob(pattern))
            
            # Create file info list
            file_info = []
            for file_path in files:
                if file_path.is_file():
                    stat = file_path.stat()
                    relative_path = file_path.relative_to(self.vault_path)
                    
                    file_info.append({
                        "name": file_path.name,
                        "path": str(relative_path),
                        "size": stat.st_size,
                        "modified": datetime.fromtimestamp(stat.st_mtime),
                        "modified_str": datetime.fromtimestamp(stat.st_mtime).strftime('%Y-%m-%d %H:%M:%S')
                    })
                    
            # Sort files
            if sort_by == "name":
                file_info.sort(key=lambda x: x["name"].lower())
            elif sort_by == "modified":
                file_info.sort(key=lambda x: x["modified"], reverse=True)
            elif sort_by == "size":
                file_info.sort(key=lambda x: x["size"], reverse=True)
                
            # Limit results
            file_info = file_info[:limit]
            
            # Format output
            if not file_info:
                content = "No notes found"
            else:
                content = []
                for info in file_info:
                    size_kb = info["size"] / 1024
                    content.append(f"📄 {info['path']} ({size_kb:.1f}KB, {info['modified_str']})")
                    
            return ToolResult(
                status=ToolStatus.SUCCESS,
                content=content,
                metadata={
                    "total_found": len(file_info),
                    "pattern": pattern,
                    "sort_by": sort_by,
                    "vault_path": str(self.vault_path)
                }
            )
            
        except Exception as e:
            logger.error(f"Error listing notes: {e}")
            return ToolResult(
                status=ToolStatus.ERROR,
                error_message=f"Failed to list notes: {e}"
            )