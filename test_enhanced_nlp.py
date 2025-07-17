"""
Test script for enhanced NLP vault interaction capabilities.
"""

import asyncio
from pathlib import Path
from selene.chat.nlp.language_processor import LanguageProcessor
from selene.chat.nlp.intent_classifier import Intent


async def test_enhanced_nlp():
    """Test the enhanced NLP system."""
    print("🧪 Testing Enhanced NLP System for Vault Interactions")
    print("=" * 60)
    
    # Initialize language processor
    processor = LanguageProcessor()
    
    # Test cases with expected outcomes
    test_cases = [
        # Read note tests
        ("Show me the meeting notes", Intent.READ_NOTE),
        ("Read the note called 'project ideas'", Intent.READ_NOTE),
        ("Open research.md", Intent.READ_NOTE),
        ("What's in my daily notes?", Intent.READ_NOTE),
        
        # Write note tests
        ("Create a note called 'Weekly Planning'", Intent.WRITE_NOTE),
        ("Write a new note about machine learning", Intent.WRITE_NOTE),
        ("Make a note with my ideas", Intent.WRITE_NOTE),
        
        # Search tests
        ("Search for notes about AI", Intent.SEARCH_NOTES),
        ("Find anything related to project management", Intent.SEARCH_NOTES),
        ("Look for notes containing 'meeting'", Intent.SEARCH_NOTES),
        
        # Vector search tests
        ("Find notes similar to machine learning", Intent.VECTOR_SEARCH),
        ("Search semantically for research insights", Intent.VECTOR_SEARCH),
        
        # AI processing tests
        ("Summarize my meeting notes", Intent.SUMMARIZE),
        ("Extract insights from my research", Intent.EXTRACT_INSIGHTS),
        ("Generate questions from this brainstorm", Intent.GENERATE_QUESTIONS),
        ("Enhance my rough notes", Intent.ENHANCE),
        
        # List notes tests
        ("List all my notes", Intent.LIST_NOTES),
        ("What notes do I have?", Intent.LIST_NOTES),
        ("Show me all files", Intent.LIST_NOTES),
        
        # Ambiguous/low confidence tests
        ("Do something with notes", Intent.UNKNOWN),
        ("Help me", Intent.HELP),
        ("Hello", Intent.GREETING),
    ]
    
    print("\n📋 Test Results:")
    print("-" * 60)
    
    correct_predictions = 0
    total_tests = len(test_cases)
    
    for i, (message, expected_intent) in enumerate(test_cases, 1):
        print(f"\n{i:2d}. Testing: '{message}'")
        
        try:
            # Process the message
            result = processor.process_message(message)
            
            # Check if intent matches
            intent_correct = result.intent == expected_intent
            if intent_correct:
                correct_predictions += 1
                status = "✅ PASS"
            else:
                status = "❌ FAIL"
                
            print(f"    Expected: {expected_intent.value}")
            print(f"    Got:      {result.intent.value}")
            print(f"    Confidence: {result.confidence:.1%}")
            print(f"    Tool: {result.tool_name}")
            print(f"    Parameters: {result.parameters}")
            print(f"    Status: {status}")
            
            if result.missing_parameters:
                print(f"    Missing: {result.missing_parameters}")
            if result.suggestions:
                print(f"    Suggestions: {result.suggestions}")
                
        except Exception as e:
            print(f"    ❌ ERROR: {e}")
            
    print("\n" + "=" * 60)
    print(f"📊 Overall Results:")
    print(f"   Correct predictions: {correct_predictions}/{total_tests}")
    print(f"   Accuracy: {correct_predictions/total_tests:.1%}")
    
    if correct_predictions >= total_tests * 0.8:
        print("   🎉 NLP System: EXCELLENT")
    elif correct_predictions >= total_tests * 0.6:
        print("   👍 NLP System: GOOD")
    else:
        print("   ⚠️  NLP System: NEEDS IMPROVEMENT")
    
    print("\n🔄 Testing Context Awareness...")
    print("-" * 40)
    
    # Test context-aware conversation
    context_tests = [
        ("Read my meeting notes", Intent.READ_NOTE),
        ("Summarize it", Intent.SUMMARIZE),  # Should use context
        ("Search for AI topics", Intent.SEARCH_NOTES),
        ("Find more like that", Intent.VECTOR_SEARCH),  # Should use context
    ]
    
    for message, expected_intent in context_tests:
        print(f"\nProcessing: '{message}'")
        result = processor.process_message(message)
        
        # Update context for next message
        processor.update_context(message, result, f"Processed {result.intent.value}")
        
        print(f"  Intent: {result.intent.value}")
        print(f"  Confidence: {result.confidence:.1%}")
        print(f"  Context used: {result.context_used}")
        if result.parameters:
            print(f"  Parameters: {result.parameters}")
    
    print("\n🏁 Enhanced NLP Testing Complete!")


if __name__ == "__main__":
    asyncio.run(test_enhanced_nlp())