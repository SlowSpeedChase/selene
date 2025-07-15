"""
Configuration management for file monitoring system.
"""

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml
from loguru import logger


@dataclass
class WatchedDirectory:
    """Configuration for a watched directory."""

    path: str
    patterns: List[str] = field(
        default_factory=lambda: ["*.txt", "*.md", "*.pdf", "*.docx"]
    )
    recursive: bool = True
    auto_process: bool = True
    processing_tasks: List[str] = field(
        default_factory=lambda: ["summarize", "extract_insights"]
    )
    store_in_vector_db: bool = True
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class MonitorConfig:
    """File monitoring system configuration."""

    watched_directories: List[WatchedDirectory] = field(default_factory=list)
    processing_enabled: bool = True
    batch_size: int = 5
    max_concurrent_jobs: int = 3
    debounce_seconds: float = 2.0
    ignore_patterns: List[str] = field(
        default_factory=lambda: [
            "*.tmp",
            "*.temp",
            ".*",
            "__pycache__",
            "*.pyc",
            ".DS_Store",
        ]
    )
    supported_extensions: List[str] = field(
        default_factory=lambda: [".txt", ".md", ".pdf", ".docx", ".doc", ".rtf", ".odt"]
    )
    default_processor: str = "ollama"
    vector_db_path: str = "./chroma_db"
    queue_max_size: int = 100

    @classmethod
    def from_file(cls, config_path: str = ".monitor-config.yaml") -> "MonitorConfig":
        """Load configuration from YAML file."""
        config_file = Path(config_path)

        if not config_file.exists():
            logger.info(f"Monitor config file not found: {config_path}, using defaults")
            return cls()

        try:
            with open(config_file, "r") as f:
                data = yaml.safe_load(f)

            # Parse watched directories
            watched_dirs = []
            for dir_data in data.get("watched_directories", []):
                watched_dir = WatchedDirectory(
                    path=dir_data["path"],
                    patterns=dir_data.get(
                        "patterns", ["*.txt", "*.md", "*.pdf", "*.docx"]
                    ),
                    recursive=dir_data.get("recursive", True),
                    auto_process=dir_data.get("auto_process", True),
                    processing_tasks=dir_data.get(
                        "processing_tasks", ["summarize", "extract_insights"]
                    ),
                    store_in_vector_db=dir_data.get("store_in_vector_db", True),
                    metadata=dir_data.get("metadata", {}),
                )
                watched_dirs.append(watched_dir)

            # Create config with parsed data
            config = cls(
                watched_directories=watched_dirs,
                processing_enabled=data.get("processing_enabled", True),
                batch_size=data.get("batch_size", 5),
                max_concurrent_jobs=data.get("max_concurrent_jobs", 3),
                debounce_seconds=data.get("debounce_seconds", 2.0),
                ignore_patterns=data.get(
                    "ignore_patterns",
                    ["*.tmp", "*.temp", ".*", "__pycache__", "*.pyc", ".DS_Store"],
                ),
                supported_extensions=data.get(
                    "supported_extensions",
                    [".txt", ".md", ".pdf", ".docx", ".doc", ".rtf", ".odt"],
                ),
                default_processor=data.get("default_processor", "ollama"),
                vector_db_path=data.get("vector_db_path", "./chroma_db"),
                queue_max_size=data.get("queue_max_size", 100),
            )

            logger.info(f"Loaded monitor configuration from {config_path}")
            return config

        except Exception as e:
            logger.error(f"Failed to load monitor config: {e}")
            logger.info("Using default configuration")
            return cls()

    def save_to_file(self, config_path: str = ".monitor-config.yaml") -> bool:
        """Save configuration to YAML file."""
        try:
            config_data = {
                "watched_directories": [
                    {
                        "path": wd.path,
                        "patterns": wd.patterns,
                        "recursive": wd.recursive,
                        "auto_process": wd.auto_process,
                        "processing_tasks": wd.processing_tasks,
                        "store_in_vector_db": wd.store_in_vector_db,
                        "metadata": wd.metadata,
                    }
                    for wd in self.watched_directories
                ],
                "processing_enabled": self.processing_enabled,
                "batch_size": self.batch_size,
                "max_concurrent_jobs": self.max_concurrent_jobs,
                "debounce_seconds": self.debounce_seconds,
                "ignore_patterns": self.ignore_patterns,
                "supported_extensions": self.supported_extensions,
                "default_processor": self.default_processor,
                "vector_db_path": self.vector_db_path,
                "queue_max_size": self.queue_max_size,
            }

            with open(config_path, "w") as f:
                yaml.dump(config_data, f, default_flow_style=False, indent=2)

            logger.info(f"Saved monitor configuration to {config_path}")
            return True

        except Exception as e:
            logger.error(f"Failed to save monitor config: {e}")
            return False

    def add_watched_directory(
        self, path: str, patterns: Optional[List[str]] = None, **kwargs
    ) -> bool:
        """Add a new watched directory to the configuration."""
        try:
            # Check if directory exists
            if not Path(path).exists():
                logger.error(f"Directory does not exist: {path}")
                return False

            # Check if already being watched
            for wd in self.watched_directories:
                if Path(wd.path).resolve() == Path(path).resolve():
                    logger.warning(f"Directory already being watched: {path}")
                    return False

            # Create new watched directory
            watched_dir = WatchedDirectory(
                path=str(Path(path).resolve()),
                patterns=patterns or ["*.txt", "*.md", "*.pdf", "*.docx"],
                **kwargs,
            )

            self.watched_directories.append(watched_dir)
            logger.info(f"Added watched directory: {path}")
            return True

        except Exception as e:
            logger.error(f"Failed to add watched directory: {e}")
            return False

    def remove_watched_directory(self, path: str) -> bool:
        """Remove a watched directory from the configuration."""
        try:
            path_resolved = Path(path).resolve()

            for i, wd in enumerate(self.watched_directories):
                if Path(wd.path).resolve() == path_resolved:
                    self.watched_directories.pop(i)
                    logger.info(f"Removed watched directory: {path}")
                    return True

            logger.warning(f"Directory not found in watched list: {path}")
            return False

        except Exception as e:
            logger.error(f"Failed to remove watched directory: {e}")
            return False

    def is_file_supported(self, file_path: str) -> bool:
        """Check if a file type is supported for processing."""
        file_ext = Path(file_path).suffix.lower()
        return file_ext in self.supported_extensions

    def should_ignore_file(self, file_path: str) -> bool:
        """Check if a file should be ignored based on ignore patterns."""
        import fnmatch

        file_name = Path(file_path).name

        for pattern in self.ignore_patterns:
            if fnmatch.fnmatch(file_name, pattern):
                return True

        return False

    def get_directory_config(self, file_path: str) -> Optional[WatchedDirectory]:
        """Get the watched directory configuration for a given file path."""
        file_path_obj = Path(file_path).resolve()

        for wd in self.watched_directories:
            wd_path = Path(wd.path).resolve()

            try:
                # Check if file is in watched directory
                file_path_obj.relative_to(wd_path)
                return wd
            except ValueError:
                # File is not in this watched directory
                continue

        return None

    def validate(self) -> List[str]:
        """Validate configuration and return list of issues."""
        issues = []

        # Check watched directories exist
        for wd in self.watched_directories:
            if not Path(wd.path).exists():
                issues.append(f"Watched directory does not exist: {wd.path}")

        # Check processing settings
        if self.batch_size <= 0:
            issues.append("Batch size must be positive")

        if self.max_concurrent_jobs <= 0:
            issues.append("Max concurrent jobs must be positive")

        if self.debounce_seconds < 0:
            issues.append("Debounce seconds must be non-negative")

        # Check processor
        if self.default_processor not in ["ollama", "openai", "vector"]:
            issues.append(f"Invalid default processor: {self.default_processor}")

        return issues

    def get_summary(self) -> Dict[str, Any]:
        """Get a summary of the current configuration."""
        return {
            "watched_directories_count": len(self.watched_directories),
            "watched_paths": [wd.path for wd in self.watched_directories],
            "processing_enabled": self.processing_enabled,
            "default_processor": self.default_processor,
            "supported_extensions": self.supported_extensions,
            "batch_size": self.batch_size,
            "max_concurrent_jobs": self.max_concurrent_jobs,
        }
