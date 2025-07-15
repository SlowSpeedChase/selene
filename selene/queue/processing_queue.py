"""
Asynchronous processing queue for file operations.
"""

import asyncio
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any, Awaitable, Callable, Dict, List, Optional

from loguru import logger


class QueueItemStatus(Enum):
    """Status of items in the processing queue."""

    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class QueueItemType(Enum):
    """Type of processing operation."""

    FILE_PROCESS = "file_process"
    VECTOR_STORE = "vector_store"
    BATCH_PROCESS = "batch_process"
    CUSTOM = "custom"


@dataclass
class QueueItem:
    """Item in the processing queue."""

    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    item_type: QueueItemType = QueueItemType.FILE_PROCESS
    file_path: Optional[str] = None
    content: Optional[str] = None
    task: str = "summarize"
    processor_type: str = "ollama"
    metadata: Dict[str, Any] = field(default_factory=dict)

    # Status tracking
    status: QueueItemStatus = QueueItemStatus.PENDING
    created_at: float = field(default_factory=time.time)
    started_at: Optional[float] = None
    completed_at: Optional[float] = None
    error_message: Optional[str] = None

    # Processing results
    result_content: Optional[str] = None
    result_metadata: Dict[str, Any] = field(default_factory=dict)
    processing_time: Optional[float] = None

    # Priority and retry
    priority: int = 5  # 1 = highest, 10 = lowest
    retry_count: int = 0
    max_retries: int = 2

    def mark_started(self):
        """Mark item as started processing."""
        self.status = QueueItemStatus.PROCESSING
        self.started_at = time.time()

    def mark_completed(
        self, result_content: str = "", result_metadata: Dict[str, Any] = None
    ):
        """Mark item as completed successfully."""
        self.status = QueueItemStatus.COMPLETED
        self.completed_at = time.time()
        self.result_content = result_content
        self.result_metadata = result_metadata or {}

        if self.started_at:
            self.processing_time = self.completed_at - self.started_at

    def mark_failed(self, error_message: str):
        """Mark item as failed."""
        self.status = QueueItemStatus.FAILED
        self.completed_at = time.time()
        self.error_message = error_message

        if self.started_at:
            self.processing_time = self.completed_at - self.started_at

    def mark_cancelled(self):
        """Mark item as cancelled."""
        self.status = QueueItemStatus.CANCELLED
        self.completed_at = time.time()

    def can_retry(self) -> bool:
        """Check if item can be retried."""
        return (
            self.status == QueueItemStatus.FAILED
            and self.retry_count < self.max_retries
        )

    def reset_for_retry(self):
        """Reset item for retry."""
        if self.can_retry():
            self.status = QueueItemStatus.PENDING
            self.started_at = None
            self.completed_at = None
            self.error_message = None
            self.retry_count += 1

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization."""
        return {
            "id": self.id,
            "item_type": self.item_type.value,
            "file_path": self.file_path,
            "content": (
                self.content[:100] + "..."
                if self.content and len(self.content) > 100
                else self.content
            ),
            "task": self.task,
            "processor_type": self.processor_type,
            "metadata": self.metadata,
            "status": self.status.value,
            "created_at": self.created_at,
            "started_at": self.started_at,
            "completed_at": self.completed_at,
            "error_message": self.error_message,
            "processing_time": self.processing_time,
            "priority": self.priority,
            "retry_count": self.retry_count,
            "max_retries": self.max_retries,
        }


class ProcessingQueue:
    """Asynchronous processing queue for file operations."""

    def __init__(self, max_size: int = 100, max_concurrent: int = 3):
        """
        Initialize processing queue.

        Args:
            max_size: Maximum number of items in queue
            max_concurrent: Maximum concurrent processing jobs
        """
        self.max_size = max_size
        self.max_concurrent = max_concurrent

        # Queue storage
        self._queue: List[QueueItem] = []
        self._processing: Dict[str, QueueItem] = {}
        self._completed: Dict[str, QueueItem] = {}
        self._failed: Dict[str, QueueItem] = {}

        # Async management
        self._queue_lock = asyncio.Lock()
        self._running = False
        self._worker_tasks: List[asyncio.Task] = []

        # Statistics
        self._stats = {
            "total_processed": 0,
            "total_failed": 0,
            "total_cancelled": 0,
            "processing_time_total": 0.0,
        }

    async def add_item(self, item: QueueItem) -> bool:
        """
        Add item to the queue.

        Args:
            item: Queue item to add

        Returns:
            True if added successfully, False if queue is full
        """
        async with self._queue_lock:
            if len(self._queue) >= self.max_size:
                logger.warning(f"Queue is full (max {self.max_size}), cannot add item")
                return False

            # Insert in priority order (lower priority number = higher priority)
            inserted = False
            for i, existing_item in enumerate(self._queue):
                if item.priority < existing_item.priority:
                    self._queue.insert(i, item)
                    inserted = True
                    break

            if not inserted:
                self._queue.append(item)

            logger.info(f"Added item to queue: {item.id} (priority {item.priority})")
            return True

    async def get_next_item(self) -> Optional[QueueItem]:
        """Get the next item to process from the queue."""
        async with self._queue_lock:
            if not self._queue:
                return None

            # Get highest priority item (lowest priority number)
            item = self._queue.pop(0)
            item.mark_started()
            self._processing[item.id] = item

            logger.info(f"Started processing item: {item.id}")
            return item

    async def complete_item(
        self,
        item_id: str,
        result_content: str = "",
        result_metadata: Dict[str, Any] = None,
    ):
        """Mark an item as completed."""
        async with self._queue_lock:
            if item_id in self._processing:
                item = self._processing.pop(item_id)
                item.mark_completed(result_content, result_metadata)
                self._completed[item_id] = item

                # Update stats
                self._stats["total_processed"] += 1
                if item.processing_time:
                    self._stats["processing_time_total"] += item.processing_time

                logger.info(f"Completed item: {item_id} in {item.processing_time:.2f}s")

    async def fail_item(self, item_id: str, error_message: str):
        """Mark an item as failed."""
        async with self._queue_lock:
            if item_id in self._processing:
                item = self._processing.pop(item_id)
                item.mark_failed(error_message)

                # Check if we should retry
                if item.can_retry():
                    item.reset_for_retry()
                    # Re-add to queue for retry
                    self._queue.insert(0, item)  # High priority for retries
                    logger.info(
                        f"Retrying item: {item_id} (attempt {item.retry_count}/{item.max_retries})"
                    )
                else:
                    self._failed[item_id] = item
                    self._stats["total_failed"] += 1
                    logger.error(f"Failed item: {item_id} - {error_message}")

    async def cancel_item(self, item_id: str) -> bool:
        """Cancel an item (remove from queue or mark as cancelled if processing)."""
        async with self._queue_lock:
            # Check if in queue
            for i, item in enumerate(self._queue):
                if item.id == item_id:
                    item.mark_cancelled()
                    self._queue.pop(i)
                    self._stats["total_cancelled"] += 1
                    logger.info(f"Cancelled queued item: {item_id}")
                    return True

            # Check if currently processing
            if item_id in self._processing:
                item = self._processing[item_id]
                item.mark_cancelled()
                # Note: actual processing cancellation would need to be handled by the worker
                logger.info(f"Marked processing item as cancelled: {item_id}")
                return True

            return False

    def get_queue_status(self) -> Dict[str, Any]:
        """Get current queue status and statistics."""
        return {
            "queue_size": len(self._queue),
            "processing_count": len(self._processing),
            "completed_count": len(self._completed),
            "failed_count": len(self._failed),
            "max_size": self.max_size,
            "max_concurrent": self.max_concurrent,
            "is_running": self._running,
            "statistics": self._stats.copy(),
        }

    def get_items_by_status(self, status: QueueItemStatus) -> List[QueueItem]:
        """Get all items with a specific status."""
        if status == QueueItemStatus.PENDING:
            return self._queue.copy()
        elif status == QueueItemStatus.PROCESSING:
            return list(self._processing.values())
        elif status == QueueItemStatus.COMPLETED:
            return list(self._completed.values())
        elif status == QueueItemStatus.FAILED:
            return list(self._failed.values())
        else:
            return []

    def get_item(self, item_id: str) -> Optional[QueueItem]:
        """Get a specific item by ID."""
        # Check all storage locations
        for item in self._queue:
            if item.id == item_id:
                return item

        if item_id in self._processing:
            return self._processing[item_id]

        if item_id in self._completed:
            return self._completed[item_id]

        if item_id in self._failed:
            return self._failed[item_id]

        return None

    async def clear_completed(self, max_age_hours: float = 24.0):
        """Clear completed items older than specified age."""
        async with self._queue_lock:
            current_time = time.time()
            max_age_seconds = max_age_hours * 3600

            to_remove = []
            for item_id, item in self._completed.items():
                if (
                    item.completed_at
                    and (current_time - item.completed_at) > max_age_seconds
                ):
                    to_remove.append(item_id)

            for item_id in to_remove:
                del self._completed[item_id]

            if to_remove:
                logger.info(f"Cleared {len(to_remove)} old completed items")

    async def clear_failed(self, max_age_hours: float = 24.0):
        """Clear failed items older than specified age."""
        async with self._queue_lock:
            current_time = time.time()
            max_age_seconds = max_age_hours * 3600

            to_remove = []
            for item_id, item in self._failed.items():
                if (
                    item.completed_at
                    and (current_time - item.completed_at) > max_age_seconds
                ):
                    to_remove.append(item_id)

            for item_id in to_remove:
                del self._failed[item_id]

            if to_remove:
                logger.info(f"Cleared {len(to_remove)} old failed items")

    def get_summary(self) -> Dict[str, Any]:
        """Get a summary of queue state and performance."""
        total_items = (
            self._stats["total_processed"]
            + self._stats["total_failed"]
            + self._stats["total_cancelled"]
        )

        avg_processing_time = 0.0
        if self._stats["total_processed"] > 0:
            avg_processing_time = (
                self._stats["processing_time_total"] / self._stats["total_processed"]
            )

        success_rate = 0.0
        if total_items > 0:
            success_rate = self._stats["total_processed"] / total_items

        return {
            "queue_status": self.get_queue_status(),
            "total_items_processed": total_items,
            "success_rate": success_rate,
            "average_processing_time": avg_processing_time,
            "current_queue_size": len(self._queue),
            "active_jobs": len(self._processing),
        }
