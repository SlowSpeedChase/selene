"""
Conversation Flow Manager for SMS-38 Advanced Chat Features.

This module manages complex multi-turn conversations and workflows:
- Multi-step conversation workflows with state management
- Dynamic conversation branching and decision trees
- Context-aware conversation continuation
- Workflow templates for common interaction patterns
- Conversation memory and state persistence
"""

import json
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Callable
from collections import defaultdict, deque

from loguru import logger

from ..nlp.enhanced_language_processor import EnhancedProcessingResult
from ..nlp.intent_classifier import Intent
from ..response.context_aware_generator import GeneratedResponse, ResponseContext


class FlowState(Enum):
    """Conversation flow states."""
    IDLE = "idle"
    ACTIVE = "active"
    WAITING_INPUT = "waiting_input"
    WAITING_CONFIRMATION = "waiting_confirmation"
    EXECUTING = "executing"
    COMPLETED = "completed"
    ERROR = "error"
    PAUSED = "paused"


class FlowStepType(Enum):
    """Types of flow steps."""
    INPUT_COLLECTION = "input_collection"
    CONFIRMATION = "confirmation"
    TOOL_EXECUTION = "tool_execution"
    DECISION_POINT = "decision_point"
    INFORMATION_DISPLAY = "information_display"
    BRANCHING = "branching"
    LOOP = "loop"
    COMPLETION = "completion"


@dataclass
class FlowStep:
    """A single step in a conversation flow."""
    step_id: str
    step_type: FlowStepType
    name: str
    description: str
    required_parameters: List[str] = field(default_factory=list)
    optional_parameters: List[str] = field(default_factory=list)
    validation_rules: Dict[str, Any] = field(default_factory=dict)
    next_steps: List[str] = field(default_factory=list)
    branching_logic: Optional[Callable] = None
    timeout_seconds: Optional[int] = None
    retry_count: int = 0
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ConversationFlow:
    """A complete conversation flow definition."""
    flow_id: str
    name: str
    description: str
    steps: Dict[str, FlowStep]
    start_step: str
    context_requirements: List[str] = field(default_factory=list)
    max_duration_minutes: int = 30
    auto_save: bool = True
    priority: int = 1
    tags: List[str] = field(default_factory=list)


@dataclass
class FlowExecution:
    """State of an active flow execution."""
    execution_id: str
    flow_id: str
    user_id: Optional[str]
    current_step: str
    state: FlowState
    collected_data: Dict[str, Any] = field(default_factory=dict)
    step_history: List[Dict[str, Any]] = field(default_factory=list)
    started_at: datetime = field(default_factory=datetime.now)
    last_activity: datetime = field(default_factory=datetime.now)
    error_count: int = 0
    retry_count: int = 0
    metadata: Dict[str, Any] = field(default_factory=dict)


class ConversationFlowManager:
    """
    Manages complex multi-turn conversation flows.
    
    Features:
    - Template-based flow definitions
    - Dynamic step progression with branching
    - State persistence and recovery
    - Timeout and error handling
    - Context-aware flow selection
    - Flow performance analytics
    """
    
    def __init__(self, vault_path: Optional[Path] = None):
        """
        Initialize conversation flow manager.
        
        Args:
            vault_path: Current vault path for context
        """
        self.vault_path = vault_path
        
        # Flow definitions and executions
        self.flows: Dict[str, ConversationFlow] = {}
        self.active_executions: Dict[str, FlowExecution] = {}  # execution_id -> execution
        self.user_executions: Dict[str, List[str]] = defaultdict(list)  # user_id -> execution_ids
        
        # Flow templates
        self.flow_templates = self._initialize_flow_templates()
        
        # Analytics and statistics
        self.flow_stats = {
            "total_flows_started": 0,
            "total_flows_completed": 0,
            "total_flows_abandoned": 0,
            "average_completion_time": 0.0,
            "common_abandonment_steps": defaultdict(int),
            "flow_success_rates": defaultdict(lambda: {"started": 0, "completed": 0})
        }
        
        # Configuration
        self.max_concurrent_flows_per_user = 3
        self.flow_timeout_minutes = 30
        self.auto_cleanup_enabled = True
        
    def start_flow(
        self, 
        flow_id: str, 
        user_id: Optional[str] = None,
        initial_context: Dict[str, Any] = None
    ) -> Optional[FlowExecution]:
        """
        Start a new conversation flow.
        
        Args:
            flow_id: ID of the flow to start
            user_id: Optional user identifier
            initial_context: Initial context data
            
        Returns:
            Flow execution if started successfully, None otherwise
        """
        try:
            # Check if flow exists
            if flow_id not in self.flows:
                logger.error(f"Flow not found: {flow_id}")
                return None
                
            flow = self.flows[flow_id]
            
            # Check user flow limits
            if user_id and len(self.user_executions[user_id]) >= self.max_concurrent_flows_per_user:
                logger.warning(f"User {user_id} has reached max concurrent flows")
                return None
                
            # Create execution
            execution_id = str(uuid.uuid4())
            execution = FlowExecution(
                execution_id=execution_id,
                flow_id=flow_id,
                user_id=user_id,
                current_step=flow.start_step,
                state=FlowState.ACTIVE,
                collected_data=initial_context or {},
                metadata={"flow_name": flow.name}
            )
            
            # Store execution
            self.active_executions[execution_id] = execution
            if user_id:
                self.user_executions[user_id].append(execution_id)
                
            # Update statistics
            self.flow_stats["total_flows_started"] += 1
            self.flow_stats["flow_success_rates"][flow_id]["started"] += 1
            
            logger.info(f"Started flow {flow_id} with execution {execution_id}")
            
            return execution
            
        except Exception as e:
            logger.error(f"Failed to start flow {flow_id}: {e}")
            return None
            
    def process_flow_input(
        self, 
        execution_id: str, 
        user_input: str,
        processing_result: Optional[EnhancedProcessingResult] = None
    ) -> Tuple[bool, Optional[GeneratedResponse], Optional[str]]:
        """
        Process user input within an active flow.
        
        Args:
            execution_id: Flow execution ID
            user_input: User's input message
            processing_result: Optional processing result
            
        Returns:
            Tuple of (success, response, next_action)
        """
        try:
            # Get execution
            execution = self.active_executions.get(execution_id)
            if not execution:
                return False, None, "execution_not_found"
                
            # Get flow and current step
            flow = self.flows.get(execution.flow_id)
            if not flow:
                return False, None, "flow_not_found"
                
            current_step = flow.steps.get(execution.current_step)
            if not current_step:
                return False, None, "step_not_found"
                
            # Update last activity
            execution.last_activity = datetime.now()
            
            # Process step based on type
            if current_step.step_type == FlowStepType.INPUT_COLLECTION:
                success, response, next_action = self._process_input_collection_step(
                    execution, current_step, user_input, processing_result
                )
            elif current_step.step_type == FlowStepType.CONFIRMATION:
                success, response, next_action = self._process_confirmation_step(
                    execution, current_step, user_input
                )
            elif current_step.step_type == FlowStepType.DECISION_POINT:
                success, response, next_action = self._process_decision_step(
                    execution, current_step, user_input, processing_result
                )
            else:
                success, response, next_action = self._process_generic_step(
                    execution, current_step, user_input
                )
                
            # Update step history
            execution.step_history.append({
                "step_id": current_step.step_id,
                "timestamp": datetime.now().isoformat(),
                "user_input": user_input,
                "success": success,
                "next_action": next_action
            })
            
            return success, response, next_action
            
        except Exception as e:
            logger.error(f"Error processing flow input: {e}")
            return False, None, f"error: {e}"
            
    def advance_flow(self, execution_id: str, next_step_id: Optional[str] = None) -> bool:
        """
        Advance flow to the next step.
        
        Args:
            execution_id: Flow execution ID
            next_step_id: Optional specific next step ID
            
        Returns:
            True if advanced successfully
        """
        try:
            execution = self.active_executions.get(execution_id)
            if not execution:
                return False
                
            flow = self.flows.get(execution.flow_id)
            if not flow:
                return False
                
            current_step = flow.steps.get(execution.current_step)
            if not current_step:
                return False
                
            # Determine next step
            if next_step_id:
                next_step = next_step_id
            elif len(current_step.next_steps) == 1:
                next_step = current_step.next_steps[0]
            elif current_step.branching_logic:
                next_step = current_step.branching_logic(execution)
            else:
                # Multiple next steps without branching logic - need user choice
                execution.state = FlowState.WAITING_INPUT
                return True
                
            # Validate next step exists
            if next_step not in flow.steps:
                logger.error(f"Next step not found: {next_step}")
                execution.state = FlowState.ERROR
                return False
                
            # Update execution
            execution.current_step = next_step
            execution.last_activity = datetime.now()
            
            # Check if this is completion step
            next_step_obj = flow.steps[next_step]
            if next_step_obj.step_type == FlowStepType.COMPLETION:
                execution.state = FlowState.COMPLETED
                self._complete_flow(execution)
            else:
                execution.state = FlowState.ACTIVE
                
            logger.debug(f"Advanced flow {execution.flow_id} to step {next_step}")
            return True
            
        except Exception as e:
            logger.error(f"Error advancing flow: {e}")
            return False
            
    def pause_flow(self, execution_id: str) -> bool:
        """Pause an active flow."""
        execution = self.active_executions.get(execution_id)
        if execution and execution.state == FlowState.ACTIVE:
            execution.state = FlowState.PAUSED
            logger.info(f"Paused flow execution {execution_id}")
            return True
        return False
        
    def resume_flow(self, execution_id: str) -> bool:
        """Resume a paused flow."""
        execution = self.active_executions.get(execution_id)
        if execution and execution.state == FlowState.PAUSED:
            execution.state = FlowState.ACTIVE
            execution.last_activity = datetime.now()
            logger.info(f"Resumed flow execution {execution_id}")
            return True
        return False
        
    def cancel_flow(self, execution_id: str, reason: str = "user_cancelled") -> bool:
        """Cancel an active flow."""
        try:
            execution = self.active_executions.get(execution_id)
            if not execution:
                return False
                
            # Update statistics
            self.flow_stats["total_flows_abandoned"] += 1
            self.flow_stats["common_abandonment_steps"][execution.current_step] += 1
            
            # Remove from active executions
            del self.active_executions[execution_id]
            
            # Remove from user executions
            if execution.user_id and execution_id in self.user_executions[execution.user_id]:
                self.user_executions[execution.user_id].remove(execution_id)
                
            logger.info(f"Cancelled flow execution {execution_id}: {reason}")
            return True
            
        except Exception as e:
            logger.error(f"Error cancelling flow: {e}")
            return False
            
    def get_flow_context(self, execution_id: str) -> Optional[Dict[str, Any]]:
        """Get current context for a flow execution."""
        execution = self.active_executions.get(execution_id)
        if not execution:
            return None
            
        flow = self.flows.get(execution.flow_id)
        current_step = flow.steps.get(execution.current_step) if flow else None
        
        return {
            "execution_id": execution_id,
            "flow_id": execution.flow_id,
            "flow_name": execution.metadata.get("flow_name", "Unknown"),
            "current_step": execution.current_step,
            "step_name": current_step.name if current_step else "Unknown",
            "state": execution.state.value,
            "collected_data": execution.collected_data,
            "progress": self._calculate_flow_progress(execution),
            "started_at": execution.started_at.isoformat(),
            "duration_minutes": (datetime.now() - execution.started_at).total_seconds() / 60
        }
        
    def _process_input_collection_step(
        self, 
        execution: FlowExecution,
        step: FlowStep, 
        user_input: str,
        processing_result: Optional[EnhancedProcessingResult]
    ) -> Tuple[bool, Optional[GeneratedResponse], Optional[str]]:
        """Process input collection step."""
        
        # Extract data from user input or processing result
        collected_data = {}
        
        if processing_result:
            # Use parameters from processing result
            collected_data.update(processing_result.parameters)
            collected_data.update(processing_result.inferred_parameters)
            
        # Extract data from raw input for missing parameters
        for param in step.required_parameters:
            if param not in collected_data:
                extracted_value = self._extract_parameter_from_input(param, user_input)
                if extracted_value:
                    collected_data[param] = extracted_value
                    
        # Validate collected data
        validation_errors = self._validate_step_data(step, collected_data)
        
        if validation_errors:
            # Request missing information
            missing_params = [error for error in validation_errors if "missing" in error.lower()]
            response_content = f"I need more information:\n\n"
            for error in missing_params:
                response_content += f"• {error}\n"
                
            response = GeneratedResponse(
                content=response_content,
                response_type="clarification",
                suggestions=self._generate_step_suggestions(step, collected_data),
                follow_up_actions=[],
                requires_input=True,
                confidence=0.7,
                metadata={"step_type": "input_collection", "validation_errors": validation_errors}
            )
            
            return False, response, "request_clarification"
            
        # Store collected data
        execution.collected_data.update(collected_data)
        execution.state = FlowState.ACTIVE
        
        # Generate success response
        response = GeneratedResponse(
            content=f"✅ Got it! I've collected the information for {step.name}.",
            response_type="success",
            suggestions=[],
            follow_up_actions=[],
            requires_input=False,
            confidence=0.9,
            metadata={"step_type": "input_collection", "collected": list(collected_data.keys())}
        )
        
        return True, response, "advance_step"
        
    def _process_confirmation_step(
        self, 
        execution: FlowExecution,
        step: FlowStep,
        user_input: str
    ) -> Tuple[bool, Optional[GeneratedResponse], Optional[str]]:
        """Process confirmation step."""
        
        user_input_lower = user_input.lower().strip()
        
        # Check for positive confirmation
        positive_responses = ["yes", "y", "ok", "okay", "confirm", "proceed", "continue", "sure"]
        negative_responses = ["no", "n", "cancel", "stop", "abort", "nevermind", "nope"]
        
        if any(pos in user_input_lower for pos in positive_responses):
            execution.collected_data["confirmed"] = True
            response = GeneratedResponse(
                content="✅ Confirmed! Proceeding with the action.",
                response_type="success",
                suggestions=[],
                follow_up_actions=[],
                requires_input=False,
                confidence=0.95,
                metadata={"step_type": "confirmation", "confirmed": True}
            )
            return True, response, "advance_step"
            
        elif any(neg in user_input_lower for neg in negative_responses):
            execution.collected_data["confirmed"] = False
            response = GeneratedResponse(
                content="❌ Action cancelled. How else can I help you?",
                response_type="informational",
                suggestions=["Start a new task", "Ask a question", "List available commands"],
                follow_up_actions=[],
                requires_input=True,
                confidence=0.95,
                metadata={"step_type": "confirmation", "confirmed": False}
            )
            return True, response, "cancel_flow"
            
        else:
            # Unclear response - request clarification
            response = GeneratedResponse(
                content="I need a clear confirmation. Please respond with 'yes' to proceed or 'no' to cancel.",
                response_type="clarification",
                suggestions=["yes", "no", "cancel"],
                follow_up_actions=[],
                requires_input=True,
                confidence=0.8,
                metadata={"step_type": "confirmation", "unclear_response": True}
            )
            return False, response, "request_clarification"
            
    def _process_decision_step(
        self, 
        execution: FlowExecution,
        step: FlowStep,
        user_input: str,
        processing_result: Optional[EnhancedProcessingResult]
    ) -> Tuple[bool, Optional[GeneratedResponse], Optional[str]]:
        """Process decision point step."""
        
        # Use branching logic if available
        if step.branching_logic:
            try:
                next_step = step.branching_logic(execution)
                if next_step:
                    response = GeneratedResponse(
                        content=f"Based on your input, I'll proceed with {next_step}.",
                        response_type="informational",
                        suggestions=[],
                        follow_up_actions=[],
                        requires_input=False,
                        confidence=0.8,
                        metadata={"step_type": "decision", "next_step": next_step}
                    )
                    return True, response, f"advance_to:{next_step}"
            except Exception as e:
                logger.error(f"Branching logic failed: {e}")
                
        # Fallback: present options to user
        if step.next_steps:
            options_text = "\n".join([f"{i+1}. {step_id}" for i, step_id in enumerate(step.next_steps)])
            response = GeneratedResponse(
                content=f"Please choose an option:\n\n{options_text}",
                response_type="clarification",
                suggestions=[f"Option {i+1}" for i in range(len(step.next_steps))],
                follow_up_actions=[],
                requires_input=True,
                confidence=0.9,
                metadata={"step_type": "decision", "options": step.next_steps}
            )
            return False, response, "request_choice"
            
        # No next steps defined
        execution.state = FlowState.ERROR
        response = GeneratedResponse(
            content="❌ Flow configuration error: no next steps defined.",
            response_type="error",
            suggestions=["Cancel flow", "Contact support"],
            follow_up_actions=[],
            requires_input=False,
            confidence=0.1,
            metadata={"step_type": "decision", "error": "no_next_steps"}
        )
        return False, response, "flow_error"
        
    def _process_generic_step(
        self, 
        execution: FlowExecution,
        step: FlowStep,
        user_input: str
    ) -> Tuple[bool, Optional[GeneratedResponse], Optional[str]]:
        """Process generic step types."""
        
        response = GeneratedResponse(
            content=f"Processing step: {step.name}",
            response_type="informational",
            suggestions=[],
            follow_up_actions=[],
            requires_input=False,
            confidence=0.8,
            metadata={"step_type": step.step_type.value}
        )
        
        return True, response, "advance_step"
        
    def _extract_parameter_from_input(self, param_name: str, user_input: str) -> Optional[Any]:
        """Extract parameter value from user input."""
        
        # Simple pattern matching for common parameters
        if param_name in ["note_path", "file_path", "filename"]:
            # Look for file patterns
            patterns = [
                r'\b([\w\-_]+\.md)\b',
                r'["\']([^"\']+\.md)["\']',
                r'called\s+["\']?([^"\']+)["\']?'
            ]
            for pattern in patterns:
                match = re.search(pattern, user_input, re.IGNORECASE)
                if match:
                    filename = match.group(1)
                    if not filename.endswith('.md'):
                        filename += '.md'
                    return filename
                    
        elif param_name == "content":
            # Look for quoted content
            quoted = re.findall(r'["\']([^"\']{10,})["\']', user_input)
            if quoted:
                return quoted[0]
                
        elif param_name == "query":
            # Extract search terms
            query_patterns = [
                r'(?:search|find|look for)\s+(.+)',
                r'about\s+(.+)',
                r'containing\s+(.+)'
            ]
            for pattern in query_patterns:
                match = re.search(pattern, user_input, re.IGNORECASE)
                if match:
                    return match.group(1).strip()
                    
        return None
        
    def _validate_step_data(self, step: FlowStep, data: Dict[str, Any]) -> List[str]:
        """Validate collected data against step requirements."""
        
        errors = []
        
        # Check required parameters
        for param in step.required_parameters:
            if param not in data or not data[param]:
                errors.append(f"Missing required parameter: {param}")
                
        # Apply validation rules
        for param, rules in step.validation_rules.items():
            if param in data:
                value = data[param]
                
                # Type validation
                if "type" in rules:
                    expected_type = rules["type"]
                    if not isinstance(value, expected_type):
                        errors.append(f"{param} must be {expected_type.__name__}")
                        
                # Length validation
                if "min_length" in rules and isinstance(value, str):
                    if len(value) < rules["min_length"]:
                        errors.append(f"{param} must be at least {rules['min_length']} characters")
                        
                if "max_length" in rules and isinstance(value, str):
                    if len(value) > rules["max_length"]:
                        errors.append(f"{param} must be at most {rules['max_length']} characters")
                        
                # Pattern validation
                if "pattern" in rules and isinstance(value, str):
                    if not re.match(rules["pattern"], value):
                        errors.append(f"{param} format is invalid")
                        
        return errors
        
    def _generate_step_suggestions(self, step: FlowStep, current_data: Dict[str, Any]) -> List[str]:
        """Generate helpful suggestions for the current step."""
        
        suggestions = []
        
        # Parameter-specific suggestions
        missing_required = [p for p in step.required_parameters if p not in current_data]
        
        for param in missing_required:
            if param in ["note_path", "file_path"]:
                suggestions.append("Specify a filename like 'daily-notes.md'")
            elif param == "content":
                suggestions.append("Provide the content in quotes")
            elif param == "query":
                suggestions.append("Tell me what to search for")
                
        # Generic suggestions
        if not suggestions:
            suggestions.extend([
                "Try being more specific",
                "Use quotes for exact text",
                "Ask for help if unsure"
            ])
            
        return suggestions
        
    def _calculate_flow_progress(self, execution: FlowExecution) -> float:
        """Calculate progress percentage of flow execution."""
        
        flow = self.flows.get(execution.flow_id)
        if not flow:
            return 0.0
            
        total_steps = len(flow.steps)
        if total_steps == 0:
            return 0.0
            
        # Simple linear progress based on step position
        step_positions = {step_id: i for i, step_id in enumerate(flow.steps.keys())}
        current_position = step_positions.get(execution.current_step, 0)
        
        return (current_position + 1) / total_steps
        
    def _complete_flow(self, execution: FlowExecution) -> None:
        """Complete a flow execution."""
        
        try:
            # Calculate completion time
            completion_time = (datetime.now() - execution.started_at).total_seconds() / 60
            
            # Update statistics
            self.flow_stats["total_flows_completed"] += 1
            self.flow_stats["flow_success_rates"][execution.flow_id]["completed"] += 1
            
            # Update average completion time
            total_completed = self.flow_stats["total_flows_completed"]
            current_avg = self.flow_stats["average_completion_time"]
            self.flow_stats["average_completion_time"] = (
                (current_avg * (total_completed - 1) + completion_time) / total_completed
            )
            
            # Remove from active executions
            if execution.execution_id in self.active_executions:
                del self.active_executions[execution.execution_id]
                
            # Remove from user executions
            if execution.user_id and execution.execution_id in self.user_executions[execution.user_id]:
                self.user_executions[execution.user_id].remove(execution.execution_id)
                
            logger.info(f"Completed flow {execution.flow_id} in {completion_time:.1f} minutes")
            
        except Exception as e:
            logger.error(f"Error completing flow: {e}")
            
    def _initialize_flow_templates(self) -> Dict[str, ConversationFlow]:
        """Initialize built-in flow templates."""
        
        templates = {}
        
        # Note Creation Flow
        note_creation_flow = ConversationFlow(
            flow_id="create_note_flow",
            name="Create Note",
            description="Guided note creation with AI enhancement",
            steps={
                "collect_title": FlowStep(
                    step_id="collect_title",
                    step_type=FlowStepType.INPUT_COLLECTION,
                    name="Collect Note Title",
                    description="Get the title for the new note",
                    required_parameters=["note_title"],
                    next_steps=["collect_content"]
                ),
                "collect_content": FlowStep(
                    step_id="collect_content", 
                    step_type=FlowStepType.INPUT_COLLECTION,
                    name="Collect Note Content",
                    description="Get the initial content for the note",
                    required_parameters=["content"],
                    next_steps=["confirm_creation"]
                ),
                "confirm_creation": FlowStep(
                    step_id="confirm_creation",
                    step_type=FlowStepType.CONFIRMATION,
                    name="Confirm Note Creation",
                    description="Confirm note creation",
                    next_steps=["create_note"]
                ),
                "create_note": FlowStep(
                    step_id="create_note",
                    step_type=FlowStepType.TOOL_EXECUTION,
                    name="Create Note",
                    description="Create the note file",
                    next_steps=["completion"]
                ),
                "completion": FlowStep(
                    step_id="completion",
                    step_type=FlowStepType.COMPLETION,
                    name="Flow Complete",
                    description="Note creation completed"
                )
            },
            start_step="collect_title"
        )
        templates[note_creation_flow.flow_id] = note_creation_flow
        
        # Research Flow
        research_flow = ConversationFlow(
            flow_id="research_flow",
            name="Research Assistant",
            description="Multi-step research and note organization",
            steps={
                "collect_topic": FlowStep(
                    step_id="collect_topic",
                    step_type=FlowStepType.INPUT_COLLECTION,
                    name="Research Topic",
                    description="What would you like to research?",
                    required_parameters=["research_topic"],
                    next_steps=["search_existing"]
                ),
                "search_existing": FlowStep(
                    step_id="search_existing",
                    step_type=FlowStepType.TOOL_EXECUTION,
                    name="Search Existing Notes",
                    description="Search for existing research",
                    next_steps=["review_results"]
                ),
                "review_results": FlowStep(
                    step_id="review_results",
                    step_type=FlowStepType.DECISION_POINT,
                    name="Review Search Results",
                    description="Review and decide next steps",
                    next_steps=["create_new_note", "enhance_existing", "completion"]
                ),
                "create_new_note": FlowStep(
                    step_id="create_new_note",
                    step_type=FlowStepType.TOOL_EXECUTION,
                    name="Create Research Note",
                    description="Create new research note",
                    next_steps=["completion"]
                ),
                "enhance_existing": FlowStep(
                    step_id="enhance_existing",
                    step_type=FlowStepType.TOOL_EXECUTION,
                    name="Enhance Existing Notes",
                    description="Enhance existing research",
                    next_steps=["completion"]
                ),
                "completion": FlowStep(
                    step_id="completion",
                    step_type=FlowStepType.COMPLETION,
                    name="Research Complete",
                    description="Research session completed"
                )
            },
            start_step="collect_topic"
        )
        templates[research_flow.flow_id] = research_flow
        
        return templates
        
    def register_flow(self, flow: ConversationFlow) -> bool:
        """Register a new conversation flow."""
        try:
            self.flows[flow.flow_id] = flow
            logger.info(f"Registered flow: {flow.flow_id}")
            return True
        except Exception as e:
            logger.error(f"Failed to register flow {flow.flow_id}: {e}")
            return False
            
    def get_available_flows(self) -> List[Dict[str, Any]]:
        """Get list of available flows."""
        return [
            {
                "flow_id": flow.flow_id,
                "name": flow.name,
                "description": flow.description,
                "steps_count": len(flow.steps),
                "tags": flow.tags
            }
            for flow in self.flows.values()
        ]
        
    def get_active_flows(self, user_id: Optional[str] = None) -> List[Dict[str, Any]]:
        """Get list of active flow executions."""
        executions = []
        
        for execution in self.active_executions.values():
            if user_id is None or execution.user_id == user_id:
                executions.append(self.get_flow_context(execution.execution_id))
                
        return executions
        
    def cleanup_expired_flows(self) -> int:
        """Clean up expired flow executions."""
        if not self.auto_cleanup_enabled:
            return 0
            
        expired_count = 0
        current_time = datetime.now()
        expired_executions = []
        
        for execution_id, execution in self.active_executions.items():
            time_since_activity = current_time - execution.last_activity
            if time_since_activity.total_seconds() > (self.flow_timeout_minutes * 60):
                expired_executions.append(execution_id)
                
        for execution_id in expired_executions:
            if self.cancel_flow(execution_id, "timeout"):
                expired_count += 1
                
        if expired_count > 0:
            logger.info(f"Cleaned up {expired_count} expired flow executions")
            
        return expired_count
        
    def get_flow_statistics(self) -> Dict[str, Any]:
        """Get flow management statistics."""
        stats = self.flow_stats.copy()
        
        # Add current state info
        stats["active_flows"] = len(self.active_executions)
        stats["registered_flows"] = len(self.flows)
        stats["users_with_active_flows"] = len([uid for uid, execs in self.user_executions.items() if execs])
        
        # Calculate success rates
        for flow_id, flow_stats in stats["flow_success_rates"].items():
            if flow_stats["started"] > 0:
                flow_stats["success_rate"] = flow_stats["completed"] / flow_stats["started"]
            else:
                flow_stats["success_rate"] = 0.0
                
        return stats
        
    def export_flow_data(self) -> Dict[str, Any]:
        """Export flow definitions and execution data."""
        return {
            "flows": {fid: {
                "flow_id": flow.flow_id,
                "name": flow.name,
                "description": flow.description,
                "steps": {sid: {
                    "step_id": step.step_id,
                    "step_type": step.step_type.value,
                    "name": step.name,
                    "description": step.description,
                    "required_parameters": step.required_parameters,
                    "next_steps": step.next_steps
                } for sid, step in flow.steps.items()},
                "start_step": flow.start_step
            } for fid, flow in self.flows.items()},
            "statistics": self.get_flow_statistics(),
            "export_timestamp": datetime.now().isoformat()
        }