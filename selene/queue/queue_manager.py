"""
Queue manager for orchestrating file processing operations.
"""

import asyncio
import time
from typing import Dict, Any, Optional, List
from pathlib import Path

from loguru import logger

from .processing_queue import ProcessingQueue, QueueItem, QueueItemStatus, QueueItemType
from ..processors import OllamaProcessor, LLMProcessor, VectorProcessor
from ..processors.base import BaseProcessor


class QueueManager:
    """Manages processing queue and worker execution."""
    
    def __init__(self, 
                 processing_queue: Optional[ProcessingQueue] = None,
                 max_workers: int = 3):
        """
        Initialize queue manager.
        
        Args:
            processing_queue: Processing queue instance
            max_workers: Maximum number of concurrent workers
        """
        self.processing_queue = processing_queue or ProcessingQueue()
        self.max_workers = max_workers
        
        # Worker management
        self._workers: List[asyncio.Task] = []
        self._running = False
        self._stop_event = asyncio.Event()
        
        # Processor instances (cached for performance)
        self._processors: Dict[str, BaseProcessor] = {}
        
        # Statistics
        self._worker_stats = {
            "total_processed": 0,
            "total_errors": 0,
            "start_time": None,
            "last_activity": None
        }
    
    def _get_processor(self, processor_type: str) -> Optional[BaseProcessor]:
        """Get or create processor instance."""
        if processor_type in self._processors:
            return self._processors[processor_type]
        
        try:
            if processor_type == "ollama":
                processor = OllamaProcessor()
            elif processor_type == "openai":
                processor = LLMProcessor()
            elif processor_type == "vector":
                processor = VectorProcessor()
            else:
                logger.error(f"Unknown processor type: {processor_type}")
                return None
            
            self._processors[processor_type] = processor
            logger.info(f"Created processor instance: {processor_type}")
            return processor
            
        except Exception as e:
            logger.error(f"Failed to create processor {processor_type}: {e}")
            return None
    
    async def _process_file_item(self, item: QueueItem) -> bool:
        """
        Process a file processing queue item.
        
        Args:
            item: Queue item to process
            
        Returns:
            True if successful, False otherwise
        """
        try:
            # Get processor
            processor = self._get_processor(item.processor_type)
            if not processor:
                await self.processing_queue.fail_item(
                    item.id, 
                    f"Failed to get processor: {item.processor_type}"
                )
                return False
            
            # Process file or content
            if item.file_path:
                # Process file
                file_path = Path(item.file_path)
                if not file_path.exists():
                    await self.processing_queue.fail_item(
                        item.id,
                        f"File not found: {item.file_path}"
                    )
                    return False
                
                result = await processor.process_file(
                    file_path,
                    task=item.task,
                    **item.metadata
                )
            elif item.content:
                # Process content directly
                result = await processor.process(
                    item.content,
                    task=item.task,
                    **item.metadata
                )
            else:
                await self.processing_queue.fail_item(
                    item.id,
                    "No file path or content provided"
                )
                return False
            
            # Handle result
            if result.success:
                # Prepare result metadata
                result_metadata = {
                    "processor_type": item.processor_type,
                    "task": item.task,
                    "original_metadata": item.metadata,
                    "processing_metadata": result.metadata,
                    "processing_time": result.processing_time
                }
                
                # Store in vector database if requested
                if item.metadata.get("store_in_vector_db", False):
                    await self._store_in_vector_db(item, result.content, result_metadata)
                
                # Mark as completed
                await self.processing_queue.complete_item(
                    item.id,
                    result.content,
                    result_metadata
                )
                
                logger.info(f"Successfully processed {item.task} for: {item.file_path or 'content'}")
                return True
            else:
                await self.processing_queue.fail_item(
                    item.id,
                    result.error or "Processing failed with unknown error"
                )
                return False
        
        except Exception as e:
            await self.processing_queue.fail_item(
                item.id,
                f"Processing exception: {str(e)}"
            )
            logger.error(f"Error processing item {item.id}: {e}")
            return False
    
    async def _store_in_vector_db(self, 
                                  item: QueueItem, 
                                  processed_content: str,
                                  result_metadata: Dict[str, Any]):
        """Store processed content in vector database."""
        try:
            vector_processor = self._get_processor("vector")
            if not vector_processor:
                logger.warning("Vector processor not available, skipping vector storage")
                return
            
            # Prepare metadata for vector storage
            doc_metadata = {
                "source_file": item.file_path,
                "original_task": item.task,
                "processor_type": item.processor_type,
                "processed_at": time.time(),
                "auto_generated": item.metadata.get("auto_generated", False),
                "watched_directory": item.metadata.get("watched_directory"),
                **item.metadata.get("directory_metadata", {})
            }
            
            # Generate document ID
            if item.file_path:
                file_name = Path(item.file_path).stem
                doc_id = f"{file_name}_{item.task}_{int(time.time())}"
            else:
                doc_id = f"content_{item.task}_{int(time.time())}"
            
            # Store in vector database
            vector_result = await vector_processor.process(
                processed_content,
                task="store",
                metadata=doc_metadata,
                doc_id=doc_id,
                file_path=item.file_path
            )
            
            if vector_result.success:
                logger.info(f"Stored processed content in vector DB: {doc_id}")
                result_metadata["vector_storage"] = {
                    "success": True,
                    "document_id": doc_id,
                    "storage_metadata": vector_result.metadata
                }
            else:
                logger.warning(f"Failed to store in vector DB: {vector_result.error}")
                result_metadata["vector_storage"] = {
                    "success": False,
                    "error": vector_result.error
                }
        
        except Exception as e:
            logger.error(f"Error storing in vector database: {e}")
            result_metadata["vector_storage"] = {
                "success": False,
                "error": str(e)
            }
    
    async def _process_vector_item(self, item: QueueItem) -> bool:
        """Process a vector database operation item."""
        try:
            vector_processor = self._get_processor("vector")
            if not vector_processor:
                await self.processing_queue.fail_item(
                    item.id,
                    "Vector processor not available"
                )
                return False
            
            # Execute vector operation
            if item.content:
                result = await vector_processor.process(
                    item.content,
                    task=item.task,
                    **item.metadata
                )
            else:
                result = await vector_processor.process(
                    "",
                    task=item.task,
                    **item.metadata
                )
            
            if result.success:
                await self.processing_queue.complete_item(
                    item.id,
                    result.content,
                    result.metadata
                )
                return True
            else:
                await self.processing_queue.fail_item(
                    item.id,
                    result.error or "Vector operation failed"
                )
                return False
        
        except Exception as e:
            await self.processing_queue.fail_item(
                item.id,
                f"Vector processing exception: {str(e)}"
            )
            return False
    
    async def _worker_loop(self, worker_id: int):
        """Worker loop for processing queue items."""
        logger.info(f"Worker {worker_id} started")
        
        while not self._stop_event.is_set():
            try:
                # Get next item from queue
                item = await self.processing_queue.get_next_item()
                
                if item is None:
                    # No items to process, wait briefly
                    await asyncio.sleep(0.5)
                    continue
                
                self._worker_stats["last_activity"] = time.time()
                
                # Process based on item type
                success = False
                if item.item_type == QueueItemType.FILE_PROCESS:
                    success = await self._process_file_item(item)
                elif item.item_type == QueueItemType.VECTOR_STORE:
                    success = await self._process_vector_item(item)
                elif item.item_type == QueueItemType.BATCH_PROCESS:
                    # Handle batch processing (could be implemented later)
                    logger.warning(f"Batch processing not yet implemented for item {item.id}")
                    await self.processing_queue.fail_item(
                        item.id,
                        "Batch processing not implemented"
                    )
                else:
                    logger.warning(f"Unknown item type: {item.item_type}")
                    await self.processing_queue.fail_item(
                        item.id,
                        f"Unknown item type: {item.item_type}"
                    )
                
                # Update statistics
                if success:
                    self._worker_stats["total_processed"] += 1
                else:
                    self._worker_stats["total_errors"] += 1
            
            except asyncio.CancelledError:
                logger.info(f"Worker {worker_id} cancelled")
                break
            except Exception as e:
                logger.error(f"Worker {worker_id} error: {e}")
                self._worker_stats["total_errors"] += 1
                await asyncio.sleep(1)  # Brief pause on error
        
        logger.info(f"Worker {worker_id} stopped")
    
    async def start_processing(self) -> bool:
        """Start the queue processing workers."""
        if self._running:
            logger.warning("Queue manager is already running")
            return True
        
        try:
            self._stop_event.clear()
            self._running = True
            self._worker_stats["start_time"] = time.time()
            
            # Start worker tasks
            for i in range(self.max_workers):
                worker_task = asyncio.create_task(self._worker_loop(i))
                self._workers.append(worker_task)
            
            logger.info(f"Started {self.max_workers} queue processing workers")
            return True
        
        except Exception as e:
            logger.error(f"Failed to start queue processing: {e}")
            return False
    
    async def stop_processing(self):
        """Stop the queue processing workers."""
        if not self._running:
            return
        
        logger.info("Stopping queue processing...")
        
        # Signal workers to stop
        self._stop_event.set()
        
        # Cancel worker tasks
        for worker in self._workers:
            worker.cancel()
        
        # Wait for workers to finish
        if self._workers:
            await asyncio.gather(*self._workers, return_exceptions=True)
        
        self._workers.clear()
        self._running = False
        
        logger.info("Queue processing stopped")
    
    def is_running(self) -> bool:
        """Check if queue processing is running."""
        return self._running
    
    def get_status(self) -> Dict[str, Any]:
        """Get queue manager status."""
        queue_status = self.processing_queue.get_queue_status()
        
        uptime = 0
        if self._worker_stats["start_time"]:
            uptime = time.time() - self._worker_stats["start_time"]
        
        return {
            "is_running": self._running,
            "workers": {
                "count": len(self._workers),
                "max_workers": self.max_workers,
                "active_workers": len([w for w in self._workers if not w.done()])
            },
            "queue": queue_status,
            "statistics": {
                **self._worker_stats,
                "uptime_seconds": uptime
            },
            "processors": {
                "loaded_processors": list(self._processors.keys()),
                "processor_count": len(self._processors)
            }
        }
    
    async def process_item_now(self, item: QueueItem) -> bool:
        """
        Process a single item immediately (bypass queue).
        
        Args:
            item: Queue item to process
            
        Returns:
            True if successful
        """
        try:
            if item.item_type == QueueItemType.FILE_PROCESS:
                return await self._process_file_item(item)
            elif item.item_type == QueueItemType.VECTOR_STORE:
                return await self._process_vector_item(item)
            else:
                logger.error(f"Cannot process item type immediately: {item.item_type}")
                return False
        except Exception as e:
            logger.error(f"Error processing item immediately: {e}")
            return False
    
    async def clear_old_items(self, max_age_hours: float = 24.0):
        """Clear old completed and failed items from queue."""
        await self.processing_queue.clear_completed(max_age_hours)
        await self.processing_queue.clear_failed(max_age_hours)
    
    def get_comprehensive_status(self) -> Dict[str, Any]:
        """Get comprehensive status including queue details."""
        return {
            "manager_status": self.get_status(),
            "queue_summary": self.processing_queue.get_summary(),
            "recent_items": {
                "pending": [item.to_dict() for item in self.processing_queue.get_items_by_status(QueueItemStatus.PENDING)[:5]],
                "processing": [item.to_dict() for item in self.processing_queue.get_items_by_status(QueueItemStatus.PROCESSING)],
                "completed": [item.to_dict() for item in self.processing_queue.get_items_by_status(QueueItemStatus.COMPLETED)[-5:]],
                "failed": [item.to_dict() for item in self.processing_queue.get_items_by_status(QueueItemStatus.FAILED)[-3:]]
            }
        }