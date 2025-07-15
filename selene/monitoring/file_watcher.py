"""
File system watcher for real-time file monitoring.
"""

import asyncio
import fnmatch
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Awaitable, Callable, Dict, Optional, Set

from loguru import logger
from watchdog.events import FileSystemEvent, FileSystemEventHandler
from watchdog.observers import Observer

from ..queue.processing_queue import ProcessingQueue, QueueItem, QueueItemType
from .monitor_config import MonitorConfig, WatchedDirectory


@dataclass
class FileEvent:
    """File system event data."""

    event_type: str  # created, modified, deleted, moved
    file_path: str
    is_directory: bool
    timestamp: float = field(default_factory=time.time)
    src_path: Optional[str] = None  # For move events


class FileEventHandler(FileSystemEventHandler):
    """Custom file system event handler."""

    def __init__(
        self,
        config: MonitorConfig,
        event_callback: Callable[[FileEvent], Awaitable[None]],
    ):
        """
        Initialize file event handler.

        Args:
            config: Monitor configuration
            event_callback: Async callback for file events
        """
        super().__init__()
        self.config = config
        self.event_callback = event_callback

        # Debounce mechanism
        self._debounce_events: Dict[str, float] = {}
        self._loop = None

    def _should_process_file(
        self, file_path: str, watched_dir: WatchedDirectory
    ) -> bool:
        """Check if file should be processed based on configuration."""
        path_obj = Path(file_path)

        # Check if it's a supported file type
        if not self.config.is_file_supported(file_path):
            return False

        # Check ignore patterns
        if self.config.should_ignore_file(file_path):
            return False

        # Check watched directory patterns
        file_name = path_obj.name
        pattern_match = False

        for pattern in watched_dir.patterns:
            if fnmatch.fnmatch(file_name, pattern):
                pattern_match = True
                break

        return pattern_match

    def _get_watched_directory(self, file_path: str) -> Optional[WatchedDirectory]:
        """Get the watched directory configuration for a file."""
        return self.config.get_directory_config(file_path)

    def _should_debounce(self, file_path: str) -> bool:
        """Check if event should be debounced."""
        current_time = time.time()
        last_event_time = self._debounce_events.get(file_path, 0)

        if current_time - last_event_time < self.config.debounce_seconds:
            # Update the timestamp for this file
            self._debounce_events[file_path] = current_time
            return True

        # Record this event
        self._debounce_events[file_path] = current_time
        return False

    def _schedule_callback(self, event: FileEvent):
        """Schedule async callback in event loop."""
        if self._loop is None:
            try:
                self._loop = asyncio.get_running_loop()
            except RuntimeError:
                logger.warning("No running event loop found, cannot process file event")
                return

        # Schedule the callback
        asyncio.run_coroutine_threadsafe(self.event_callback(event), self._loop)

    def on_created(self, event: FileSystemEvent):
        """Handle file/directory creation."""
        if event.is_directory:
            return

        watched_dir = self._get_watched_directory(event.src_path)
        if not watched_dir:
            return

        if not self._should_process_file(event.src_path, watched_dir):
            return

        if self._should_debounce(event.src_path):
            return

        file_event = FileEvent(
            event_type="created",
            file_path=event.src_path,
            is_directory=event.is_directory,
        )

        logger.info(f"File created: {event.src_path}")
        self._schedule_callback(file_event)

    def on_modified(self, event: FileSystemEvent):
        """Handle file/directory modification."""
        if event.is_directory:
            return

        watched_dir = self._get_watched_directory(event.src_path)
        if not watched_dir:
            return

        if not self._should_process_file(event.src_path, watched_dir):
            return

        if self._should_debounce(event.src_path):
            return

        file_event = FileEvent(
            event_type="modified",
            file_path=event.src_path,
            is_directory=event.is_directory,
        )

        logger.info(f"File modified: {event.src_path}")
        self._schedule_callback(file_event)

    def on_deleted(self, event: FileSystemEvent):
        """Handle file/directory deletion."""
        if event.is_directory:
            return

        # Clean up debounce tracking
        if event.src_path in self._debounce_events:
            del self._debounce_events[event.src_path]

        file_event = FileEvent(
            event_type="deleted",
            file_path=event.src_path,
            is_directory=event.is_directory,
        )

        logger.info(f"File deleted: {event.src_path}")
        self._schedule_callback(file_event)

    def on_moved(self, event: FileSystemEvent):
        """Handle file/directory move."""
        if event.is_directory:
            return

        # Clean up old path from debounce tracking
        if hasattr(event, "src_path") and event.src_path in self._debounce_events:
            del self._debounce_events[event.src_path]

        watched_dir = self._get_watched_directory(event.dest_path)
        if not watched_dir:
            return

        if not self._should_process_file(event.dest_path, watched_dir):
            return

        file_event = FileEvent(
            event_type="moved",
            file_path=event.dest_path,
            is_directory=event.is_directory,
            src_path=getattr(event, "src_path", None),
        )

        logger.info(
            f"File moved: {getattr(event, 'src_path', 'unknown')} -> {event.dest_path}"
        )
        self._schedule_callback(file_event)


class FileWatcher:
    """File system watcher for monitoring directories."""

    def __init__(
        self, config: MonitorConfig, processing_queue: Optional[ProcessingQueue] = None
    ):
        """
        Initialize file watcher.

        Args:
            config: Monitor configuration
            processing_queue: Processing queue for file operations
        """
        self.config = config
        self.processing_queue = processing_queue or ProcessingQueue()

        # Watchdog components
        self.observer = Observer()
        self.event_handler = FileEventHandler(config, self._handle_file_event)

        # State tracking
        self._watching = False
        self._watched_paths: Set[str] = set()

        # Statistics
        self._stats = {
            "events_processed": 0,
            "files_queued": 0,
            "errors": 0,
            "start_time": None,
        }

    async def _handle_file_event(self, event: FileEvent):
        """Handle file system events and queue for processing."""
        try:
            self._stats["events_processed"] += 1

            # Skip deleted files (nothing to process)
            if event.event_type == "deleted":
                logger.debug(f"Skipping deleted file: {event.file_path}")
                return

            # Get watched directory configuration
            watched_dir = self.config.get_directory_config(event.file_path)
            if not watched_dir:
                logger.debug(f"File not in watched directory: {event.file_path}")
                return

            # Skip if auto-processing is disabled
            if not watched_dir.auto_process:
                logger.debug(f"Auto-processing disabled for: {event.file_path}")
                return

            # Create processing tasks for each configured task
            for task in watched_dir.processing_tasks:
                queue_item = QueueItem(
                    item_type=QueueItemType.FILE_PROCESS,
                    file_path=event.file_path,
                    task=task,
                    processor_type=self.config.default_processor,
                    metadata={
                        "event_type": event.event_type,
                        "watched_directory": watched_dir.path,
                        "directory_metadata": watched_dir.metadata,
                        "store_in_vector_db": watched_dir.store_in_vector_db,
                        "auto_generated": True,
                        "timestamp": event.timestamp,
                    },
                    priority=3,  # Medium priority for auto-generated tasks
                )

                # Add to processing queue
                success = await self.processing_queue.add_item(queue_item)
                if success:
                    self._stats["files_queued"] += 1
                    logger.info(f"Queued {task} task for: {event.file_path}")
                else:
                    logger.warning(
                        f"Failed to queue {task} task for: {event.file_path}"
                    )

        except Exception as e:
            self._stats["errors"] += 1
            logger.error(f"Error handling file event: {e}")

    async def start_watching(self) -> bool:
        """Start watching configured directories."""
        try:
            if self._watching:
                logger.warning("File watcher is already running")
                return True

            # Validate configuration
            config_issues = self.config.validate()
            if config_issues:
                logger.error(f"Configuration issues: {', '.join(config_issues)}")
                return False

            # Set up watches for each directory
            for watched_dir in self.config.watched_directories:
                path = Path(watched_dir.path)

                if not path.exists():
                    logger.error(f"Watched directory does not exist: {path}")
                    continue

                # Add watch
                self.observer.schedule(
                    self.event_handler, str(path), recursive=watched_dir.recursive
                )

                self._watched_paths.add(str(path))
                logger.info(
                    f"Watching directory: {path} (recursive: {watched_dir.recursive})"
                )

            if not self._watched_paths:
                logger.error("No valid directories to watch")
                return False

            # Start the observer
            self.observer.start()
            self._watching = True
            self._stats["start_time"] = time.time()

            logger.info(
                f"File watcher started, monitoring {len(self._watched_paths)} directories"
            )
            return True

        except Exception as e:
            logger.error(f"Failed to start file watcher: {e}")
            return False

    async def stop_watching(self):
        """Stop watching directories."""
        if not self._watching:
            return

        try:
            self.observer.stop()
            self.observer.join(timeout=5.0)  # Wait up to 5 seconds

            self._watching = False
            self._watched_paths.clear()

            logger.info("File watcher stopped")

        except Exception as e:
            logger.error(f"Error stopping file watcher: {e}")

    def is_watching(self) -> bool:
        """Check if the watcher is currently active."""
        return self._watching

    def get_watched_paths(self) -> Set[str]:
        """Get the set of currently watched paths."""
        return self._watched_paths.copy()

    def get_statistics(self) -> Dict[str, any]:
        """Get file watcher statistics."""
        stats = self._stats.copy()

        if stats["start_time"]:
            stats["uptime_seconds"] = time.time() - stats["start_time"]
        else:
            stats["uptime_seconds"] = 0

        stats["is_watching"] = self._watching
        stats["watched_directories"] = len(self._watched_paths)
        stats["queue_status"] = self.processing_queue.get_queue_status()

        return stats

    async def add_watched_directory(
        self,
        path: str,
        patterns: Optional[list] = None,
        recursive: bool = True,
        **kwargs,
    ) -> bool:
        """
        Add a new directory to watch.

        Args:
            path: Directory path to watch
            patterns: File patterns to match
            recursive: Watch subdirectories
            **kwargs: Additional configuration options

        Returns:
            True if added successfully
        """
        # Add to configuration
        success = self.config.add_watched_directory(
            path=path, patterns=patterns, recursive=recursive, **kwargs
        )

        if not success:
            return False

        # If currently watching, add the new watch
        if self._watching:
            try:
                path_obj = Path(path)
                self.observer.schedule(
                    self.event_handler, str(path_obj), recursive=recursive
                )

                self._watched_paths.add(str(path_obj))
                logger.info(f"Added new watched directory: {path}")

            except Exception as e:
                logger.error(f"Failed to add watch for {path}: {e}")
                # Remove from config since watch failed
                self.config.remove_watched_directory(path)
                return False

        return True

    async def remove_watched_directory(self, path: str) -> bool:
        """
        Remove a directory from watching.

        Args:
            path: Directory path to stop watching

        Returns:
            True if removed successfully
        """
        # Remove from configuration
        success = self.config.remove_watched_directory(path)

        if success and self._watching:
            # Need to restart observer to remove watch
            # (watchdog doesn't support removing individual watches)
            logger.info(f"Restarting watcher to remove directory: {path}")
            await self.stop_watching()
            await self.start_watching()

        return success

    async def process_existing_files(self, directory_path: Optional[str] = None):
        """
        Process existing files in watched directories.

        Args:
            directory_path: Specific directory to process, or None for all
        """
        directories_to_process = []

        if directory_path:
            # Process specific directory
            watched_dir = self.config.get_directory_config(directory_path)
            if watched_dir:
                directories_to_process.append(watched_dir)
            else:
                logger.error(f"Directory not in watched list: {directory_path}")
                return
        else:
            # Process all watched directories
            directories_to_process = self.config.watched_directories

        total_files = 0
        processed_files = 0

        for watched_dir in directories_to_process:
            try:
                path_obj = Path(watched_dir.path)

                if not path_obj.exists():
                    logger.warning(f"Directory does not exist: {path_obj}")
                    continue

                # Find matching files
                for pattern in watched_dir.patterns:
                    if watched_dir.recursive:
                        files = path_obj.rglob(pattern)
                    else:
                        files = path_obj.glob(pattern)

                    for file_path in files:
                        if file_path.is_file():
                            total_files += 1

                            # Check if should be processed
                            if self.config.is_file_supported(
                                str(file_path)
                            ) and not self.config.should_ignore_file(str(file_path)):

                                # Create file event for processing
                                event = FileEvent(
                                    event_type="existing",
                                    file_path=str(file_path),
                                    is_directory=False,
                                )

                                await self._handle_file_event(event)
                                processed_files += 1

                logger.info(
                    f"Processed {processed_files}/{total_files} existing files in {watched_dir.path}"
                )

            except Exception as e:
                logger.error(
                    f"Error processing existing files in {watched_dir.path}: {e}"
                )

        logger.info(
            f"Batch processing complete: {processed_files} files queued from {total_files} total files"
        )

    def get_status_summary(self) -> Dict[str, any]:
        """Get a comprehensive status summary."""
        return {
            "watcher_status": {
                "is_watching": self._watching,
                "watched_directories": len(self._watched_paths),
                "watched_paths": list(self._watched_paths),
            },
            "configuration": self.config.get_summary(),
            "statistics": self.get_statistics(),
            "queue_summary": self.processing_queue.get_summary(),
        }
