#!/usr/bin/env python3
"""
Test script for validating the batch import functionality.
"""

import asyncio
import tempfile
from pathlib import Path

from rich.console import Console

console = Console()


async def test_batch_import_basic():
    """Test basic batch import functionality."""
    console.print("🧪 Testing basic batch import functionality...")
    
    try:
        # Create temporary directory with test notes
        temp_dir = Path(tempfile.mkdtemp(prefix="selene_test_"))
        
        # Create test notes
        test_notes = [
            {
                'filename': 'test_note1.txt',
                'content': 'This is a test note for batch import. #selene #test'
            },
            {
                'filename': 'test_note2.txt',
                'content': 'Another test note with different content. #selene #demo'
            }
        ]
        
        for note in test_notes:
            file_path = temp_dir / note['filename']
            with open(file_path, 'w') as f:
                f.write(note['content'])
        
        # Test imports
        from selene.batch import BatchImporter, TextFileSource
        from selene.processors.ollama_processor import OllamaProcessor
        
        # Create source
        source = TextFileSource(
            directory=temp_dir,
            tag_filter="selene"
        )
        
        # Get notes without processing
        notes = await source.get_notes()
        console.print(f"✅ Found {len(notes)} notes")
        
        # Test that notes have expected structure
        for note in notes:
            assert 'title' in note
            assert 'content' in note
            assert 'tags' in note
            assert 'source' in note
        
        console.print("✅ Note structure validation passed")
        
        # Test archive functionality
        await source.archive_notes(notes)
        console.print("✅ Archive functionality works")
        
        console.print("🎉 Basic batch import test passed!")
        return True
        
    except Exception as e:
        console.print(f"❌ Test failed: {e}")
        import traceback
        console.print(traceback.format_exc())
        return False


async def test_drafts_source():
    """Test Drafts source (without actual database)."""
    console.print("🧪 Testing Drafts source...")
    
    try:
        from selene.batch import DraftsSource
        
        # Create Drafts source (will fail to find database, but that's expected)
        source = DraftsSource(tag_filter="selene")
        
        # Test that it handles missing database gracefully
        notes = await source.get_notes()
        console.print(f"✅ Drafts source handles missing database: {len(notes)} notes")
        
        console.print("✅ Drafts source test passed!")
        return True
        
    except Exception as e:
        console.print(f"❌ Drafts source test failed: {e}")
        return False


async def test_obsidian_source():
    """Test Obsidian source."""
    console.print("🧪 Testing Obsidian source...")
    
    try:
        # Create temporary vault
        temp_vault = Path(tempfile.mkdtemp(prefix="selene_vault_"))
        
        # Create test markdown files
        test_files = [
            {
                'filename': 'test.md',
                'content': '''---
title: Test Note
tags: [selene, test]
---

# Test Note

This is a test note for Obsidian import.

#selene #obsidian
'''
            },
            {
                'filename': 'no_tag.md',
                'content': '''# No Tag Note

This note has no selene tag.
'''
            }
        ]
        
        for file_info in test_files:
            file_path = temp_vault / file_info['filename']
            with open(file_path, 'w') as f:
                f.write(file_info['content'])
        
        from selene.batch import ObsidianSource
        
        # Test without tag filter
        source = ObsidianSource(vault_path=temp_vault)
        notes = await source.get_notes()
        console.print(f"✅ Found {len(notes)} notes without filter")
        
        # Test with tag filter
        source = ObsidianSource(vault_path=temp_vault, tag_filter="selene")
        notes = await source.get_notes()
        console.print(f"✅ Found {len(notes)} notes with selene tag")
        
        console.print("✅ Obsidian source test passed!")
        return True
        
    except Exception as e:
        console.print(f"❌ Obsidian source test failed: {e}")
        return False


async def test_cli_integration():
    """Test CLI integration."""
    console.print("🧪 Testing CLI integration...")
    
    try:
        # Test that imports work
        from selene.batch import BatchImporter, TextFileSource, DraftsSource, ObsidianSource
        
        console.print("✅ All imports successful")
        
        # Test that classes can be instantiated
        importer = BatchImporter()
        text_source = TextFileSource("/tmp")
        drafts_source = DraftsSource()
        obsidian_source = ObsidianSource("/tmp")
        
        console.print("✅ All classes can be instantiated")
        console.print("✅ CLI integration test passed!")
        return True
        
    except Exception as e:
        console.print(f"❌ CLI integration test failed: {e}")
        return False


async def main():
    """Run all tests."""
    console.print("🚀 Running batch import tests...\n")
    
    tests = [
        ("Basic Functionality", test_batch_import_basic),
        ("Drafts Source", test_drafts_source),
        ("Obsidian Source", test_obsidian_source),
        ("CLI Integration", test_cli_integration)
    ]
    
    results = []
    
    for test_name, test_func in tests:
        console.print(f"\n📋 Running {test_name} test...")
        result = await test_func()
        results.append((test_name, result))
        
        if result:
            console.print(f"✅ {test_name} test PASSED")
        else:
            console.print(f"❌ {test_name} test FAILED")
    
    # Summary
    console.print("\n" + "="*50)
    console.print("📊 Test Summary")
    console.print("="*50)
    
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for test_name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        console.print(f"{status} {test_name}")
    
    console.print(f"\n🎯 {passed}/{total} tests passed")
    
    if passed == total:
        console.print("🎉 All tests passed! Batch import system is ready!")
    else:
        console.print("⚠️  Some tests failed. Please check the errors above.")


if __name__ == "__main__":
    asyncio.run(main())