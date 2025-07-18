"""
SMS-22: Analytics Data Models

Defines the data models and schemas for the advanced analytics system.
These models extend the existing monitoring infrastructure to support
historical analysis, user behavior tracking, and performance optimization.
"""

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Union
from enum import Enum
import json
import uuid


class EventType(Enum):
    """Types of analytics events"""
    PROCESSING_START = "processing_start"
    PROCESSING_COMPLETE = "processing_complete"
    PROCESSING_ERROR = "processing_error"
    USER_ACTION = "user_action"
    SYSTEM_HEALTH = "system_health"
    PERFORMANCE_METRIC = "performance_metric"
    TEMPLATE_USAGE = "template_usage"
    VECTOR_OPERATION = "vector_operation"
    CHAT_INTERACTION = "chat_interaction"
    WEB_REQUEST = "web_request"


class MetricType(Enum):
    """Types of metrics"""
    COUNTER = "counter"
    GAUGE = "gauge"
    HISTOGRAM = "histogram"
    TIMER = "timer"


@dataclass
class AnalyticsEvent:
    """Base analytics event model"""
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    timestamp: datetime = field(default_factory=datetime.now)
    event_type: EventType = EventType.USER_ACTION
    user_id: Optional[str] = None
    session_id: Optional[str] = None
    data: Dict[str, Any] = field(default_factory=dict)
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for storage"""
        return {
            'id': self.id,
            'timestamp': self.timestamp.isoformat(),
            'event_type': self.event_type.value,
            'user_id': self.user_id,
            'session_id': self.session_id,
            'data': self.data,
            'metadata': self.metadata
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'AnalyticsEvent':
        """Create from dictionary"""
        return cls(
            id=data['id'],
            timestamp=datetime.fromisoformat(data['timestamp']),
            event_type=EventType(data['event_type']),
            user_id=data.get('user_id'),
            session_id=data.get('session_id'),
            data=data.get('data', {}),
            metadata=data.get('metadata', {})
        )


@dataclass
class ProcessingMetrics:
    """Metrics for content processing operations"""
    session_id: str
    task_type: str
    model_name: str
    processor_type: str
    start_time: datetime
    end_time: Optional[datetime] = None
    duration_seconds: Optional[float] = None
    tokens_processed: Optional[int] = None
    tokens_per_second: Optional[float] = None
    input_size: Optional[int] = None
    output_size: Optional[int] = None
    success: bool = True
    error_message: Optional[str] = None
    template_id: Optional[str] = None
    quality_score: Optional[float] = None
    
    def calculate_duration(self) -> Optional[float]:
        """Calculate duration if end time is set"""
        if self.end_time:
            self.duration_seconds = (self.end_time - self.start_time).total_seconds()
        return self.duration_seconds
    
    def calculate_tokens_per_second(self) -> Optional[float]:
        """Calculate tokens per second if data is available"""
        if self.tokens_processed and self.duration_seconds and self.duration_seconds > 0:
            self.tokens_per_second = self.tokens_processed / self.duration_seconds
        return self.tokens_per_second


@dataclass
class UserBehavior:
    """User behavior tracking model"""
    user_id: str
    session_id: str
    timestamp: datetime
    action: str  # 'process_content', 'search_vector', 'chat_message', etc.
    page_path: Optional[str] = None
    duration_seconds: Optional[float] = None
    success: bool = True
    context: Dict[str, Any] = field(default_factory=dict)
    
    # User journey tracking
    previous_action: Optional[str] = None
    next_action: Optional[str] = None
    
    # Feature usage
    feature_used: Optional[str] = None
    feature_success: bool = True
    feature_context: Dict[str, Any] = field(default_factory=dict)


@dataclass
class SystemHealth:
    """System health metrics"""
    timestamp: datetime
    cpu_usage: float
    memory_usage: float
    disk_usage: float
    active_sessions: int
    queue_size: int
    processed_files: int
    error_rate: float
    response_time_avg: float
    
    # Service-specific health
    ollama_status: str = "unknown"  # 'online', 'offline', 'degraded'
    vector_db_status: str = "unknown"
    web_server_status: str = "unknown"
    
    # Performance indicators
    throughput: float = 0.0  # operations per second
    latency_p95: float = 0.0  # 95th percentile latency
    availability: float = 100.0  # percentage uptime


@dataclass
class PerformanceMetrics:
    """Performance optimization metrics"""
    metric_name: str
    metric_type: MetricType
    value: Union[int, float]
    timestamp: datetime
    labels: Dict[str, str] = field(default_factory=dict)
    
    # Time-series data for trends
    historical_values: List[float] = field(default_factory=list)
    
    # Performance analysis
    baseline_value: Optional[float] = None
    threshold_warning: Optional[float] = None
    threshold_critical: Optional[float] = None
    
    def is_above_threshold(self, level: str = "warning") -> bool:
        """Check if metric is above threshold"""
        threshold = getattr(self, f"threshold_{level}", None)
        return threshold is not None and self.value > threshold
    
    def get_trend(self, window_size: int = 10) -> str:
        """Get trend direction over recent values"""
        if len(self.historical_values) < window_size:
            return "insufficient_data"
        
        recent_values = self.historical_values[-window_size:]
        first_half = sum(recent_values[:window_size//2]) / (window_size//2)
        second_half = sum(recent_values[window_size//2:]) / (window_size//2)
        
        if second_half > first_half * 1.05:
            return "increasing"
        elif second_half < first_half * 0.95:
            return "decreasing"
        else:
            return "stable"


@dataclass
class AnalyticsReport:
    """Analytics report model"""
    report_id: str
    report_type: str
    title: str
    created_at: datetime
    time_range: Dict[str, datetime]
    metrics: Dict[str, Any]
    insights: List[str]
    recommendations: List[str]
    
    def to_json(self) -> str:
        """Convert to JSON string"""
        data = {
            'report_id': self.report_id,
            'report_type': self.report_type,
            'title': self.title,
            'created_at': self.created_at.isoformat(),
            'time_range': {
                k: v.isoformat() for k, v in self.time_range.items()
            },
            'metrics': self.metrics,
            'insights': self.insights,
            'recommendations': self.recommendations
        }
        return json.dumps(data, indent=2)


@dataclass
class AnalyticsQuery:
    """Analytics query model for flexible data retrieval"""
    start_time: datetime
    end_time: datetime
    event_types: List[EventType] = field(default_factory=list)
    filters: Dict[str, Any] = field(default_factory=dict)
    aggregations: List[str] = field(default_factory=list)
    group_by: List[str] = field(default_factory=list)
    limit: Optional[int] = None
    offset: Optional[int] = None
    
    def to_sql_where(self) -> str:
        """Convert to SQL WHERE clause"""
        conditions = [
            f"timestamp >= '{self.start_time.isoformat()}'",
            f"timestamp <= '{self.end_time.isoformat()}'"
        ]
        
        if self.event_types:
            event_values = "', '".join([et.value for et in self.event_types])
            conditions.append(f"event_type IN ('{event_values}')")
        
        for key, value in self.filters.items():
            if isinstance(value, str):
                conditions.append(f"{key} = '{value}'")
            elif isinstance(value, (int, float)):
                conditions.append(f"{key} = {value}")
            elif isinstance(value, list):
                values = "', '".join([str(v) for v in value])
                conditions.append(f"{key} IN ('{values}')")
        
        return " AND ".join(conditions)


# Predefined metric configurations
SYSTEM_METRICS = {
    'processing_throughput': PerformanceMetrics(
        metric_name='processing_throughput',
        metric_type=MetricType.GAUGE,
        value=0.0,
        timestamp=datetime.now(),
        labels={'unit': 'operations_per_second'},
        threshold_warning=10.0,
        threshold_critical=5.0
    ),
    'response_time': PerformanceMetrics(
        metric_name='response_time',
        metric_type=MetricType.HISTOGRAM,
        value=0.0,
        timestamp=datetime.now(),
        labels={'unit': 'seconds'},
        threshold_warning=5.0,
        threshold_critical=10.0
    ),
    'error_rate': PerformanceMetrics(
        metric_name='error_rate',
        metric_type=MetricType.GAUGE,
        value=0.0,
        timestamp=datetime.now(),
        labels={'unit': 'percentage'},
        threshold_warning=5.0,
        threshold_critical=10.0
    ),
    'memory_usage': PerformanceMetrics(
        metric_name='memory_usage',
        metric_type=MetricType.GAUGE,
        value=0.0,
        timestamp=datetime.now(),
        labels={'unit': 'percentage'},
        threshold_warning=80.0,
        threshold_critical=90.0
    )
}