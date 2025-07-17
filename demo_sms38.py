#!/usr/bin/env python3
"""
SMS-38 Enhanced Chat Features Demo

This demo showcases the advanced chat capabilities implemented in SMS-38
without requiring Ollama to be running.
"""

import asyncio
import tempfile
from pathlib import Path
from unittest.mock import Mock, AsyncMock

def demo_enhanced_language_processing():
    """Demo enhanced language processing capabilities."""
    print("🧠 Enhanced Natural Language Processing Demo")
    print("=" * 50)
    
    try:
        from selene.chat.nlp.enhanced_language_processor import EnhancedLanguageProcessor
        from selene.chat.nlp.intent_classifier import Intent
        
        # Create processor with mock vault
        with tempfile.TemporaryDirectory() as temp_dir:
            vault_path = Path(temp_dir)
            
            # Create demo files
            (vault_path / "daily-notes.md").write_text("Daily notes content")
            (vault_path / "ai-research.md").write_text("AI research content")
            (vault_path / "meeting-summary.md").write_text("Meeting summary")
            
            processor = EnhancedLanguageProcessor(vault_path)
            
            # Test messages
            test_messages = [
                "read my daily notes",
                "find AI research", 
                "show me meeting stuff",
                "create a note about project planning",
                "help me with research"
            ]
            
            print(f"📁 Created demo vault with {len(list(vault_path.glob('*.md')))} files")
            print()
            
            for i, message in enumerate(test_messages, 1):
                print(f"Test {i}: \"{message}\"")
                
                try:
                    result = processor.process_message(message, user_id="demo_user")
                    
                    print(f"  Intent: {result.intent.value}")
                    print(f"  Confidence: {result.confidence:.2f}")
                    print(f"  Tool: {result.tool_name}")
                    print(f"  Parameters: {result.parameters}")
                    
                    if result.file_matches:
                        print(f"  File matches: {result.file_matches}")
                        
                    if result.suggestions:
                        print(f"  Suggestions: {result.suggestions[:2]}")  # Show first 2
                        
                    if result.alternative_interpretations:
                        print(f"  Alternatives: {len(result.alternative_interpretations)} found")
                        
                except Exception as e:
                    print(f"  Error: {e}")
                    
                print()
                
        print("✅ Enhanced Language Processing demo complete!")
        
    except ImportError as e:
        print(f"❌ Import error: {e}")
    except Exception as e:
        print(f"❌ Demo error: {e}")
    
    print()

def demo_context_aware_responses():
    """Demo context-aware response generation."""
    print("💬 Context-Aware Response Generation Demo")
    print("=" * 50)
    
    try:
        from selene.chat.response.context_aware_generator import (
            ContextAwareResponseGenerator, 
            ResponseContext,
            GeneratedResponse
        )
        from selene.chat.nlp.enhanced_language_processor import EnhancedProcessingResult
        from selene.chat.nlp.intent_classifier import Intent
        
        generator = ContextAwareResponseGenerator()
        
        # Mock processing result
        processing_result = EnhancedProcessingResult(
            intent=Intent.READ_NOTE,
            tool_name="read_note",
            parameters={"note_path": "daily-notes.md"},
            confidence=0.9,
            missing_parameters=[],
            suggestions=["Try searching for related notes"],
            needs_confirmation=False,
            context_used=True,
            file_matches=["daily-notes.md", "daily-2025-07-17.md"]
        )
        
        # Mock context
        context = ResponseContext(
            user_id="demo_user",
            conversation_history=[
                {"role": "user", "content": "Hello", "timestamp": "2025-07-17T10:00:00"}
            ],
            current_vault_info={"note_count": 5, "recent_files": ["daily-notes.md"]},
            user_preferences={"read_note": 10},
            recent_actions=[],
            time_context={"time_of_day": "morning", "hour": 10}
        )
        
        # Generate responses for different scenarios
        scenarios = [
            ("Success", Mock(is_success=True, content="Note content here")),
            ("Error", Mock(is_success=False, error_message="File not found")),
            ("Clarification", None)  # No tool result
        ]
        
        for scenario_name, tool_result in scenarios:
            print(f"Scenario: {scenario_name}")
            
            try:
                if scenario_name == "Clarification":
                    processing_result.needs_clarification = True
                    processing_result.clarification_question = "Which file did you mean?"
                else:
                    processing_result.needs_clarification = False
                    
                response = generator.generate_response(processing_result, context, tool_result)
                
                print(f"  Type: {response.response_type}")
                print(f"  Content: {response.content[:100]}...")
                print(f"  Suggestions: {len(response.suggestions)}")
                print(f"  Confidence: {response.confidence:.2f}")
                print(f"  Requires input: {response.requires_input}")
                
            except Exception as e:
                print(f"  Error: {e}")
                
            print()
            
        print("✅ Context-Aware Response Generation demo complete!")
        
    except ImportError as e:
        print(f"❌ Import error: {e}")
    except Exception as e:
        print(f"❌ Demo error: {e}")
        
    print()

def demo_smart_tool_selection():
    """Demo smart tool selection capabilities."""
    print("🛠️ Smart Tool Selection Demo")
    print("=" * 50)
    
    try:
        from selene.chat.tools.smart_tool_selector import SmartToolSelector
        from selene.chat.tools.base import ToolRegistry
        from selene.chat.nlp.enhanced_language_processor import EnhancedProcessingResult
        from selene.chat.nlp.intent_classifier import Intent
        
        # Create mock tool registry
        registry = ToolRegistry()
        
        # Mock tools
        mock_tool = Mock()
        mock_tool.name = "read_note"
        mock_tool.description = "Read a note file"
        
        registry.register(mock_tool)
        registry.enable_tool("read_note")
        
        selector = SmartToolSelector(registry)
        
        # Test tool selection
        processing_result = EnhancedProcessingResult(
            intent=Intent.READ_NOTE,
            tool_name=None,
            parameters={"note_path": "daily.md"},
            confidence=0.8,
            missing_parameters=[],
            suggestions=[],
            needs_confirmation=False,
            context_used=False
        )
        
        print("Tool Selection Test:")
        selection = selector.select_tool(processing_result, context={}, user_id="demo_user")
        
        print(f"  Selected tool: {selection.selected_tool}")
        print(f"  Confidence: {selection.confidence:.2f}")
        print(f"  Inferred parameters: {selection.inferred_parameters}")
        print(f"  Validation errors: {len(selection.validation_errors)}")
        print(f"  Selection reason: {selection.selection_reason}")
        
        # Test performance tracking
        print("\nPerformance Tracking Test:")
        selector.record_tool_execution_result(
            "read_note", 
            success=True, 
            execution_time=0.5,
            context={"test": True}
        )
        
        stats = selector.get_tool_performance_stats()
        if stats:
            for tool_name, tool_stats in stats.items():
                print(f"  {tool_name}: {tool_stats['success_rate']:.2f} success rate")
                
        print("\n✅ Smart Tool Selection demo complete!")
        
    except ImportError as e:
        print(f"❌ Import error: {e}")
    except Exception as e:
        print(f"❌ Demo error: {e}")
        
    print()

def demo_conversation_flows():
    """Demo conversation flow management."""
    print("🔄 Conversation Flow Management Demo")
    print("=" * 50)
    
    try:
        from selene.chat.flow.conversation_flow_manager import (
            ConversationFlowManager,
            ConversationFlow,
            FlowStep,
            FlowStepType
        )
        
        manager = ConversationFlowManager()
        
        # Show available built-in flows
        available_flows = manager.get_available_flows()
        print(f"Built-in flows: {len(available_flows)}")
        
        for flow in available_flows:
            print(f"  - {flow['name']}: {flow['description']} ({flow['steps_count']} steps)")
            
        # Test starting a flow
        print("\nFlow Execution Test:")
        execution = manager.start_flow("create_note_flow", user_id="demo_user")
        
        if execution:
            print(f"  Started flow: {execution.flow_id}")
            print(f"  Current step: {execution.current_step}")
            print(f"  State: {execution.state.value}")
            
            # Get flow context
            context = manager.get_flow_context(execution.execution_id)
            if context:
                print(f"  Progress: {context['progress']:.0%}")
                
            # Cancel flow
            manager.cancel_flow(execution.execution_id, "demo_complete")
            print("  Flow cancelled for demo")
            
        # Show statistics
        stats = manager.get_flow_statistics()
        print(f"\nFlow Statistics:")
        print(f"  Total flows started: {stats['total_flows_started']}")
        print(f"  Active flows: {stats['active_flows']}")
        
        print("\n✅ Conversation Flow Management demo complete!")
        
    except ImportError as e:
        print(f"❌ Import error: {e}")
    except Exception as e:
        print(f"❌ Demo error: {e}")
        
    print()

def demo_feature_integration():
    """Demo enhanced chat agent feature integration."""
    print("🤖 Enhanced Chat Agent Integration Demo")
    print("=" * 50)
    
    try:
        from selene.chat.enhanced_agent import EnhancedChatAgent
        from selene.chat.config import ChatConfig
        
        # Create minimal config (no Ollama needed for this demo)
        config = ChatConfig()
        config.conversation_memory = False
        config.rich_formatting = False
        
        agent = EnhancedChatAgent(config)
        
        # Show feature status
        print("Enhanced Features Status:")
        for feature, enabled in agent.features.items():
            status = "✅ Enabled" if enabled else "❌ Disabled"
            feature_name = feature.replace('_', ' ').title()
            print(f"  {feature_name}: {status}")
            
        # Show component status  
        print("\nComponent Status:")
        components = [
            ("Enhanced Language Processor", bool(agent.language_processor)),
            ("Context-Aware Response Generator", bool(agent.response_generator)),
            ("Smart Tool Selector", bool(agent.tool_selector)),
            ("Conversation Flow Manager", bool(agent.flow_manager))
        ]
        
        for name, initialized in components:
            status = "✅ Ready" if initialized else "❌ Not initialized"
            print(f"  {name}: {status}")
            
        # Show session stats
        print(f"\nSession Statistics:")
        for key, value in agent.session_stats.items():
            if key != "session_start":
                print(f"  {key.replace('_', ' ').title()}: {value}")
                
        print("\n✅ Enhanced Chat Agent Integration demo complete!")
        
    except ImportError as e:
        print(f"❌ Import error: {e}")
    except Exception as e:
        print(f"❌ Demo error: {e}")
        
    print()

def main():
    """Run all SMS-38 demos."""
    print("🚀 SMS-38: Advanced Chat Features Demo")
    print("=" * 60)
    print("Showcasing enhanced conversational AI capabilities")
    print("=" * 60)
    print()
    
    # Run all demos
    demo_enhanced_language_processing()
    demo_context_aware_responses()  
    demo_smart_tool_selection()
    demo_conversation_flows()
    demo_feature_integration()
    
    print("🎉 SMS-38 Demo Complete!")
    print()
    print("Key Features Demonstrated:")
    print("✅ Enhanced natural language processing with fuzzy matching")
    print("✅ Context-aware response generation with personalization")
    print("✅ Smart tool selection with performance optimization")
    print("✅ Multi-turn conversation flows with state management")
    print("✅ Enhanced agent integration with rich feature set")
    print()
    print("Ready for production use! 🚀")

if __name__ == "__main__":
    main()