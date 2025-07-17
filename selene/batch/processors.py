"""
Batch processors for handling multiple notes efficiently.
"""

import asyncio
from typing import List, Dict, Any, Optional

from loguru import logger
from rich.console import Console
from rich.progress import Progress, TaskID

from ..processors.base import BaseProcessor
from ..processors.ollama_processor import OllamaProcessor


class BatchProcessor:
    """Wrapper for processing multiple notes efficiently."""
    
    def __init__(self, 
                 processor: Optional[BaseProcessor] = None,
                 max_concurrent: int = 5):
        """Initialize batch processor.
        
        Args:
            processor: Base processor to use for individual notes
            max_concurrent: Maximum number of concurrent processing tasks
        """
        self.processor = processor or OllamaProcessor()
        self.max_concurrent = max_concurrent
        self.console = Console()
        
    async def process_batch(self, 
                          notes: List[Dict[str, Any]],
                          tasks: List[str],
                          progress: Optional[Progress] = None,
                          main_task: Optional[TaskID] = None) -> List[Dict[str, Any]]:
        """Process a batch of notes with the specified tasks.
        
        Args:
            notes: List of note dictionaries
            tasks: List of processing tasks to perform
            progress: Optional progress tracker
            main_task: Optional main task ID for progress updates
            
        Returns:
            List of processing results
        """
        # Create semaphore to limit concurrent processing
        semaphore = asyncio.Semaphore(self.max_concurrent)
        
        # Create processing tasks
        processing_tasks = []
        for note in notes:
            task = self._process_note_with_semaphore(semaphore, note, tasks)
            processing_tasks.append(task)
            
        # Execute all tasks
        results = await asyncio.gather(*processing_tasks, return_exceptions=True)
        
        # Process results and update progress
        batch_results = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                logger.error(f"Failed to process note {notes[i].get('title', 'Unknown')}: {result}")
                batch_results.append({
                    'note': notes[i],
                    'status': 'failed',
                    'error': str(result)
                })
            else:
                batch_results.append(result)
                
            # Update progress if available
            if progress and main_task:
                progress.update(main_task, advance=1)
                
        return batch_results
    
    async def _process_note_with_semaphore(self, 
                                         semaphore: asyncio.Semaphore,
                                         note: Dict[str, Any],
                                         tasks: List[str]) -> Dict[str, Any]:
        """Process a single note with semaphore control."""
        async with semaphore:
            return await self._process_single_note(note, tasks)
    
    async def _process_single_note(self, 
                                 note: Dict[str, Any],
                                 tasks: List[str]) -> Dict[str, Any]:
        """Process a single note with multiple tasks."""
        try:
            original_content = note['content']
            processed_content = original_content
            processing_results = {}
            
            # Apply each processing task sequentially
            for task in tasks:
                try:
                    result = await self.processor.process_content(
                        content=processed_content,
                        task=task,
                        metadata={
                            'title': note.get('title'),
                            'source': note.get('source'),
                            'tags': note.get('tags', [])
                        }
                    )
                    
                    if result.success:
                        processing_results[task] = result.content
                        
                        # Use enhanced content for subsequent tasks
                        if task == 'enhance':
                            processed_content = result.content
                            
                        logger.debug(f"Task {task} completed for note {note.get('title', 'Unknown')}")
                    else:
                        logger.warning(f"Task {task} failed for note {note.get('title', 'Unknown')}: {result.error}")
                        processing_results[task] = f"Task failed: {result.error}"
                        
                except Exception as e:
                    logger.error(f"Error in task {task} for note {note.get('title', 'Unknown')}: {e}")
                    processing_results[task] = f"Error: {e}"
                    
            return {
                'note': note,
                'status': 'success',
                'processed_content': processed_content,
                'processing_results': processing_results,
                'original_content': original_content
            }
            
        except Exception as e:
            logger.error(f"Error processing note {note.get('title', 'Unknown')}: {e}")
            return {
                'note': note,
                'status': 'failed',
                'error': str(e)
            }


class ParallelBatchProcessor(BatchProcessor):
    """Batch processor that can run multiple tasks in parallel per note."""
    
    async def _process_single_note(self, 
                                 note: Dict[str, Any],
                                 tasks: List[str]) -> Dict[str, Any]:
        """Process a single note with parallel task execution."""
        try:
            original_content = note['content']
            
            # Separate enhancement from other tasks
            enhancement_tasks = [task for task in tasks if task == 'enhance']
            other_tasks = [task for task in tasks if task != 'enhance']
            
            processing_results = {}
            processed_content = original_content
            
            # Run enhancement first if requested
            if enhancement_tasks:
                result = await self.processor.process_content(
                    content=original_content,
                    task='enhance',
                    metadata={
                        'title': note.get('title'),
                        'source': note.get('source'),
                        'tags': note.get('tags', [])
                    }
                )
                
                if result.success:
                    processing_results['enhance'] = result.content
                    processed_content = result.content
                else:
                    logger.warning(f"Enhancement failed for note {note.get('title', 'Unknown')}")
                    processing_results['enhance'] = f"Enhancement failed: {result.error}"
            
            # Run other tasks in parallel on the (possibly enhanced) content
            if other_tasks:
                parallel_tasks = []
                for task in other_tasks:
                    parallel_tasks.append(self._process_task(processed_content, task, note))
                
                parallel_results = await asyncio.gather(*parallel_tasks, return_exceptions=True)
                
                # Collect results
                for i, result in enumerate(parallel_results):
                    task_name = other_tasks[i]
                    if isinstance(result, Exception):
                        logger.error(f"Parallel task {task_name} failed: {result}")
                        processing_results[task_name] = f"Error: {result}"
                    else:
                        processing_results[task_name] = result
            
            return {
                'note': note,
                'status': 'success',
                'processed_content': processed_content,
                'processing_results': processing_results,
                'original_content': original_content
            }
            
        except Exception as e:
            logger.error(f"Error processing note {note.get('title', 'Unknown')}: {e}")
            return {
                'note': note,
                'status': 'failed',
                'error': str(e)
            }
    
    async def _process_task(self, 
                          content: str, 
                          task: str, 
                          note: Dict[str, Any]) -> str:
        """Process a single task on content."""
        try:
            result = await self.processor.process_content(
                content=content,
                task=task,
                metadata={
                    'title': note.get('title'),
                    'source': note.get('source'),
                    'tags': note.get('tags', [])
                }
            )
            
            if result.success:
                return result.content
            else:
                return f"Task failed: {result.error}"
                
        except Exception as e:
            logger.error(f"Error in task {task}: {e}")
            return f"Error: {e}"