# Real-Time LLM Processing Monitor

## Overview

The Real-Time LLM Processing Monitor provides detailed visibility into AI processing operations, replacing generic "processing" messages with granular stage-by-stage progress tracking and real-time updates.

## Features

### 🔍 **Processing Stages**
The monitor tracks 10 distinct processing stages:

1. **Initializing** - Starting the processing session
2. **Validating Input** - Checking content validity and format
3. **Resolving Template** - Finding and loading prompt templates
4. **Generating Prompt** - Rendering final prompt with variables
5. **Selecting Model** - Choosing optimal AI model (multi-model processor)
6. **Connecting to Model** - Establishing connection to LLM service
7. **Sending Request** - Transmitting prompt to LLM
8. **Streaming Response** - Receiving LLM response with token counting
9. **Processing Response** - Parsing and formatting output
10. **Collecting Metadata** - Gathering timing and usage statistics

### 📊 **Real-Time Updates**
- **WebSocket Communication**: Live updates via `/ws/monitoring`
- **Progress Tracking**: 0-100% progress for each processing session
- **Session Management**: Unique session IDs for tracking individual requests
- **Event Timeline**: Complete history of processing events per session

### 🖥️ **Web Interface**
- **Processing Monitor Tab**: New tab in the web dashboard
- **Live Statistics**: Success rates, processing times, session counts
- **Active Sessions**: Real-time view of currently processing requests
- **Session Details**: Detailed timeline and metadata for selected sessions
- **Recent History**: Complete history of recent processing sessions

## Usage

### Starting the Monitor

1. **Start Web Server**:
   ```bash
   python -m selene.main web
   ```

2. **Open Browser**: Navigate to `http://localhost:8000`

3. **Access Monitor**: Click the "Processing Monitor" tab

### Monitoring Processing

The monitor automatically tracks all processing requests. Each request gets:
- **Unique Session ID**: For tracking and reference
- **Real-time Progress**: Updated as processing progresses
- **Stage Information**: Current stage and detailed status
- **Performance Metrics**: Token counts, processing time, etc.

### API Access

#### WebSocket Connection
```javascript
const ws = new WebSocket('ws://localhost:8000/ws/monitoring');
ws.onmessage = (event) => {
    const data = JSON.parse(event.data);
    console.log('Monitor update:', data);
};
```

#### REST API Endpoints
- `GET /api/monitoring/statistics` - Processing statistics
- `GET /api/monitoring/sessions/active` - Active sessions
- `GET /api/monitoring/sessions/recent` - Recent sessions
- `GET /api/monitoring/sessions/{session_id}` - Session details

## Configuration

### Enabling/Disabling Monitoring

Monitoring can be controlled per processor:

```python
# Enable monitoring (default)
processor = OllamaProcessor({
    "enable_monitoring": True
})

# Disable monitoring for performance
processor = OllamaProcessor({
    "enable_monitoring": False
})
```

### Session Retention

- **Active Sessions**: Kept until completion or failure
- **Completed Sessions**: Retained for 1 hour
- **Automatic Cleanup**: Background task removes old sessions

## Technical Implementation

### Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Processor     │    │   Monitor        │    │   WebSocket     │
│   (Base/Ollama) │───▶│   System         │───▶│   Clients       │
│                 │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Processing    │    │   Session        │    │   Real-time     │
│   Events        │    │   Storage        │    │   Updates       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Event System

The monitoring system uses a lightweight event-driven architecture:

```python
# Emit processing stage
self.emit_stage(session_id, ProcessingStage.VALIDATING_INPUT, 
               "Validating input content")

# Emit streaming token
self.emit_streaming_token(session_id, token, token_count)

# Finish session
self.finish_monitoring_session(session_id, success=True, 
                              final_result=content)
```

### Data Models

#### ProcessingSession
```python
@dataclass
class ProcessingSession:
    session_id: str
    start_time: float
    current_stage: ProcessingStage
    progress: float
    content_preview: str
    task: str
    model: str
    processor_type: str
    events: List[ProcessingEvent]
    streaming_tokens: List[str]
    metadata: Dict[str, Any]
    error: Optional[str]
```

#### ProcessingEvent
```python
@dataclass
class ProcessingEvent:
    session_id: str
    stage: ProcessingStage
    timestamp: float
    message: str
    progress: float
    metadata: Dict[str, Any]
    error: Optional[str]
```

## Performance Impact

### Overhead
- **Minimal CPU**: Event emission adds ~0.1ms per stage
- **Memory**: ~1KB per session, auto-cleanup after 1 hour
- **Network**: WebSocket updates only when clients connected
- **Optional**: Can be completely disabled if needed

### Optimization
- **Lazy Connection**: WebSocket only connects when monitoring tab active
- **Batch Updates**: Multiple events batched for efficiency
- **Automatic Cleanup**: Old sessions removed automatically
- **Graceful Degradation**: System works normally if monitoring fails

## Integration with Existing Features

### Template System
- Tracks template resolution and rendering
- Shows template ID and variables used
- Integrates with template analytics

### Multi-Model Processing
- Shows model selection process
- Tracks fallback attempts
- Displays routing decisions

### Chain Processing
- Monitors each step in the chain
- Shows conditional branching
- Tracks parallel execution

### Vector Database
- Monitors embedding generation
- Tracks similarity searches
- Shows storage operations

## Development

### Adding Monitoring to New Processors

1. **Inherit from BaseProcessor**:
   ```python
   class MyProcessor(BaseProcessor):
       def __init__(self, config):
           super().__init__(config)
   ```

2. **Start Monitoring Session**:
   ```python
   session_id = self.start_monitoring_session(content, task, model)
   ```

3. **Emit Stages**:
   ```python
   self.emit_stage(session_id, ProcessingStage.CONNECTING_TO_MODEL, 
                  "Connecting to custom model")
   ```

4. **Finish Session**:
   ```python
   self.finish_monitoring_session(session_id, success=True, 
                                 final_result=result)
   ```

### Custom Processing Stages

Add new stages to the `ProcessingStage` enum:

```python
class ProcessingStage(Enum):
    # ... existing stages ...
    CUSTOM_VALIDATION = "custom_validation"
    CUSTOM_PROCESSING = "custom_processing"
```

Update progress mapping:
```python
STAGE_PROGRESS = {
    # ... existing mappings ...
    ProcessingStage.CUSTOM_VALIDATION: 0.15,
    ProcessingStage.CUSTOM_PROCESSING: 0.75,
}
```

## Testing

### Manual Testing
```bash
# Run test script
python test_monitoring.py

# Start web server in another terminal
python -m selene.main web

# Open browser and watch real-time updates
```

### API Testing
```bash
# Test WebSocket connection
wscat -c ws://localhost:8000/ws/monitoring

# Test REST endpoints
curl http://localhost:8000/api/monitoring/statistics
curl http://localhost:8000/api/monitoring/sessions/active
```

## Troubleshooting

### Common Issues

1. **WebSocket Connection Failed**
   - Check if web server is running
   - Verify port 8000 is accessible
   - Check browser console for errors

2. **No Monitoring Events**
   - Ensure `enable_monitoring: True` in processor config
   - Check if event loop is running for async operations
   - Verify processor inherits from BaseProcessor

3. **Performance Issues**
   - Disable monitoring for high-volume processing
   - Reduce session retention time
   - Limit concurrent WebSocket connections

### Debug Mode

Enable debug logging:
```python
import logging
logging.getLogger('selene.processors.monitoring').setLevel(logging.DEBUG)
```

## Future Enhancements

### Planned Features
- **Processing Analytics**: Historical performance analysis
- **Alert System**: Notifications for failed processing
- **Export Data**: CSV/JSON export of monitoring data
- **Mobile Monitoring**: Mobile-optimized monitoring interface
- **Custom Dashboards**: User-configurable monitoring views

### Integration Ideas
- **Prometheus Metrics**: Export metrics for monitoring systems
- **Grafana Dashboards**: Pre-built visualization dashboards
- **Log Integration**: Structured logging with monitoring events
- **Performance Profiling**: Detailed performance breakdown

---

*The Real-Time LLM Processing Monitor provides unprecedented visibility into AI processing operations, enabling better debugging, performance optimization, and user experience.*