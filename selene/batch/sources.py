"""
Sources for batch importing notes from various external systems.
"""

import json
import re
import sqlite3
import subprocess
from abc import ABC, abstractmethod
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Any, Optional, Union

from loguru import logger


class BaseSource(ABC):
    """Base class for note sources."""
    
    @abstractmethod
    async def get_notes(self) -> List[Dict[str, Any]]:
        """Get notes from the source.
        
        Returns:
            List of note dictionaries with keys: title, content, tags, created_at, source
        """
        pass
    
    @abstractmethod
    async def archive_notes(self, notes: List[Dict[str, Any]]) -> bool:
        """Archive notes after successful processing.
        
        Args:
            notes: List of note dictionaries to archive
            
        Returns:
            True if archiving was successful
        """
        pass


class DraftsSource(BaseSource):
    """Source for importing notes from Drafts app on macOS/iOS."""
    
    def __init__(self, 
                 tag_filter: str = "selene",
                 archive_tag: str = "selene-processed",
                 drafts_db_path: Optional[Union[str, Path]] = None):
        """Initialize Drafts source.
        
        Args:
            tag_filter: Only import drafts with this tag
            archive_tag: Tag to add to processed drafts
            drafts_db_path: Path to Drafts database (auto-detected if None)
        """
        self.tag_filter = tag_filter
        self.archive_tag = archive_tag
        self.drafts_db_path = self._find_drafts_db(drafts_db_path)
        
    def _find_drafts_db(self, custom_path: Optional[Union[str, Path]] = None) -> Optional[Path]:
        """Find the Drafts database file."""
        if custom_path:
            return Path(custom_path)
            
        # Common locations for Drafts database
        possible_paths = [
            Path.home() / "Library" / "Application Support" / "Drafts" / "Drafts.sqlite",
            Path.home() / "Library" / "Containers" / "com.agiletortoise.Drafts-OSX" / "Data" / "Library" / "Application Support" / "Drafts" / "Drafts.sqlite",
            Path.home() / "Library" / "Group Containers" / "group.com.agiletortoise.Drafts-OSX" / "Drafts.sqlite"
        ]
        
        for path in possible_paths:
            if path.exists():
                return path
                
        logger.warning("Drafts database not found. You may need to specify the path manually.")
        return None
    
    def _extract_tags_from_content(self, content: str) -> List[str]:
        """Extract hashtags from draft content."""
        # Find hashtags in the content
        hashtags = re.findall(r'#(\w+)', content)
        return hashtags
    
    async def get_notes(self) -> List[Dict[str, Any]]:
        """Get notes from Drafts app database."""
        if not self.drafts_db_path or not self.drafts_db_path.exists():
            logger.error("Drafts database not found")
            return []
        
        try:
            notes = []
            
            # Connect to Drafts database
            with sqlite3.connect(str(self.drafts_db_path)) as conn:
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                
                # Query for drafts with the specified tag
                query = """
                SELECT 
                    d.uuid,
                    d.content,
                    d.created_at,
                    d.modified_at,
                    d.flagged,
                    d.archived,
                    d.trashed
                FROM drafts d
                WHERE d.content LIKE ? 
                    AND d.trashed = 0
                    AND d.archived = 0
                ORDER BY d.created_at DESC
                """
                
                cursor.execute(query, (f'%#{self.tag_filter}%',))
                rows = cursor.fetchall()
                
                for row in rows:
                    content = row['content']
                    
                    # Extract title from first line or use preview
                    lines = content.split('\n')
                    title = lines[0].strip() if lines else "Untitled"
                    
                    # Remove title from content if it's a header
                    if title.startswith('#'):
                        title = title.lstrip('#').strip()
                        content = '\n'.join(lines[1:]).strip()
                    
                    # Extract tags from content
                    tags = self._extract_tags_from_content(content)
                    
                    # Only include if it has the filter tag
                    if self.tag_filter in tags:
                        notes.append({
                            'uuid': row['uuid'],
                            'title': title,
                            'content': content,
                            'tags': tags,
                            'created_at': row['created_at'],
                            'modified_at': row['modified_at'],
                            'source': 'drafts'
                        })
                        
            logger.info(f"Found {len(notes)} drafts with tag '{self.tag_filter}'")
            return notes
            
        except Exception as e:
            logger.error(f"Error reading from Drafts database: {e}")
            return []
    
    async def archive_notes(self, notes: List[Dict[str, Any]]) -> bool:
        """Archive notes by adding processed tag and removing selene tag."""
        if not self.drafts_db_path or not self.drafts_db_path.exists():
            logger.error("Drafts database not found")
            return False
        
        try:
            # Use Drafts URL scheme to update drafts
            for note in notes:
                uuid = note.get('uuid')
                if not uuid:
                    continue
                    
                # Remove selene tag and add processed tag
                original_content = note['content']
                
                # Replace selene tag with processed tag
                updated_content = original_content.replace(
                    f'#{self.tag_filter}', 
                    f'#{self.archive_tag}'
                )
                
                # Use Drafts URL scheme to update the draft
                url = f"drafts://x-callback-url/update?uuid={uuid}&content={updated_content}"
                
                try:
                    subprocess.run(['open', url], check=True, capture_output=True)
                except subprocess.CalledProcessError as e:
                    logger.warning(f"Failed to update draft {uuid}: {e}")
                    
            logger.info(f"Archived {len(notes)} drafts")
            return True
            
        except Exception as e:
            logger.error(f"Error archiving drafts: {e}")
            return False


class TextFileSource(BaseSource):
    """Source for importing notes from text files."""
    
    def __init__(self, 
                 directory: Union[str, Path],
                 file_pattern: str = "*.txt",
                 tag_filter: Optional[str] = None,
                 archive_dir: Optional[Union[str, Path]] = None):
        """Initialize text file source.
        
        Args:
            directory: Directory containing text files
            file_pattern: Glob pattern for files to process
            tag_filter: Only process files containing this tag
            archive_dir: Directory to move processed files to
        """
        self.directory = Path(directory)
        self.file_pattern = file_pattern
        self.tag_filter = tag_filter
        self.archive_dir = Path(archive_dir) if archive_dir else self.directory / "processed"
        self.archive_dir.mkdir(parents=True, exist_ok=True)
        
    async def get_notes(self) -> List[Dict[str, Any]]:
        """Get notes from text files."""
        if not self.directory.exists():
            logger.error(f"Directory {self.directory} does not exist")
            return []
        
        notes = []
        
        for file_path in self.directory.glob(self.file_pattern):
            if file_path.is_file():
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                    
                    # Extract tags from content
                    tags = re.findall(r'#(\w+)', content)
                    
                    # Filter by tag if specified
                    if self.tag_filter and self.tag_filter not in tags:
                        continue
                    
                    # Extract title from filename or first line
                    title = file_path.stem
                    lines = content.split('\n')
                    if lines and lines[0].strip():
                        first_line = lines[0].strip()
                        if first_line.startswith('#'):
                            title = first_line.lstrip('#').strip()
                            content = '\n'.join(lines[1:]).strip()
                        elif len(first_line) < 100:  # Reasonable title length
                            title = first_line
                    
                    # Get file timestamps
                    stat = file_path.stat()
                    created_at = datetime.fromtimestamp(stat.st_ctime).isoformat()
                    
                    notes.append({
                        'file_path': str(file_path),
                        'title': title,
                        'content': content,
                        'tags': tags,
                        'created_at': created_at,
                        'source': 'text_file'
                    })
                    
                except Exception as e:
                    logger.error(f"Error reading file {file_path}: {e}")
                    
        logger.info(f"Found {len(notes)} text files")
        return notes
    
    async def archive_notes(self, notes: List[Dict[str, Any]]) -> bool:
        """Archive notes by moving files to archive directory."""
        try:
            for note in notes:
                file_path = Path(note.get('file_path'))
                if file_path.exists():
                    archive_path = self.archive_dir / file_path.name
                    
                    # Ensure unique filename
                    counter = 1
                    while archive_path.exists():
                        stem = file_path.stem
                        suffix = file_path.suffix
                        archive_path = self.archive_dir / f"{stem}_{counter}{suffix}"
                        counter += 1
                    
                    file_path.rename(archive_path)
                    logger.debug(f"Archived {file_path} to {archive_path}")
                    
            logger.info(f"Archived {len(notes)} files to {self.archive_dir}")
            return True
            
        except Exception as e:
            logger.error(f"Error archiving files: {e}")
            return False


class ObsidianSource(BaseSource):
    """Source for importing notes from Obsidian vault."""
    
    def __init__(self, 
                 vault_path: Union[str, Path],
                 tag_filter: Optional[str] = None,
                 folder_filter: Optional[str] = None,
                 archive_folder: str = "processed"):
        """Initialize Obsidian source.
        
        Args:
            vault_path: Path to Obsidian vault
            tag_filter: Only process notes with this tag
            folder_filter: Only process notes in this folder
            archive_folder: Folder to move processed notes to
        """
        self.vault_path = Path(vault_path)
        self.tag_filter = tag_filter
        self.folder_filter = folder_filter
        self.archive_folder = archive_folder
        
    def _extract_frontmatter(self, content: str) -> tuple[Dict[str, Any], str]:
        """Extract frontmatter from markdown content."""
        if not content.startswith('---'):
            return {}, content
        
        try:
            parts = content.split('---', 2)
            if len(parts) < 3:
                return {}, content
            
            frontmatter_text = parts[1].strip()
            content_text = parts[2].strip()
            
            # Parse YAML frontmatter
            import yaml
            frontmatter = yaml.safe_load(frontmatter_text) or {}
            
            return frontmatter, content_text
            
        except Exception as e:
            logger.warning(f"Error parsing frontmatter: {e}")
            return {}, content
    
    async def get_notes(self) -> List[Dict[str, Any]]:
        """Get notes from Obsidian vault."""
        if not self.vault_path.exists():
            logger.error(f"Vault {self.vault_path} does not exist")
            return []
        
        notes = []
        
        # Search for markdown files
        search_path = self.vault_path
        if self.folder_filter:
            search_path = self.vault_path / self.folder_filter
            
        for file_path in search_path.rglob("*.md"):
            if file_path.is_file():
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                    
                    # Extract frontmatter
                    frontmatter, content_text = self._extract_frontmatter(content)
                    
                    # Extract tags from frontmatter and content
                    tags = frontmatter.get('tags', [])
                    if isinstance(tags, str):
                        tags = [tags]
                    
                    # Also extract hashtags from content
                    hashtags = re.findall(r'#(\w+)', content_text)
                    tags.extend(hashtags)
                    tags = list(set(tags))  # Remove duplicates
                    
                    # Filter by tag if specified
                    if self.tag_filter and self.tag_filter not in tags:
                        continue
                    
                    # Get title from frontmatter or filename
                    title = frontmatter.get('title', file_path.stem)
                    
                    # Get file timestamps
                    stat = file_path.stat()
                    created_at = datetime.fromtimestamp(stat.st_ctime).isoformat()
                    
                    notes.append({
                        'file_path': str(file_path),
                        'title': title,
                        'content': content_text,
                        'frontmatter': frontmatter,
                        'tags': tags,
                        'created_at': created_at,
                        'source': 'obsidian'
                    })
                    
                except Exception as e:
                    logger.error(f"Error reading file {file_path}: {e}")
                    
        logger.info(f"Found {len(notes)} Obsidian notes")
        return notes
    
    async def archive_notes(self, notes: List[Dict[str, Any]]) -> bool:
        """Archive notes by moving to archive folder."""
        try:
            archive_path = self.vault_path / self.archive_folder
            archive_path.mkdir(parents=True, exist_ok=True)
            
            for note in notes:
                file_path = Path(note.get('file_path'))
                if file_path.exists():
                    # Preserve folder structure in archive
                    relative_path = file_path.relative_to(self.vault_path)
                    archive_file_path = archive_path / relative_path
                    
                    # Create parent directories
                    archive_file_path.parent.mkdir(parents=True, exist_ok=True)
                    
                    # Move file
                    file_path.rename(archive_file_path)
                    logger.debug(f"Archived {file_path} to {archive_file_path}")
                    
            logger.info(f"Archived {len(notes)} files to {archive_path}")
            return True
            
        except Exception as e:
            logger.error(f"Error archiving files: {e}")
            return False