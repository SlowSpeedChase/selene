"""
Batch importer for processing multiple notes from various sources.
"""

import asyncio
import json
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional, Any, Union

from loguru import logger
from rich.console import Console
from rich.progress import Progress, TaskID, SpinnerColumn, TextColumn, BarColumn, TimeRemainingColumn

from ..processors.base import BaseProcessor
from ..processors.ollama_processor import OllamaProcessor
from ..vector.chroma_store import ChromaStore
from .sources import BaseSource, DraftsSource, TextFileSource


class BatchImporter:
    """Batch importer for processing multiple notes from various sources."""
    
    def __init__(self, 
                 processor: Optional[BaseProcessor] = None,
                 vector_store: Optional[ChromaStore] = None,
                 output_dir: Optional[Union[str, Path]] = None):
        """Initialize the batch importer.
        
        Args:
            processor: Note processor to use (defaults to OllamaProcessor)
            vector_store: Vector store for semantic search (defaults to ChromaStore)
            output_dir: Directory to store processed notes
        """
        self.processor = processor or OllamaProcessor()
        self.vector_store = vector_store or ChromaStore()
        self.output_dir = Path(output_dir) if output_dir else Path.cwd() / "processed_notes"
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        self.console = Console()
        self.stats = {
            'total_notes': 0,
            'processed_notes': 0,
            'failed_notes': 0,
            'skipped_notes': 0,
            'start_time': None,
            'end_time': None
        }
        
    async def import_from_source(self, 
                               source: BaseSource,
                               tasks: List[str] = None,
                               batch_size: int = 5,
                               archive_after_import: bool = True) -> Dict[str, Any]:
        """Import and process notes from a source.
        
        Args:
            source: Source to import notes from
            tasks: List of processing tasks to perform
            batch_size: Number of notes to process concurrently
            archive_after_import: Whether to archive source notes after processing
            
        Returns:
            Dictionary with import statistics and results
        """
        if tasks is None:
            tasks = ['enhance', 'extract_insights']
            
        self.stats['start_time'] = datetime.now()
        
        try:
            # Get notes from source
            notes = await source.get_notes()
            self.stats['total_notes'] = len(notes)
            
            if not notes:
                self.console.print("📭 No notes found to process")
                return self.stats
                
            self.console.print(f"🔍 Found {len(notes)} notes to process")
            
            # Process notes in batches
            results = []
            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                BarColumn(),
                TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
                TimeRemainingColumn(),
                console=self.console
            ) as progress:
                
                main_task = progress.add_task("Processing notes...", total=len(notes))
                
                for i in range(0, len(notes), batch_size):
                    batch = notes[i:i + batch_size]
                    batch_results = await self._process_batch(batch, tasks, progress, main_task)
                    results.extend(batch_results)
                    
            # Archive processed notes if requested
            if archive_after_import:
                await self._archive_processed_notes(source, results)
                
            self.stats['end_time'] = datetime.now()
            self._print_final_stats()
            
            return {
                'stats': self.stats,
                'results': results,
                'output_dir': str(self.output_dir)
            }
            
        except Exception as e:
            logger.error(f"Batch import failed: {e}")
            self.console.print(f"❌ Batch import failed: {e}")
            return {'stats': self.stats, 'error': str(e)}
    
    async def _process_batch(self, 
                           batch: List[Dict[str, Any]], 
                           tasks: List[str],
                           progress: Progress,
                           main_task: TaskID) -> List[Dict[str, Any]]:
        """Process a batch of notes concurrently."""
        batch_results = []
        
        # Create tasks for concurrent processing
        processing_tasks = []
        for note in batch:
            task = self._process_single_note(note, tasks)
            processing_tasks.append(task)
            
        # Wait for all tasks to complete
        results = await asyncio.gather(*processing_tasks, return_exceptions=True)
        
        # Process results
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                logger.error(f"Failed to process note {batch[i].get('title', 'Unknown')}: {result}")
                self.stats['failed_notes'] += 1
                batch_results.append({
                    'note': batch[i],
                    'status': 'failed',
                    'error': str(result)
                })
            else:
                self.stats['processed_notes'] += 1
                batch_results.append(result)
                
            progress.update(main_task, advance=1)
            
        return batch_results
    
    async def _process_single_note(self, 
                                 note: Dict[str, Any], 
                                 tasks: List[str]) -> Dict[str, Any]:
        """Process a single note with the specified tasks."""
        try:
            original_content = note['content']
            processed_content = original_content
            processing_results = {}
            
            # Apply each processing task
            for task in tasks:
                result = await self.processor.process_content(
                    content=processed_content,
                    task=task,
                    metadata={'source': note.get('source', 'unknown')}
                )
                
                if result.success:
                    processing_results[task] = result.content
                    if task == 'enhance':
                        processed_content = result.content
                else:
                    logger.warning(f"Task {task} failed for note {note.get('title', 'Unknown')}")
                    
            # Generate filename
            title = note.get('title', f"note_{datetime.now().strftime('%Y%m%d_%H%M%S')}")
            safe_title = "".join(c for c in title if c.isalnum() or c in (' ', '-', '_')).rstrip()
            filename = f"{safe_title}.md"
            
            # Save processed note
            output_path = self.output_dir / filename
            await self._save_processed_note(output_path, note, processed_content, processing_results)
            
            # Store in vector database
            await self._store_in_vector_db(note, processed_content)
            
            return {
                'note': note,
                'status': 'success',
                'output_path': str(output_path),
                'processing_results': processing_results,
                'filename': filename
            }
            
        except Exception as e:
            logger.error(f"Error processing note {note.get('title', 'Unknown')}: {e}")
            raise
    
    async def _save_processed_note(self, 
                                 output_path: Path, 
                                 original_note: Dict[str, Any],
                                 processed_content: str,
                                 processing_results: Dict[str, Any]):
        """Save processed note to file with metadata."""
        try:
            # Create frontmatter
            frontmatter = {
                'title': original_note.get('title', 'Untitled'),
                'source': original_note.get('source', 'unknown'),
                'original_date': original_note.get('created_at', datetime.now().isoformat()),
                'processed_date': datetime.now().isoformat(),
                'tags': original_note.get('tags', []),
                'processing_tasks': list(processing_results.keys())
            }
            
            # Write note with frontmatter
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write("---\n")
                for key, value in frontmatter.items():
                    if isinstance(value, list):
                        f.write(f"{key}: {json.dumps(value)}\n")
                    else:
                        f.write(f"{key}: {value}\n")
                f.write("---\n\n")
                f.write(processed_content)
                
                # Add processing results as appendix
                if processing_results:
                    f.write("\n\n## Processing Results\n\n")
                    for task, result in processing_results.items():
                        if task != 'enhance':  # Don't duplicate enhanced content
                            f.write(f"### {task.replace('_', ' ').title()}\n\n")
                            f.write(f"{result}\n\n")
                            
        except Exception as e:
            logger.error(f"Error saving processed note to {output_path}: {e}")
            raise
    
    async def _store_in_vector_db(self, 
                                original_note: Dict[str, Any], 
                                processed_content: str):
        """Store note in vector database for semantic search."""
        try:
            metadata = {
                'title': original_note.get('title', 'Untitled'),
                'source': original_note.get('source', 'unknown'),
                'tags': original_note.get('tags', []),
                'created_at': original_note.get('created_at', datetime.now().isoformat()),
                'processed_at': datetime.now().isoformat()
            }
            
            # Use title as document ID, fallback to hash of content
            doc_id = original_note.get('title', f"note_{hash(processed_content)}")
            
            await self.vector_store.add_document(
                doc_id=doc_id,
                content=processed_content,
                metadata=metadata
            )
            
        except Exception as e:
            logger.error(f"Error storing note in vector database: {e}")
            # Don't raise - vector storage failure shouldn't stop import
    
    async def _archive_processed_notes(self, 
                                     source: BaseSource, 
                                     results: List[Dict[str, Any]]):
        """Archive successfully processed notes from source."""
        try:
            successful_notes = [r for r in results if r.get('status') == 'success']
            if successful_notes:
                await source.archive_notes([r['note'] for r in successful_notes])
                self.console.print(f"📦 Archived {len(successful_notes)} processed notes")
        except Exception as e:
            logger.error(f"Error archiving notes: {e}")
            self.console.print(f"⚠️  Failed to archive notes: {e}")
    
    def _print_final_stats(self):
        """Print final import statistics."""
        duration = self.stats['end_time'] - self.stats['start_time']
        
        self.console.print("\n" + "="*50)
        self.console.print("📊 [bold]Batch Import Complete![/bold]")
        self.console.print("="*50)
        self.console.print(f"📝 Total notes: {self.stats['total_notes']}")
        self.console.print(f"✅ Processed: {self.stats['processed_notes']}")
        self.console.print(f"❌ Failed: {self.stats['failed_notes']}")
        self.console.print(f"⏸️  Skipped: {self.stats['skipped_notes']}")
        self.console.print(f"⏱️  Duration: {duration}")
        self.console.print(f"📁 Output: {self.output_dir}")
        
        if self.stats['processed_notes'] > 0:
            rate = self.stats['processed_notes'] / duration.total_seconds()
            self.console.print(f"🚀 Rate: {rate:.2f} notes/second")
            
        self.console.print("="*50)


async def main():
    """Demo/test function for the batch importer."""
    console = Console()
    
    # Example usage
    console.print("🚀 [bold]Selene Batch Importer Demo[/bold]")
    
    # Create sample notes directory
    sample_dir = Path("sample_notes")
    sample_dir.mkdir(exist_ok=True)
    
    # Create sample notes
    sample_notes = [
        {
            'title': 'Daily Reflection',
            'content': 'Today was productive. Worked on the batch importer system.',
            'tags': ['daily', 'reflection'],
            'created_at': datetime.now().isoformat()
        },
        {
            'title': 'Project Ideas',
            'content': 'Ideas for improving the note processing system.',
            'tags': ['ideas', 'project'],
            'created_at': datetime.now().isoformat()
        }
    ]
    
    # Save sample notes
    for note in sample_notes:
        file_path = sample_dir / f"{note['title'].replace(' ', '_')}.txt"
        with open(file_path, 'w') as f:
            f.write(note['content'])
    
    # Create text file source
    source = TextFileSource(sample_dir, tag_filter=None)
    
    # Create batch importer
    importer = BatchImporter(output_dir="processed_notes")
    
    # Import notes
    results = await importer.import_from_source(
        source=source,
        tasks=['enhance', 'extract_insights'],
        batch_size=2,
        archive_after_import=False
    )
    
    console.print(f"\n✅ Import complete! Results: {results}")


if __name__ == "__main__":
    asyncio.run(main())