#!/usr/bin/env python3
"""
Test script for the real-time LLM processing monitoring system.
"""

import asyncio
import time
from selene.processors.ollama_processor import OllamaProcessor


async def test_monitoring():
    """Test the monitoring system with actual processing."""
    print("🔍 Testing Real-time LLM Processing Monitor")
    print("=" * 50)
    
    # Test content
    test_content = """
    This is a test note for the monitoring system. 
    It should demonstrate how the real-time monitoring works 
    with different processing stages and progress updates.
    """
    
    # Initialize processor with monitoring enabled
    processor = OllamaProcessor({
        "base_url": "http://localhost:11434",
        "model": "llama3.2:1b",
        "enable_monitoring": True,
        "validate_on_init": False
    })
    
    print("📝 Processing test content...")
    print(f"Content: {test_content.strip()}")
    print()
    
    # Test different tasks
    tasks = ["summarize", "enhance", "extract_insights", "questions"]
    
    for task in tasks:
        print(f"🔄 Testing {task} task...")
        
        try:
            start_time = time.time()
            result = await processor.process(test_content, task=task)
            end_time = time.time()
            
            if result.success:
                print(f"✅ {task} completed in {end_time - start_time:.2f}s")
                print(f"   Session ID: {result.session_id}")
                print(f"   Output: {result.content[:100]}...")
            else:
                print(f"❌ {task} failed: {result.error}")
            
        except Exception as e:
            print(f"❌ {task} error: {e}")
        
        print()
        
        # Small delay between tasks
        await asyncio.sleep(1)
    
    print("🎉 Monitoring test completed!")
    print()
    print("📊 To view real-time monitoring:")
    print("1. Start the web server: python -m selene.main web")
    print("2. Open http://localhost:8000 in your browser")
    print("3. Click on 'Processing Monitor' tab")
    print("4. Run this test script again to see live updates")


if __name__ == "__main__":
    asyncio.run(test_monitoring())