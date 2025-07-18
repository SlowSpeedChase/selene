"""
SMS-22: Analytics Data Collector

Collects and stores analytics data from various sources throughout the Selene system.
This collector integrates with existing monitoring infrastructure to provide
comprehensive analytics data collection.
"""

import sqlite3
import json
import asyncio
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Callable
from pathlib import Path
import logging
from contextlib import contextmanager
from dataclasses import asdict
import threading
from queue import Queue, Empty
import time

from .models import (
    AnalyticsEvent,
    EventType,
    ProcessingMetrics,
    UserBehavior,
    SystemHealth,
    PerformanceMetrics,
    MetricType,
    AnalyticsQuery
)


logger = logging.getLogger(__name__)


class AnalyticsCollector:
    """
    Collects and stores analytics data from various sources.
    
    Features:
    - Async event collection with buffering
    - SQLite storage with automatic schema management
    - Integration with existing monitoring systems
    - Real-time and batch processing support
    - Automatic data retention and cleanup
    """
    
    def __init__(self, db_path: str = "analytics.db", buffer_size: int = 1000):
        self.db_path = Path(db_path)
        self.buffer_size = buffer_size
        self.event_buffer: Queue = Queue(maxsize=buffer_size)
        self.metrics_buffer: Queue = Queue(maxsize=buffer_size)
        
        # Threading for async collection
        self.collection_thread: Optional[threading.Thread] = None
        self.stop_collection = threading.Event()
        
        # Event handlers
        self.event_handlers: Dict[EventType, List[Callable]] = {}
        
        # Initialize database
        self._init_database()
        
        # Start collection thread
        self.start_collection()
    
    def _init_database(self):
        """Initialize SQLite database with analytics schema"""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute('''
                CREATE TABLE IF NOT EXISTS analytics_events (
                    id TEXT PRIMARY KEY,
                    timestamp TEXT NOT NULL,
                    event_type TEXT NOT NULL,
                    user_id TEXT,
                    session_id TEXT,
                    data TEXT,
                    metadata TEXT,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP
                )
            ''')
            
            conn.execute('''
                CREATE TABLE IF NOT EXISTS processing_metrics (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id TEXT NOT NULL,
                    task_type TEXT NOT NULL,
                    model_name TEXT NOT NULL,
                    processor_type TEXT NOT NULL,
                    start_time TEXT NOT NULL,
                    end_time TEXT,
                    duration_seconds REAL,
                    tokens_processed INTEGER,
                    tokens_per_second REAL,
                    input_size INTEGER,
                    output_size INTEGER,
                    success BOOLEAN NOT NULL,
                    error_message TEXT,
                    template_id TEXT,
                    quality_score REAL,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP
                )
            ''')
            
            conn.execute('''
                CREATE TABLE IF NOT EXISTS user_behavior (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id TEXT NOT NULL,
                    session_id TEXT NOT NULL,
                    timestamp TEXT NOT NULL,
                    action TEXT NOT NULL,
                    page_path TEXT,
                    duration_seconds REAL,
                    success BOOLEAN NOT NULL,
                    context TEXT,
                    previous_action TEXT,
                    next_action TEXT,
                    feature_used TEXT,
                    feature_success BOOLEAN,
                    feature_context TEXT,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP
                )
            ''')
            
            conn.execute('''
                CREATE TABLE IF NOT EXISTS system_health (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    cpu_usage REAL NOT NULL,
                    memory_usage REAL NOT NULL,
                    disk_usage REAL NOT NULL,
                    active_sessions INTEGER NOT NULL,
                    queue_size INTEGER NOT NULL,
                    processed_files INTEGER NOT NULL,
                    error_rate REAL NOT NULL,
                    response_time_avg REAL NOT NULL,
                    ollama_status TEXT,
                    vector_db_status TEXT,
                    web_server_status TEXT,
                    throughput REAL,
                    latency_p95 REAL,
                    availability REAL,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP
                )
            ''')
            
            conn.execute('''
                CREATE TABLE IF NOT EXISTS performance_metrics (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    metric_name TEXT NOT NULL,
                    metric_type TEXT NOT NULL,
                    value REAL NOT NULL,
                    timestamp TEXT NOT NULL,
                    labels TEXT,
                    baseline_value REAL,
                    threshold_warning REAL,
                    threshold_critical REAL,
                    created_at TEXT DEFAULT CURRENT_TIMESTAMP
                )
            ''')
            
            # Create indexes for better query performance
            conn.execute('CREATE INDEX IF NOT EXISTS idx_events_timestamp ON analytics_events(timestamp)')
            conn.execute('CREATE INDEX IF NOT EXISTS idx_events_type ON analytics_events(event_type)')
            conn.execute('CREATE INDEX IF NOT EXISTS idx_events_session ON analytics_events(session_id)')
            conn.execute('CREATE INDEX IF NOT EXISTS idx_metrics_session ON processing_metrics(session_id)')
            conn.execute('CREATE INDEX IF NOT EXISTS idx_metrics_task ON processing_metrics(task_type)')
            conn.execute('CREATE INDEX IF NOT EXISTS idx_behavior_user ON user_behavior(user_id)')
            conn.execute('CREATE INDEX IF NOT EXISTS idx_behavior_action ON user_behavior(action)')
            conn.execute('CREATE INDEX IF NOT EXISTS idx_health_timestamp ON system_health(timestamp)')
            conn.execute('CREATE INDEX IF NOT EXISTS idx_performance_name ON performance_metrics(metric_name)')
            
            conn.commit()
    
    def start_collection(self):
        """Start the analytics collection thread"""
        if self.collection_thread is None or not self.collection_thread.is_alive():
            self.stop_collection.clear()
            self.collection_thread = threading.Thread(target=self._collection_worker)
            self.collection_thread.daemon = True
            self.collection_thread.start()
            logger.info("Analytics collection thread started")
    
    def stop_collection_thread(self):
        """Stop the analytics collection thread"""
        self.stop_collection.set()
        if self.collection_thread and self.collection_thread.is_alive():
            self.collection_thread.join(timeout=5)
            logger.info("Analytics collection thread stopped")
    
    def _collection_worker(self):
        """Worker thread for processing analytics data"""
        batch_events = []
        batch_metrics = []
        last_flush = time.time()
        flush_interval = 5.0  # Flush every 5 seconds
        
        while not self.stop_collection.is_set():
            try:
                # Process events
                try:
                    event = self.event_buffer.get(timeout=0.1)
                    batch_events.append(event)
                except Empty:
                    pass
                
                # Process metrics
                try:
                    metric = self.metrics_buffer.get(timeout=0.1)
                    batch_metrics.append(metric)
                except Empty:
                    pass
                
                # Flush batches periodically or when buffer is full
                current_time = time.time()
                should_flush = (
                    current_time - last_flush > flush_interval or
                    len(batch_events) >= 50 or
                    len(batch_metrics) >= 50
                )
                
                if should_flush:
                    if batch_events:
                        self._flush_events(batch_events)
                        batch_events.clear()
                    
                    if batch_metrics:
                        self._flush_metrics(batch_metrics)
                        batch_metrics.clear()
                    
                    last_flush = current_time
                    
            except Exception as e:
                logger.error(f"Error in analytics collection worker: {e}")
                time.sleep(1)
        
        # Final flush before stopping
        if batch_events:
            self._flush_events(batch_events)
        if batch_metrics:
            self._flush_metrics(batch_metrics)
    
    def _flush_events(self, events: List[AnalyticsEvent]):
        """Flush events to database"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                for event in events:
                    conn.execute('''
                        INSERT INTO analytics_events 
                        (id, timestamp, event_type, user_id, session_id, data, metadata)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                    ''', (
                        event.id,
                        event.timestamp.isoformat(),
                        event.event_type.value,
                        event.user_id,
                        event.session_id,
                        json.dumps(event.data),
                        json.dumps(event.metadata)
                    ))
                conn.commit()
                logger.debug(f"Flushed {len(events)} events to database")
        except Exception as e:
            logger.error(f"Error flushing events to database: {e}")
    
    def _flush_metrics(self, metrics: List[Any]):
        """Flush metrics to database"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                for metric in metrics:
                    if isinstance(metric, ProcessingMetrics):
                        conn.execute('''
                            INSERT INTO processing_metrics 
                            (session_id, task_type, model_name, processor_type, start_time, end_time,
                             duration_seconds, tokens_processed, tokens_per_second, input_size,
                             output_size, success, error_message, template_id, quality_score)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ''', (
                            metric.session_id,
                            metric.task_type,
                            metric.model_name,
                            metric.processor_type,
                            metric.start_time.isoformat(),
                            metric.end_time.isoformat() if metric.end_time else None,
                            metric.duration_seconds,
                            metric.tokens_processed,
                            metric.tokens_per_second,
                            metric.input_size,
                            metric.output_size,
                            metric.success,
                            metric.error_message,
                            metric.template_id,
                            metric.quality_score
                        ))
                    elif isinstance(metric, UserBehavior):
                        conn.execute('''
                            INSERT INTO user_behavior 
                            (user_id, session_id, timestamp, action, page_path, duration_seconds,
                             success, context, previous_action, next_action, feature_used,
                             feature_success, feature_context)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ''', (
                            metric.user_id,
                            metric.session_id,
                            metric.timestamp.isoformat(),
                            metric.action,
                            metric.page_path,
                            metric.duration_seconds,
                            metric.success,
                            json.dumps(metric.context),
                            metric.previous_action,
                            metric.next_action,
                            metric.feature_used,
                            metric.feature_success,
                            json.dumps(metric.feature_context)
                        ))
                    elif isinstance(metric, SystemHealth):
                        conn.execute('''
                            INSERT INTO system_health 
                            (timestamp, cpu_usage, memory_usage, disk_usage, active_sessions,
                             queue_size, processed_files, error_rate, response_time_avg,
                             ollama_status, vector_db_status, web_server_status,
                             throughput, latency_p95, availability)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ''', (
                            metric.timestamp.isoformat(),
                            metric.cpu_usage,
                            metric.memory_usage,
                            metric.disk_usage,
                            metric.active_sessions,
                            metric.queue_size,
                            metric.processed_files,
                            metric.error_rate,
                            metric.response_time_avg,
                            metric.ollama_status,
                            metric.vector_db_status,
                            metric.web_server_status,
                            metric.throughput,
                            metric.latency_p95,
                            metric.availability
                        ))
                    elif isinstance(metric, PerformanceMetrics):
                        conn.execute('''
                            INSERT INTO performance_metrics 
                            (metric_name, metric_type, value, timestamp, labels,
                             baseline_value, threshold_warning, threshold_critical)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        ''', (
                            metric.metric_name,
                            metric.metric_type.value,
                            metric.value,
                            metric.timestamp.isoformat(),
                            json.dumps(metric.labels),
                            metric.baseline_value,
                            metric.threshold_warning,
                            metric.threshold_critical
                        ))
                conn.commit()
                logger.debug(f"Flushed {len(metrics)} metrics to database")
        except Exception as e:
            logger.error(f"Error flushing metrics to database: {e}")
    
    def collect_event(self, event: AnalyticsEvent):
        """Collect an analytics event"""
        try:
            self.event_buffer.put_nowait(event)
            
            # Trigger event handlers
            if event.event_type in self.event_handlers:
                for handler in self.event_handlers[event.event_type]:
                    try:
                        handler(event)
                    except Exception as e:
                        logger.error(f"Error in event handler: {e}")
                        
        except Exception as e:
            logger.error(f"Error collecting event: {e}")
    
    def collect_metric(self, metric: Any):
        """Collect a metric"""
        try:
            self.metrics_buffer.put_nowait(metric)
        except Exception as e:
            logger.error(f"Error collecting metric: {e}")
    
    def add_event_handler(self, event_type: EventType, handler: Callable):
        """Add an event handler for specific event types"""
        if event_type not in self.event_handlers:
            self.event_handlers[event_type] = []
        self.event_handlers[event_type].append(handler)
    
    def query_events(self, query: AnalyticsQuery) -> List[AnalyticsEvent]:
        """Query analytics events"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                
                sql = f'''
                    SELECT * FROM analytics_events 
                    WHERE {query.to_sql_where()}
                    ORDER BY timestamp DESC
                '''
                
                if query.limit:
                    sql += f' LIMIT {query.limit}'
                if query.offset:
                    sql += f' OFFSET {query.offset}'
                
                cursor = conn.execute(sql)
                rows = cursor.fetchall()
                
                events = []
                for row in rows:
                    event = AnalyticsEvent(
                        id=row['id'],
                        timestamp=datetime.fromisoformat(row['timestamp']),
                        event_type=EventType(row['event_type']),
                        user_id=row['user_id'],
                        session_id=row['session_id'],
                        data=json.loads(row['data']) if row['data'] else {},
                        metadata=json.loads(row['metadata']) if row['metadata'] else {}
                    )
                    events.append(event)
                
                return events
                
        except Exception as e:
            logger.error(f"Error querying events: {e}")
            return []
    
    def get_processing_metrics(self, session_id: Optional[str] = None,
                             task_type: Optional[str] = None,
                             start_time: Optional[datetime] = None,
                             end_time: Optional[datetime] = None) -> List[ProcessingMetrics]:
        """Get processing metrics with optional filters"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                
                conditions = []
                params = []
                
                if session_id:
                    conditions.append('session_id = ?')
                    params.append(session_id)
                
                if task_type:
                    conditions.append('task_type = ?')
                    params.append(task_type)
                
                if start_time:
                    conditions.append('start_time >= ?')
                    params.append(start_time.isoformat())
                
                if end_time:
                    conditions.append('start_time <= ?')
                    params.append(end_time.isoformat())
                
                where_clause = ' AND '.join(conditions) if conditions else '1=1'
                
                cursor = conn.execute(f'''
                    SELECT * FROM processing_metrics 
                    WHERE {where_clause}
                    ORDER BY start_time DESC
                ''', params)
                
                rows = cursor.fetchall()
                
                metrics = []
                for row in rows:
                    metric = ProcessingMetrics(
                        session_id=row['session_id'],
                        task_type=row['task_type'],
                        model_name=row['model_name'],
                        processor_type=row['processor_type'],
                        start_time=datetime.fromisoformat(row['start_time']),
                        end_time=datetime.fromisoformat(row['end_time']) if row['end_time'] else None,
                        duration_seconds=row['duration_seconds'],
                        tokens_processed=row['tokens_processed'],
                        tokens_per_second=row['tokens_per_second'],
                        input_size=row['input_size'],
                        output_size=row['output_size'],
                        success=bool(row['success']),
                        error_message=row['error_message'],
                        template_id=row['template_id'],
                        quality_score=row['quality_score']
                    )
                    metrics.append(metric)
                
                return metrics
                
        except Exception as e:
            logger.error(f"Error getting processing metrics: {e}")
            return []
    
    def cleanup_old_data(self, days_to_keep: int = 30):
        """Clean up old analytics data"""
        try:
            cutoff_date = datetime.now() - timedelta(days=days_to_keep)
            
            with sqlite3.connect(self.db_path) as conn:
                tables = [
                    'analytics_events',
                    'processing_metrics',
                    'user_behavior',
                    'system_health',
                    'performance_metrics'
                ]
                
                for table in tables:
                    cursor = conn.execute(f'''
                        DELETE FROM {table} 
                        WHERE created_at < ?
                    ''', (cutoff_date.isoformat(),))
                    
                    deleted_count = cursor.rowcount
                    logger.info(f"Deleted {deleted_count} old records from {table}")
                
                conn.commit()
                
        except Exception as e:
            logger.error(f"Error cleaning up old data: {e}")
    
    def get_database_stats(self) -> Dict[str, Any]:
        """Get database statistics"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                stats = {}
                
                tables = [
                    'analytics_events',
                    'processing_metrics',
                    'user_behavior',
                    'system_health',
                    'performance_metrics'
                ]
                
                for table in tables:
                    cursor = conn.execute(f'SELECT COUNT(*) FROM {table}')
                    stats[f'{table}_count'] = cursor.fetchone()[0]
                
                # Database size
                cursor = conn.execute("SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()")
                stats['database_size_bytes'] = cursor.fetchone()[0]
                
                return stats
                
        except Exception as e:
            logger.error(f"Error getting database stats: {e}")
            return {}
    
    def __del__(self):
        """Cleanup on destruction"""
        self.stop_collection_thread()


# Global analytics collector instance
_analytics_collector: Optional[AnalyticsCollector] = None


def get_analytics_collector() -> AnalyticsCollector:
    """Get the global analytics collector instance"""
    global _analytics_collector
    if _analytics_collector is None:
        _analytics_collector = AnalyticsCollector()
    return _analytics_collector


def collect_event(event: AnalyticsEvent):
    """Convenience function to collect an event"""
    collector = get_analytics_collector()
    collector.collect_event(event)


def collect_metric(metric: Any):
    """Convenience function to collect a metric"""
    collector = get_analytics_collector()
    collector.collect_metric(metric)