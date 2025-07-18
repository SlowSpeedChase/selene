"""
Chat configuration management for SELENE chatbot agent.
"""

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional

import yaml
from loguru import logger


@dataclass
class ChatConfig:
    """Configuration for SELENE chatbot agent."""
    
    # Vault settings
    vault_path: Optional[str] = None
    auto_discover_vaults: bool = True
    watched_extensions: List[str] = field(default_factory=lambda: [".md", ".txt"])
    
    # AI processing settings
    default_processor: str = "ollama"
    default_model: str = "llama3.1:8b"
    ai_confirmation_required: bool = True
    
    # Conversation settings
    conversation_memory: bool = True
    memory_db_path: str = "~/.selene/chat_memory.db"
    max_conversation_history: int = 50
    context_window_size: int = 10
    
    # Interface settings
    rich_formatting: bool = True
    show_tool_calls: bool = False
    auto_save_conversations: bool = True
    
    # Tool settings
    enabled_tools: List[str] = field(default_factory=lambda: [
        "read_note", "write_note", "update_note", "list_notes",
        "search_notes", "ai_process", "vector_search"
    ])
    
    # Safety settings
    backup_on_write: bool = True
    confirm_destructive_actions: bool = True
    max_file_size_mb: int = 10
    
    @classmethod
    def from_file(cls, config_path: str = "~/.selene/chat_config.yaml") -> "ChatConfig":
        """Load configuration from YAML file."""
        config_file = Path(config_path).expanduser()
        
        if not config_file.exists():
            logger.info(f"Chat config file not found at {config_path}, using defaults")
            return cls()
            
        try:
            with open(config_file, "r") as f:
                data = yaml.safe_load(f) or {}
                
            # Extract chat-specific config
            chat_config = data.get("chat", {})
            
            return cls(
                vault_path=chat_config.get("vault_path"),
                auto_discover_vaults=chat_config.get("auto_discover_vaults", True),
                watched_extensions=chat_config.get("watched_extensions", [".md", ".txt"]),
                default_processor=chat_config.get("default_processor", "ollama"),
                default_model=chat_config.get("default_model", "llama3.1:8b"),
                ai_confirmation_required=chat_config.get("ai_confirmation_required", True),
                conversation_memory=chat_config.get("conversation_memory", True),
                memory_db_path=chat_config.get("memory_db_path", "~/.selene/chat_memory.db"),
                max_conversation_history=chat_config.get("max_conversation_history", 50),
                context_window_size=chat_config.get("context_window_size", 10),
                rich_formatting=chat_config.get("rich_formatting", True),
                show_tool_calls=chat_config.get("show_tool_calls", False),
                auto_save_conversations=chat_config.get("auto_save_conversations", True),
                enabled_tools=chat_config.get("enabled_tools", [
                    "read_note", "write_note", "update_note", "list_notes",
                    "search_notes", "ai_process", "vector_search"
                ]),
                backup_on_write=chat_config.get("backup_on_write", True),
                confirm_destructive_actions=chat_config.get("confirm_destructive_actions", True),
                max_file_size_mb=chat_config.get("max_file_size_mb", 10)
            )
            
        except Exception as e:
            logger.warning(f"Error loading chat config from {config_path}: {e}")
            logger.info("Using default configuration")
            return cls()
    
    def save_to_file(self, config_path: str = "~/.selene/chat_config.yaml") -> bool:
        """Save configuration to YAML file."""
        config_file = Path(config_path).expanduser()
        config_file.parent.mkdir(parents=True, exist_ok=True)
        
        try:
            # Load existing config if it exists
            existing_config = {}
            if config_file.exists():
                with open(config_file, "r") as f:
                    existing_config = yaml.safe_load(f) or {}
            
            # Update chat section
            existing_config["chat"] = {
                "vault_path": self.vault_path,
                "auto_discover_vaults": self.auto_discover_vaults,
                "watched_extensions": self.watched_extensions,
                "default_processor": self.default_processor,
                "default_model": self.default_model,
                "ai_confirmation_required": self.ai_confirmation_required,
                "conversation_memory": self.conversation_memory,
                "memory_db_path": self.memory_db_path,
                "max_conversation_history": self.max_conversation_history,
                "context_window_size": self.context_window_size,
                "rich_formatting": self.rich_formatting,
                "show_tool_calls": self.show_tool_calls,
                "auto_save_conversations": self.auto_save_conversations,
                "enabled_tools": self.enabled_tools,
                "backup_on_write": self.backup_on_write,
                "confirm_destructive_actions": self.confirm_destructive_actions,
                "max_file_size_mb": self.max_file_size_mb
            }
            
            with open(config_file, "w") as f:
                yaml.safe_dump(existing_config, f, default_flow_style=False)
                
            logger.info(f"Saved chat configuration to {config_path}")
            return True
            
        except Exception as e:
            logger.error(f"Error saving chat config to {config_path}: {e}")
            return False
    
    def get_vault_path(self) -> Optional[Path]:
        """Get configured vault path as Path object."""
        if not self.vault_path:
            return None
        return Path(self.vault_path).expanduser().resolve()
    
    def get_memory_db_path(self) -> Path:
        """Get memory database path as Path object."""
        return Path(self.memory_db_path).expanduser().resolve()
    
    def is_valid_vault(self, path: Optional[str] = None) -> bool:
        """Check if vault path is valid."""
        vault_path = Path(path).resolve() if path else self.get_vault_path()
        
        if not vault_path or not vault_path.exists():
            return False
            
        if not vault_path.is_dir():
            return False
            
        # Check if it looks like an Obsidian vault (has .md files or .obsidian folder)
        has_markdown = any(vault_path.glob("**/*.md"))
        has_obsidian_folder = (vault_path / ".obsidian").exists()
        
        return has_markdown or has_obsidian_folder
    
    def discover_vaults(self) -> List[Path]:
        """Discover potential Obsidian vaults on the system."""
        potential_vaults = []
        
        # Common vault locations
        search_paths = [
            Path.home() / "Documents",
            Path.home() / "Obsidian",
            Path.home() / "vaults",
            Path.home() / "Notes",
            Path.home() / "Desktop"
        ]
        
        for search_path in search_paths:
            if not search_path.exists():
                continue
                
            try:
                # Look for directories with .obsidian folder or many .md files
                for item in search_path.iterdir():
                    if not item.is_dir():
                        continue
                        
                    if self.is_valid_vault(str(item)):
                        potential_vaults.append(item)
                        
            except (PermissionError, OSError):
                continue
                
        return potential_vaults
    
    def validate(self) -> List[str]:
        """Validate configuration and return list of issues."""
        issues = []
        
        # Check vault path
        if self.vault_path and not self.is_valid_vault():
            issues.append(f"Vault path is not valid: {self.vault_path}")
            
        # Check memory database path
        try:
            memory_path = self.get_memory_db_path()
            memory_path.parent.mkdir(parents=True, exist_ok=True)
        except Exception:
            issues.append(f"Cannot create memory database directory: {self.memory_db_path}")
            
        # Check file size limits
        if self.max_file_size_mb <= 0:
            issues.append("max_file_size_mb must be positive")
            
        if self.max_conversation_history <= 0:
            issues.append("max_conversation_history must be positive")
            
        if self.context_window_size <= 0:
            issues.append("context_window_size must be positive")
            
        return issues
    
    def __str__(self) -> str:
        """String representation of configuration."""
        return f"ChatConfig(vault={self.vault_path}, processor={self.default_processor})"