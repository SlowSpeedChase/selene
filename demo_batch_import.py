#!/usr/bin/env python3
"""
Demo script for testing the batch import functionality.

This script demonstrates how to use the batch import system to process
notes from various sources like Drafts app, text files, and Obsidian vaults.
"""

import asyncio
import tempfile
from pathlib import Path
from datetime import datetime

from rich.console import Console
from rich.panel import Panel
from rich.text import Text

console = Console()


def create_sample_notes():
    """Create sample notes for testing."""
    # Create temporary directory for sample notes
    temp_dir = Path(tempfile.mkdtemp(prefix="selene_demo_"))
    
    sample_notes = [
        {
            'filename': 'daily_reflection.txt',
            'content': '''# Daily Reflection - July 17, 2025

Had a productive day working on the Selene batch import system. The architecture is coming together nicely.

Key accomplishments:
- Implemented BatchImporter class with progress tracking
- Added support for multiple sources (Drafts, text files, Obsidian)
- Created CLI integration for easy usage
- Added archive functionality after processing

Next steps:
- Test with real Drafts data
- Optimize performance for large batches
- Add more sophisticated error handling

#selene #productivity #daily
'''
        },
        {
            'filename': 'project_ideas.txt',
            'content': '''# Project Ideas

## AI-Powered Note Processing
- Implement semantic search across all notes
- Add automatic tagging based on content analysis
- Create smart suggestions for related notes

## Batch Processing Improvements
- Add support for more file formats (PDF, DOCX, etc.)
- Implement incremental processing (only process new/changed notes)
- Add scheduling for automated imports

## Integration Features
- Connect with more note-taking apps (Notion, Roam, etc.)
- Add web clipper functionality
- Create mobile app for quick note capture

#selene #ideas #projects
'''
        },
        {
            'filename': 'meeting_notes.txt',
            'content': '''# Team Meeting - July 17, 2025

## Attendees
- John (Product Manager)
- Sarah (Developer)
- Mike (Designer)

## Discussion Points
1. **Batch Import Feature**
   - Architecture review complete
   - Need to test with real data
   - Performance looks good for up to 1000 notes

2. **User Experience**
   - CLI interface is intuitive
   - Web interface needed for broader adoption
   - Mobile support is future priority

3. **Next Sprint Planning**
   - Focus on production deployment
   - Add comprehensive error handling
   - Create user documentation

## Action Items
- [ ] Test batch import with Drafts app
- [ ] Create production deployment guide
- [ ] Write user documentation
- [ ] Schedule next review meeting

#selene #meeting #team
'''
        },
        {
            'filename': 'research_notes.txt',
            'content': '''# Research: Local AI Processing

## Current State
Local AI processing with Ollama is working well. The llama3.2:1b model provides good quality with fast processing times.

## Performance Metrics
- Processing time: 7-12 seconds per note
- Memory usage: ~2GB during processing
- Quality: Good for enhancement and insight extraction

## Comparison with Cloud Solutions
- **Local (Ollama)**: Fast, private, no costs
- **Cloud (OpenAI)**: Higher quality, slower, costs money

## Recommendations
- Use local processing for daily workflows
- Keep cloud processing as fallback for high-quality tasks
- Implement hybrid approach for best of both worlds

#selene #research #ai #performance
'''
        },
        {
            'filename': 'book_notes.txt',
            'content': '''# Book Notes: "Building a Second Brain"

## Key Concepts

### CODE Method
- **Capture**: Save valuable information
- **Organize**: Structure for actionability
- **Distill**: Extract key insights
- **Express**: Share your work

### Progressive Summarization
1. Start with original content
2. Add bold formatting for key points
3. Highlight most important parts
4. Create executive summary

### PARA Method
- **Projects**: What you're working on now
- **Areas**: Ongoing responsibilities
- **Resources**: Future reference topics
- **Archives**: Inactive items

## Implementation in Selene
- Batch import handles the "Capture" phase
- AI processing provides "Distill" functionality
- Vector search enables "Organize" and "Express"
- Chat interface makes everything accessible

#selene #book-notes #second-brain #productivity
'''
        }
    ]
    
    # Write sample notes
    for note in sample_notes:
        file_path = temp_dir / note['filename']
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(note['content'])
    
    console.print(f"📝 Created {len(sample_notes)} sample notes in {temp_dir}")
    return temp_dir


async def demo_text_file_import():
    """Demo importing from text files."""
    console.print("\n" + "="*60)
    console.print("🗂️  [bold]Text File Import Demo[/bold]")
    console.print("="*60)
    
    # Create sample notes
    sample_dir = create_sample_notes()
    
    try:
        from selene.batch import BatchImporter, TextFileSource
        from selene.processors.ollama_processor import OllamaProcessor
        
        # Create text file source
        source = TextFileSource(
            directory=sample_dir,
            tag_filter="selene"
        )
        
        # Create processor
        processor = OllamaProcessor({"model": "llama3.2:1b"})
        
        # Create batch importer
        importer = BatchImporter(
            processor=processor,
            output_dir="demo_processed_notes"
        )
        
        console.print(f"📂 Source directory: {sample_dir}")
        console.print("🏷️  Tag filter: selene")
        console.print("🔧 Tasks: enhance, extract_insights")
        console.print("📊 Batch size: 3")
        
        # Import notes
        results = await importer.import_from_source(
            source=source,
            tasks=['enhance', 'extract_insights'],
            batch_size=3,
            archive_after_import=True
        )
        
        # Show results
        if results.get('error'):
            console.print(f"[red]❌ Import failed: {results['error']}[/red]")
        else:
            stats = results.get('stats', {})
            console.print(f"\n✅ [bold green]Import completed successfully![/bold green]")
            console.print(f"📊 Total notes: {stats.get('total_notes', 0)}")
            console.print(f"✅ Processed: {stats.get('processed_notes', 0)}")
            console.print(f"❌ Failed: {stats.get('failed_notes', 0)}")
            console.print(f"📁 Output: {results.get('output_dir', 'demo_processed_notes')}")
            
    except Exception as e:
        console.print(f"[red]❌ Demo failed: {e}[/red]")
        import traceback
        console.print(traceback.format_exc())


async def demo_cli_usage():
    """Demo CLI usage examples."""
    console.print("\n" + "="*60)
    console.print("💻 [bold]CLI Usage Examples[/bold]")
    console.print("="*60)
    
    examples = [
        {
            'title': 'Import from Drafts app',
            'command': 'selene batch-import --source drafts --tag selene --tasks enhance,extract_insights'
        },
        {
            'title': 'Import from text files',
            'command': 'selene batch-import --source text --path ~/notes --tag selene --output ~/processed'
        },
        {
            'title': 'Import from Obsidian vault',
            'command': 'selene batch-import --source obsidian --path ~/vault --tag inbox --tasks summarize'
        },
        {
            'title': 'Dry run to see what would be processed',
            'command': 'selene batch-import --source text --path ~/notes --dry-run'
        },
        {
            'title': 'Process with specific model and batch size',
            'command': 'selene batch-import --source drafts --model llama3.2 --batch-size 10'
        }
    ]
    
    for example in examples:
        console.print(f"\n🔧 {example['title']}:")
        console.print(f"   [cyan]{example['command']}[/cyan]")


def demo_features():
    """Demo the key features of the batch import system."""
    console.print("\n" + "="*60)
    console.print("🚀 [bold]Batch Import Features[/bold]")
    console.print("="*60)
    
    features = [
        {
            'title': 'Multiple Source Support',
            'description': 'Import from Drafts app, text files, and Obsidian vaults',
            'icon': '📱'
        },
        {
            'title': 'AI Processing Pipeline',
            'description': 'Enhance, extract insights, generate questions, and more',
            'icon': '🤖'
        },
        {
            'title': 'Batch Processing',
            'description': 'Process multiple notes concurrently for efficiency',
            'icon': '⚡'
        },
        {
            'title': 'Archive Management',
            'description': 'Automatically archive processed notes from source',
            'icon': '📦'
        },
        {
            'title': 'Vector Database Integration',
            'description': 'Store processed notes for semantic search',
            'icon': '🔍'
        },
        {
            'title': 'Progress Tracking',
            'description': 'Real-time progress bars and statistics',
            'icon': '📊'
        },
        {
            'title': 'Error Handling',
            'description': 'Robust error handling with detailed reporting',
            'icon': '🛡️'
        },
        {
            'title': 'CLI Integration',
            'description': 'Easy-to-use command-line interface',
            'icon': '💻'
        }
    ]
    
    for feature in features:
        console.print(f"\n{feature['icon']} [bold]{feature['title']}[/bold]")
        console.print(f"   {feature['description']}")


async def main():
    """Main demo function."""
    console.print(Panel.fit(
        Text("🚀 Selene Batch Import Demo", style="bold magenta", justify="center"),
        border_style="bright_blue"
    ))
    
    console.print("\n🎯 This demo showcases the batch import functionality for processing")
    console.print("   notes from various sources like Drafts app, text files, and Obsidian.")
    
    # Show features
    demo_features()
    
    # Show CLI usage examples
    await demo_cli_usage()
    
    # Ask user if they want to run the actual demo
    console.print("\n" + "="*60)
    console.print("🔍 [bold]Live Demo[/bold]")
    console.print("="*60)
    
    console.print("\n⚠️  [yellow]Note: This will create sample notes and process them with AI.[/yellow]")
    console.print("   Make sure Ollama is running with the llama3.2:1b model.")
    
    try:
        user_input = input("\n🤔 Run live demo? (y/n): ").strip().lower()
        if user_input in ['y', 'yes']:
            await demo_text_file_import()
        else:
            console.print("\n✅ Demo completed. Try the CLI commands above!")
    except KeyboardInterrupt:
        console.print("\n\n👋 Demo interrupted. Goodbye!")
    except Exception as e:
        console.print(f"\n[red]❌ Demo error: {e}[/red]")


if __name__ == "__main__":
    asyncio.run(main())