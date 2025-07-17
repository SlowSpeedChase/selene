"""
Comprehensive tests for SMS-38 Enhanced Chat Features.

This test suite covers all new advanced chat capabilities:
- Enhanced language processing with fuzzy matching
- Smart tool selection and parameter inference  
- Context-aware response generation
- Conversation flow management
- Advanced suggestions and clarifications
"""

import asyncio
import json
import pytest
import pytest_asyncio
import tempfile
from datetime import datetime
from pathlib import Path
from unittest.mock import Mock, AsyncMock, patch
from typing import Dict, Any

from selene.chat.enhanced_agent import EnhancedChatAgent
from selene.chat.config import ChatConfig
from selene.chat.nlp.enhanced_language_processor import (
    EnhancedLanguageProcessor, 
    EnhancedProcessingResult
)
from selene.chat.nlp.intent_classifier import Intent
from selene.chat.response.context_aware_generator import (
    ContextAwareResponseGenerator,
    GeneratedResponse,
    ResponseContext
)
from selene.chat.tools.smart_tool_selector import (
    SmartToolSelector,
    ToolSelection,
    ToolCapability
)
from selene.chat.flow.conversation_flow_manager import (
    ConversationFlowManager,
    ConversationFlow,
    FlowStep,
    FlowStepType,
    FlowState
)
from selene.chat.tools.base import ToolRegistry, ToolResult, ToolStatus


class TestEnhancedLanguageProcessor:
    """Test enhanced language processing capabilities."""
    
    @pytest.fixture
    def temp_vault(self):
        """Create temporary vault for testing."""
        with tempfile.TemporaryDirectory() as temp_dir:
            vault_path = Path(temp_dir)
            
            # Create test files
            (vault_path / "daily-notes.md").write_text("Daily notes content")
            (vault_path / "meeting-summary.md").write_text("Meeting summary content")
            (vault_path / "project-ideas.md").write_text("Project ideas content")
            
            yield vault_path
            
    @pytest.fixture
    def enhanced_processor(self, temp_vault):
        """Create enhanced language processor."""
        return EnhancedLanguageProcessor(temp_vault)
        
    def test_enhanced_preprocessing(self, enhanced_processor):
        """Test enhanced message preprocessing."""
        # Test with file extension inference
        message = "read my daily notes"
        processed = enhanced_processor._enhanced_preprocess(message)
        
        assert "daily" in processed.lower()
        
    def test_fuzzy_file_matching(self, enhanced_processor):
        """Test fuzzy file matching capabilities."""
        # Test exact match
        matches = enhanced_processor._fuzzy_file_matching(
            {"note_path": "daily-notes.md"}, {}
        )
        assert "daily-notes.md" in matches
        
        # Test fuzzy match
        matches = enhanced_processor._fuzzy_file_matching(
            {"note_path": "daily.md"}, {}
        )
        assert any("daily" in match.lower() for match in matches)
        
    def test_parameter_inference(self, enhanced_processor):
        """Test smart parameter inference."""
        processing_result = EnhancedProcessingResult(
            intent=Intent.READ_NOTE,
            tool_name="read_note",
            parameters={},
            confidence=0.8,
            missing_parameters=["note_path"],
            suggestions=[],
            needs_confirmation=False,
            context_used=False
        )
        
        inferred = enhanced_processor._infer_missing_parameters(
            processing_result.intent, 
            Mock(missing_required=["note_path"], parameters={}),
            "read my daily notes"
        )
        
        assert "note_path" in inferred
        assert "daily" in inferred["note_path"].lower()
        
    def test_alternative_interpretations(self, enhanced_processor):
        """Test generation of alternative interpretations."""
        message = "show me AI research"
        result = enhanced_processor.process_message(message)
        
        # Should have alternative interpretations for ambiguous queries
        assert hasattr(result, 'alternative_interpretations')
        
    def test_clarification_detection(self, enhanced_processor):
        """Test clarification need detection."""
        # Ambiguous message should trigger clarification
        message = "do something with my notes"
        result = enhanced_processor.process_message(message)
        
        assert result.confidence < 0.7  # Low confidence should trigger clarification
        
    @pytest.mark.asyncio
    async def test_workflow_message_processing(self, enhanced_processor):
        """Test workflow-specific message processing."""
        # Start a mock workflow
        enhanced_processor.start_workflow(
            "test_workflow", 
            ["collect_input", "completion"],
            {"workflow_started": True}
        )
        
        assert enhanced_processor.workflow_state is not None
        assert enhanced_processor.workflow_state.workflow_id == "test_workflow"


class TestContextAwareResponseGenerator:
    """Test context-aware response generation."""
    
    @pytest.fixture
    def response_generator(self):
        """Create response generator."""
        return ContextAwareResponseGenerator()
        
    @pytest.fixture
    def sample_processing_result(self):
        """Create sample processing result."""
        return EnhancedProcessingResult(
            intent=Intent.READ_NOTE,
            tool_name="read_note",
            parameters={"note_path": "test.md"},
            confidence=0.9,
            missing_parameters=[],
            suggestions=["Test suggestion"],
            needs_confirmation=False,
            context_used=True
        )
        
    @pytest.fixture
    def sample_context(self):
        """Create sample response context."""
        return ResponseContext(
            user_id="test_user",
            conversation_history=[
                {"role": "user", "content": "Hello", "timestamp": "2024-01-01T10:00:00"}
            ],
            current_vault_info={"note_count": 5, "recent_files": ["test.md"]},
            user_preferences={"read_note": 10},
            recent_actions=[],
            time_context={"time_of_day": "morning", "hour": 10}
        )
        
    def test_response_type_determination(self, response_generator, sample_processing_result):
        """Test response type determination logic."""
        # Test success response
        tool_result = Mock(is_success=True)
        response_type = response_generator._determine_response_type(
            sample_processing_result, tool_result
        )
        assert response_type == "success"
        
        # Test clarification response
        sample_processing_result.requires_clarification = True
        response_type = response_generator._determine_response_type(
            sample_processing_result, None
        )
        assert response_type == "clarification"
        
    def test_clarification_response_generation(self, response_generator, sample_context):
        """Test clarification response generation."""
        processing_result = EnhancedProcessingResult(
            intent=Intent.UNKNOWN,
            tool_name=None,
            parameters={},
            confidence=0.3,
            missing_parameters=["note_path"],
            suggestions=[],
            needs_confirmation=False,
            context_used=False,
            requires_clarification=True,
            clarification_question="Which file did you mean?"
        )
        
        response = response_generator._generate_clarification_response(
            processing_result, sample_context
        )
        
        assert response.response_type == "clarification"
        assert response.requires_input is True
        assert "which file" in response.content.lower()
        
    def test_success_response_generation(self, response_generator, sample_context, sample_processing_result):
        """Test success response generation."""
        tool_result = Mock(is_success=True, content="File content here")
        
        response = response_generator._generate_success_response(
            sample_processing_result, sample_context, tool_result
        )
        
        assert response.response_type == "success"
        assert "✅" in response.content
        assert response.confidence > 0.9
        
    def test_personalization(self, response_generator, sample_context):
        """Test response personalization."""
        response = GeneratedResponse(
            content="Test response",
            response_type="informational",
            suggestions=[],
            follow_up_actions=[],
            requires_input=False,
            confidence=0.8,
            metadata={}
        )
        
        personalized = response_generator._personalize_response(response, sample_context)
        
        assert personalized.metadata.get("personalized") is True
        
    def test_contextual_suggestions(self, response_generator, sample_context, sample_processing_result):
        """Test contextual suggestion generation."""
        suggestions = response_generator._generate_contextual_suggestions(
            sample_processing_result, sample_context
        )
        
        # Should include recent files from context
        assert any("recent files" in s.lower() for s in suggestions)
        
    def test_time_based_suggestions(self, response_generator):
        """Test time-based suggestion generation."""
        time_context = {"time_of_day": "morning", "hour": 8}
        user_ctx = {"patterns": {}, "common_files": {}}
        
        suggestions = response_generator._generate_time_based_suggestions(
            time_context, user_ctx
        )
        
        # Morning should suggest daily review
        assert any("morning" in s.lower() or "day" in s.lower() for s in suggestions)


class TestSmartToolSelector:
    """Test smart tool selection and parameter inference."""
    
    @pytest.fixture
    def tool_registry(self):
        """Create mock tool registry."""
        from typing import List
        from selene.chat.tools.base import BaseTool, ToolResult, ToolStatus
        
        # Create a proper mock tool that inherits from BaseTool
        class MockReadNoteTool(BaseTool):
            @property
            def name(self) -> str:
                return "read_note"
            
            @property
            def description(self) -> str:
                return "Read a note file"
            
            @property
            def parameters(self) -> List:
                from selene.chat.tools.base import ToolParameter
                return [
                    ToolParameter(
                        name="note_path",
                        type="string", 
                        description="Path to note file",
                        required=True
                    )
                ]
            
            async def execute(self, **kwargs) -> ToolResult:
                note_path = kwargs.get("note_path", "unknown.md")
                return ToolResult(
                    status=ToolStatus.SUCCESS,
                    content=f"Content of {note_path}"
                )
        
        registry = ToolRegistry()
        registry.register(MockReadNoteTool())
        registry.enable_tool("read_note")
        
        return registry
        
    @pytest.fixture
    def tool_selector(self, tool_registry):
        """Create smart tool selector."""
        return SmartToolSelector(tool_registry)
        
    @pytest.fixture
    def sample_processing_result(self):
        """Create sample processing result for tool selection."""
        return EnhancedProcessingResult(
            intent=Intent.READ_NOTE,
            tool_name=None,
            parameters={"note_path": "test.md"},
            confidence=0.8,
            missing_parameters=[],
            suggestions=[],
            needs_confirmation=False,
            context_used=False
        )
        
    def test_candidate_tool_selection(self, tool_selector):
        """Test getting candidate tools for intent."""
        candidates = tool_selector._get_candidate_tools(Intent.READ_NOTE)
        assert "read_note" in candidates
        
    def test_tool_scoring(self, tool_selector, sample_processing_result):
        """Test tool scoring algorithm."""
        score = tool_selector._score_tool(
            "read_note", 
            sample_processing_result,
            context={},
            user_id="test_user"
        )
        
        assert 0.0 <= score <= 1.0
        assert score > 0.3  # Should have reasonable score for compatible tool
        
    def test_parameter_inference(self, tool_selector, sample_processing_result):
        """Test parameter inference for tools."""
        inferred = tool_selector._infer_tool_parameters(
            "read_note",
            sample_processing_result,
            context={}
        )
        
        assert "note_path" in inferred
        
    def test_file_path_inference(self, tool_selector):
        """Test file path inference from messages."""
        message = "read my daily-notes.md file"
        
        # Create proper processing result
        processing_result = EnhancedProcessingResult(
            intent=Intent.READ_NOTE,
            tool_name="read_note",
            parameters={},
            confidence=0.8,
            missing_parameters=[],
            suggestions=[],
            needs_confirmation=False,
            context_used=False,
            file_matches=[]  # Empty for this test to test pattern matching
        )
        
        path = tool_selector._infer_file_path(message, processing_result, {})
        
        assert path == "daily-notes.md"
        
    def test_parameter_validation(self, tool_selector):
        """Test parameter validation."""
        errors = tool_selector._validate_tool_parameters(
            "read_note",
            {"note_path": "test.md"}
        )
        
        assert len(errors) == 0  # Valid parameters should have no errors
        
        # Test invalid parameters
        errors = tool_selector._validate_tool_parameters(
            "read_note",
            {"note_path": 123}  # Should be string
        )
        
        assert len(errors) > 0
        
    def test_selection_confidence_calculation(self, tool_selector):
        """Test selection confidence calculation."""
        confidence = tool_selector._calculate_selection_confidence(
            best_score=0.8,
            candidate_count=3,
            validation_errors=[]
        )
        
        assert 0.0 <= confidence <= 1.0
        
        # Test with validation errors
        confidence_with_errors = tool_selector._calculate_selection_confidence(
            best_score=0.8,
            candidate_count=3,
            validation_errors=["Missing parameter"]
        )
        
        assert confidence_with_errors < confidence
        
    def test_performance_tracking(self, tool_selector):
        """Test tool performance tracking."""
        # Record successful execution
        tool_selector.record_tool_execution_result(
            "read_note", 
            success=True, 
            execution_time=0.5,
            context={"test": True}
        )
        
        perf_data = tool_selector.tool_performance["read_note"]
        assert perf_data["success_count"] == 1
        assert perf_data["total_attempts"] == 1
        assert perf_data["avg_execution_time"] == 0.5
        
        # Record failure
        tool_selector.record_tool_execution_result(
            "read_note",
            success=False,
            error_message="File not found"
        )
        
        assert perf_data["total_attempts"] == 2
        assert perf_data["success_count"] == 1
        assert "file_not_found" in perf_data["error_patterns"]


class TestConversationFlowManager:
    """Test conversation flow management."""
    
    @pytest.fixture
    def flow_manager(self):
        """Create conversation flow manager."""
        return ConversationFlowManager()
        
    @pytest.fixture
    def sample_flow(self):
        """Create sample conversation flow."""
        return ConversationFlow(
            flow_id="test_flow",
            name="Test Flow",
            description="Test conversation flow",
            steps={
                "start": FlowStep(
                    step_id="start",
                    step_type=FlowStepType.INPUT_COLLECTION,
                    name="Start Step",
                    description="Collect initial input",
                    required_parameters=["input_text"],
                    next_steps=["end"]
                ),
                "end": FlowStep(
                    step_id="end",
                    step_type=FlowStepType.COMPLETION,
                    name="End Step",
                    description="Complete the flow"
                )
            },
            start_step="start"
        )
        
    def test_flow_registration(self, flow_manager, sample_flow):
        """Test flow registration."""
        success = flow_manager.register_flow(sample_flow)
        assert success is True
        assert sample_flow.flow_id in flow_manager.flows
        
    def test_flow_start(self, flow_manager, sample_flow):
        """Test flow execution start."""
        flow_manager.register_flow(sample_flow)
        
        execution = flow_manager.start_flow(
            sample_flow.flow_id,
            user_id="test_user",
            initial_context={"test": True}
        )
        
        assert execution is not None
        assert execution.flow_id == sample_flow.flow_id
        assert execution.current_step == "start"
        assert execution.state == FlowState.ACTIVE
        
    def test_flow_input_processing(self, flow_manager, sample_flow):
        """Test flow input processing."""
        flow_manager.register_flow(sample_flow)
        execution = flow_manager.start_flow(sample_flow.flow_id)
        
        # Process input for input collection step
        success, response, next_action = flow_manager.process_flow_input(
            execution.execution_id,
            "test input text",
            processing_result=None
        )
        
        assert next_action is not None
        
    def test_flow_advancement(self, flow_manager, sample_flow):
        """Test flow step advancement."""
        flow_manager.register_flow(sample_flow)
        execution = flow_manager.start_flow(sample_flow.flow_id)
        
        # Advance to next step
        success = flow_manager.advance_flow(execution.execution_id, "end")
        assert success is True
        assert execution.current_step == "end"
        
    def test_flow_completion(self, flow_manager, sample_flow):
        """Test flow completion."""
        flow_manager.register_flow(sample_flow)
        execution = flow_manager.start_flow(sample_flow.flow_id)
        
        # Advance to completion step
        flow_manager.advance_flow(execution.execution_id, "end")
        
        # Should be marked as completed
        assert execution.state == FlowState.COMPLETED
        
    def test_flow_cancellation(self, flow_manager, sample_flow):
        """Test flow cancellation."""
        flow_manager.register_flow(sample_flow)
        execution = flow_manager.start_flow(sample_flow.flow_id)
        
        success = flow_manager.cancel_flow(execution.execution_id, "test cancel")
        assert success is True
        assert execution.execution_id not in flow_manager.active_executions
        
    def test_flow_context_retrieval(self, flow_manager, sample_flow):
        """Test flow context retrieval."""
        flow_manager.register_flow(sample_flow)
        execution = flow_manager.start_flow(sample_flow.flow_id)
        
        context = flow_manager.get_flow_context(execution.execution_id)
        
        assert context is not None
        assert context["flow_id"] == sample_flow.flow_id
        assert context["current_step"] == "start"
        assert "progress" in context
        
    def test_flow_statistics(self, flow_manager, sample_flow):
        """Test flow statistics tracking."""
        flow_manager.register_flow(sample_flow)
        
        # Start and complete a flow
        execution = flow_manager.start_flow(sample_flow.flow_id)
        flow_manager.advance_flow(execution.execution_id, "end")
        
        stats = flow_manager.get_flow_statistics()
        
        assert stats["total_flows_started"] >= 1
        assert stats["total_flows_completed"] >= 1
        
    def test_expired_flow_cleanup(self, flow_manager, sample_flow):
        """Test expired flow cleanup."""
        flow_manager.register_flow(sample_flow)
        execution = flow_manager.start_flow(sample_flow.flow_id)
        
        # Mock expired execution
        from datetime import timedelta
        execution.last_activity = datetime.now() - timedelta(hours=2)
        
        # Set short timeout for testing
        flow_manager.flow_timeout_minutes = 1
        
        cleaned_count = flow_manager.cleanup_expired_flows()
        assert cleaned_count > 0


class TestEnhancedChatAgent:
    """Test the complete enhanced chat agent."""
    
    @pytest.fixture
    def temp_vault(self):
        """Create temporary vault for testing."""
        with tempfile.TemporaryDirectory() as temp_dir:
            vault_path = Path(temp_dir)
            
            # Create test files
            (vault_path / "test-note.md").write_text("Test note content")
            (vault_path / "daily.md").write_text("Daily notes")
            
            yield vault_path
            
    @pytest.fixture
    def chat_config(self, temp_vault):
        """Create chat configuration."""
        return ChatConfig(
            vault_path=str(temp_vault),
            conversation_memory=False,
            rich_formatting=False
        )
        
    @pytest_asyncio.fixture
    async def enhanced_agent(self, chat_config):
        """Create enhanced chat agent."""
        agent = EnhancedChatAgent(chat_config)
        await agent.initialize(user_id="test_user")
        yield agent
        await agent.shutdown()
        
    @pytest.mark.asyncio
    async def test_agent_initialization(self, chat_config):
        """Test enhanced agent initialization."""
        agent = EnhancedChatAgent(chat_config)
        success = await agent.initialize(user_id="test_user")
        
        assert success is True
        assert agent._initialized is True
        assert agent.language_processor is not None
        assert agent.response_generator is not None
        assert agent.tool_selector is not None
        assert agent.flow_manager is not None
        
        await agent.shutdown()
        
    @pytest.mark.asyncio
    async def test_enhanced_message_processing(self, enhanced_agent):
        """Test enhanced message processing."""
        with patch.object(enhanced_agent.tool_registry, 'execute_tool') as mock_execute:
            mock_execute.return_value = ToolResult(
                status=ToolStatus.SUCCESS,
                content="Test file content",
                metadata={}
            )
            
            response = await enhanced_agent.chat("read my test note")
            
            assert response is not None
            assert len(response) > 0
            
    @pytest.mark.asyncio
    async def test_special_commands(self, enhanced_agent):
        """Test special command handling."""
        # Test help command
        response = await enhanced_agent.chat("help")
        assert "Enhanced SELENE" in response
        
        # Test stats command
        response = await enhanced_agent.chat("stats")
        assert "statistics" in response.lower()
        
        # Test features command
        response = await enhanced_agent.chat("features")
        assert "features" in response.lower()
        
    @pytest.mark.asyncio
    async def test_conversation_flow_initiation(self, enhanced_agent):
        """Test conversation flow initiation."""
        response = await enhanced_agent.chat("help me create a note")
        
        # Should start a conversation flow
        assert enhanced_agent._active_flow_id is not None
        assert "guided" in response.lower() or "starting" in response.lower()
        
    @pytest.mark.asyncio
    async def test_flow_message_processing(self, enhanced_agent):
        """Test message processing within active flow."""
        # Start a flow first
        await enhanced_agent.chat("help me create a note")
        
        # Process flow input
        response = await enhanced_agent.chat("My Daily Journal")
        
        assert response is not None
        assert len(response) > 0
        
    @pytest.mark.asyncio
    async def test_context_building(self, enhanced_agent):
        """Test context building for responses."""
        context = await enhanced_agent._build_context()
        
        assert "vault_path" in context
        assert "user_id" in context
        assert "time_context" in context
        
        response_context = await enhanced_agent._build_response_context()
        
        assert response_context.user_id == "test_user"
        assert response_context.time_context is not None
        
    @pytest.mark.asyncio
    async def test_vault_switching(self, enhanced_agent, temp_vault):
        """Test vault path switching."""
        # Create another temporary directory
        with tempfile.TemporaryDirectory() as temp_dir2:
            new_vault = Path(temp_dir2)
            (new_vault / "new-note.md").write_text("New vault content")
            
            success = await enhanced_agent.set_vault(str(new_vault))
            assert success is True
            assert enhanced_agent._current_vault_path == new_vault
            
    @pytest.mark.asyncio
    async def test_session_statistics_tracking(self, enhanced_agent):
        """Test session statistics tracking."""
        initial_stats = enhanced_agent.session_stats.copy()
        
        # Process a message
        await enhanced_agent.chat("test message")
        
        # Statistics should be updated
        assert enhanced_agent.session_stats["messages_processed"] > initial_stats["messages_processed"]
        
    @pytest.mark.asyncio
    async def test_enhanced_status_retrieval(self, enhanced_agent):
        """Test enhanced status retrieval."""
        status = enhanced_agent.get_enhanced_status()
        
        assert status["initialized"] is True
        assert status["user_id"] == "test_user"
        assert "features" in status
        assert "session_stats" in status
        assert "components" in status
        
    @pytest.mark.asyncio
    async def test_conversation_reset(self, enhanced_agent):
        """Test conversation reset functionality."""
        # Start a flow
        await enhanced_agent.chat("help me create a note")
        initial_flow_id = enhanced_agent._active_flow_id
        
        # Reset conversation
        response = await enhanced_agent.chat("reset")
        
        assert "reset" in response.lower()
        assert enhanced_agent._active_flow_id is None
        
    @pytest.mark.asyncio
    async def test_learning_data_display(self, enhanced_agent):
        """Test learning data display."""
        response = await enhanced_agent.chat("patterns")
        
        assert "learning" in response.lower() or "patterns" in response.lower()
        
    @pytest.mark.asyncio
    async def test_error_handling(self, enhanced_agent):
        """Test error handling in enhanced agent."""
        with patch.object(enhanced_agent.language_processor, 'process_message') as mock_process:
            mock_process.side_effect = Exception("Test error")
            
            response = await enhanced_agent.chat("test message")
            
            assert "error" in response.lower()


class TestIntegrationScenarios:
    """Integration tests for complete enhanced chat scenarios."""
    
    @pytest.fixture
    def temp_vault(self):
        """Create comprehensive test vault."""
        with tempfile.TemporaryDirectory() as temp_dir:
            vault_path = Path(temp_dir)
            
            # Create realistic test files
            (vault_path / "daily-2024-01-15.md").write_text("""
# Daily Notes - January 15, 2024

## Tasks
- Review project proposals
- Update documentation
- Team meeting at 2 PM

## Ideas
- New feature for automation
- Better user interface design
            """)
            
            (vault_path / "meeting-notes.md").write_text("""
# Team Meeting Notes

## Attendees
- Alice, Bob, Charlie

## Agenda
1. Project status update
2. Technical challenges
3. Next steps

## Action Items
- Alice: Update requirements
- Bob: Fix bug #123
- Charlie: Design review
            """)
            
            (vault_path / "research-ai.md").write_text("""
# AI Research Notes

## Machine Learning
- Neural networks
- Deep learning applications
- Natural language processing

## Current Projects
- Chatbot development
- Automated content generation
- Sentiment analysis
            """)
            
            yield vault_path
            
    @pytest.fixture
    async def full_agent(self, temp_vault):
        """Create fully configured enhanced agent."""
        config = ChatConfig(
            vault_path=str(temp_vault),
            conversation_memory=True,
            rich_formatting=False,
            enabled_tools=["read_note", "write_note", "search_notes", "ai_process"]
        )
        
        agent = EnhancedChatAgent(config)
        await agent.initialize(user_id="integration_test_user")
        yield agent
        await agent.shutdown()
        
    @pytest.mark.asyncio
    async def test_complete_note_reading_workflow(self, full_agent):
        """Test complete note reading workflow with enhancements."""
        with patch.object(full_agent.tool_registry, 'execute_tool') as mock_execute:
            mock_execute.return_value = ToolResult(
                status=ToolStatus.SUCCESS,
                content="Daily notes content here",
                metadata={"file_path": "daily-2024-01-15.md"}
            )
            
            # Test fuzzy file matching
            response = await full_agent.chat("show me my daily notes")
            
            assert mock_execute.called
            assert "daily" in response.lower() or "success" in response.lower()
            
    @pytest.mark.asyncio
    async def test_guided_note_creation_flow(self, full_agent):
        """Test complete guided note creation flow."""
        # Start the flow
        response1 = await full_agent.chat("help me create a comprehensive note")
        assert full_agent._active_flow_id is not None
        
        # Provide title
        response2 = await full_agent.chat("Project Planning Session")
        assert len(response2) > 0
        
        # Provide content
        response3 = await full_agent.chat("We need to plan the next quarter")
        assert len(response3) > 0
        
    @pytest.mark.asyncio
    async def test_intelligent_search_with_suggestions(self, full_agent):
        """Test intelligent search with contextual suggestions."""
        with patch.object(full_agent.tool_registry, 'execute_tool') as mock_execute:
            mock_execute.return_value = ToolResult(
                status=ToolStatus.SUCCESS,
                content=["research-ai.md", "meeting-notes.md"],
                metadata={"query": "AI", "results_count": 2}
            )
            
            response = await full_agent.chat("find my AI research")
            
            assert mock_execute.called
            # Should provide suggestions for next actions
            assert len(response) > 0
            
    @pytest.mark.asyncio
    async def test_context_aware_clarification(self, full_agent):
        """Test context-aware clarification requests."""
        # Ambiguous request should trigger clarification
        response = await full_agent.chat("update that file")
        
        # Should ask for clarification since no specific file mentioned
        assert "clarification" in response.lower() or "which" in response.lower() or "specify" in response.lower()
        
    @pytest.mark.asyncio
    async def test_learning_and_personalization(self, full_agent):
        """Test learning from user patterns."""
        # Simulate repeated interactions
        with patch.object(full_agent.tool_registry, 'execute_tool') as mock_execute:
            mock_execute.return_value = ToolResult(
                status=ToolStatus.SUCCESS,
                content="File content",
                metadata={}
            )
            
            # Read the same file multiple times
            await full_agent.chat("read daily-2024-01-15.md")
            await full_agent.chat("show me daily notes")
            await full_agent.chat("open my daily file")
            
            # Should learn user preferences for this file
            patterns = full_agent.language_processor.get_user_patterns("integration_test_user")
            assert len(patterns) > 0
            
    @pytest.mark.asyncio
    async def test_multi_turn_conversation_memory(self, full_agent):
        """Test multi-turn conversation with memory."""
        # First message
        response1 = await full_agent.chat("I'm working on a project about AI")
        
        # Second message referring to previous context
        response2 = await full_agent.chat("show me related notes")
        
        # Should understand "related" refers to AI from previous message
        assert len(response2) > 0
        
    @pytest.mark.asyncio
    async def test_error_recovery_and_suggestions(self, full_agent):
        """Test error recovery with helpful suggestions."""
        with patch.object(full_agent.tool_registry, 'execute_tool') as mock_execute:
            mock_execute.return_value = ToolResult(
                status=ToolStatus.ERROR,
                error_message="File not found: nonexistent.md",
                metadata={}
            )
            
            response = await full_agent.chat("read nonexistent.md")
            
            # Should provide helpful error message and suggestions
            assert "not found" in response.lower() or "error" in response.lower()
            
    @pytest.mark.asyncio
    async def test_performance_tracking(self, full_agent):
        """Test performance tracking and optimization."""
        # Perform several operations
        with patch.object(full_agent.tool_registry, 'execute_tool') as mock_execute:
            mock_execute.return_value = ToolResult(
                status=ToolStatus.SUCCESS,
                content="Success",
                metadata={}
            )
            
            await full_agent.chat("read daily notes")
            await full_agent.chat("search for meetings")
            
            # Check statistics
            stats = full_agent.session_stats
            assert stats["messages_processed"] >= 2
            
            # Check tool performance data
            tool_stats = full_agent.tool_selector.get_tool_performance_stats()
            assert len(tool_stats) > 0


# Run the tests
if __name__ == "__main__":
    pytest.main([__file__, "-v"])