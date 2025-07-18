"""
SMS-22: Analytics Data Aggregator

Aggregates analytics data for reporting and visualization.
Provides time-series analysis, trend detection, and statistical summaries.
"""

import sqlite3
import json
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass, field
from collections import defaultdict
import statistics
import logging
from pathlib import Path

from .models import (
    AnalyticsEvent,
    EventType,
    ProcessingMetrics,
    UserBehavior,
    SystemHealth,
    PerformanceMetrics,
    AnalyticsQuery
)


logger = logging.getLogger(__name__)


@dataclass
class TimeSeriesPoint:
    """Single point in time series data"""
    timestamp: datetime
    value: float
    labels: Dict[str, str] = field(default_factory=dict)


@dataclass
class TimeSeriesData:
    """Time series data with metadata"""
    metric_name: str
    points: List[TimeSeriesPoint]
    unit: str = ""
    description: str = ""
    
    def get_values(self) -> List[float]:
        """Get just the values"""
        return [point.value for point in self.points]
    
    def get_timestamps(self) -> List[datetime]:
        """Get just the timestamps"""
        return [point.timestamp for point in self.points]


@dataclass
class AggregatedMetric:
    """Aggregated metric with statistical summaries"""
    metric_name: str
    count: int
    sum: float
    mean: float
    median: float
    min: float
    max: float
    std_dev: float
    percentile_95: float
    percentile_99: float
    trend: str  # 'increasing', 'decreasing', 'stable'
    
    @classmethod
    def from_values(cls, metric_name: str, values: List[float]) -> 'AggregatedMetric':
        """Create from list of values"""
        if not values:
            return cls(
                metric_name=metric_name,
                count=0, sum=0.0, mean=0.0, median=0.0,
                min=0.0, max=0.0, std_dev=0.0,
                percentile_95=0.0, percentile_99=0.0,
                trend='stable'
            )
        
        sorted_values = sorted(values)
        count = len(values)
        sum_val = sum(values)
        mean = sum_val / count
        median = statistics.median(values)
        min_val = min(values)
        max_val = max(values)
        std_dev = statistics.stdev(values) if count > 1 else 0.0
        
        # Percentiles
        p95_idx = int(0.95 * count)
        p99_idx = int(0.99 * count)
        percentile_95 = sorted_values[min(p95_idx, count - 1)]
        percentile_99 = sorted_values[min(p99_idx, count - 1)]
        
        # Simple trend calculation
        if count > 10:
            first_half = values[:count//2]
            second_half = values[count//2:]
            first_avg = sum(first_half) / len(first_half)
            second_avg = sum(second_half) / len(second_half)
            
            if second_avg > first_avg * 1.05:
                trend = 'increasing'
            elif second_avg < first_avg * 0.95:
                trend = 'decreasing'
            else:
                trend = 'stable'
        else:
            trend = 'stable'
        
        return cls(
            metric_name=metric_name,
            count=count,
            sum=sum_val,
            mean=mean,
            median=median,
            min=min_val,
            max=max_val,
            std_dev=std_dev,
            percentile_95=percentile_95,
            percentile_99=percentile_99,
            trend=trend
        )


class AnalyticsAggregator:
    """
    Aggregates analytics data for reporting and visualization.
    
    Features:
    - Time-series data aggregation
    - Statistical summaries
    - Trend analysis
    - Performance metrics calculation
    - User behavior analysis
    """
    
    def __init__(self, db_path: str = "analytics.db"):
        self.db_path = Path(db_path)
    
    def get_processing_summary(self, start_time: datetime, end_time: datetime) -> Dict[str, Any]:
        """Get processing metrics summary"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                
                # Overall processing stats
                cursor = conn.execute('''
                    SELECT 
                        COUNT(*) as total_sessions,
                        COUNT(CASE WHEN success = 1 THEN 1 END) as successful_sessions,
                        COUNT(CASE WHEN success = 0 THEN 1 END) as failed_sessions,
                        AVG(duration_seconds) as avg_duration,
                        SUM(tokens_processed) as total_tokens,
                        AVG(tokens_per_second) as avg_tokens_per_second,
                        AVG(quality_score) as avg_quality_score
                    FROM processing_metrics
                    WHERE start_time >= ? AND start_time <= ?
                ''', (start_time.isoformat(), end_time.isoformat()))
                
                overall_stats = dict(cursor.fetchone())
                
                # Success rate
                if overall_stats['total_sessions'] > 0:
                    overall_stats['success_rate'] = (
                        overall_stats['successful_sessions'] / overall_stats['total_sessions']
                    ) * 100
                else:
                    overall_stats['success_rate'] = 0.0
                
                # Task type breakdown
                cursor = conn.execute('''
                    SELECT 
                        task_type,
                        COUNT(*) as count,
                        AVG(duration_seconds) as avg_duration,
                        COUNT(CASE WHEN success = 1 THEN 1 END) * 100.0 / COUNT(*) as success_rate
                    FROM processing_metrics
                    WHERE start_time >= ? AND start_time <= ?
                    GROUP BY task_type
                    ORDER BY count DESC
                ''', (start_time.isoformat(), end_time.isoformat()))
                
                task_breakdown = [dict(row) for row in cursor.fetchall()]
                
                # Model performance
                cursor = conn.execute('''
                    SELECT 
                        model_name,
                        COUNT(*) as count,
                        AVG(duration_seconds) as avg_duration,
                        AVG(tokens_per_second) as avg_tokens_per_second,
                        COUNT(CASE WHEN success = 1 THEN 1 END) * 100.0 / COUNT(*) as success_rate
                    FROM processing_metrics
                    WHERE start_time >= ? AND start_time <= ?
                    GROUP BY model_name
                    ORDER BY count DESC
                ''', (start_time.isoformat(), end_time.isoformat()))
                
                model_performance = [dict(row) for row in cursor.fetchall()]
                
                # Processor type stats
                cursor = conn.execute('''
                    SELECT 
                        processor_type,
                        COUNT(*) as count,
                        AVG(duration_seconds) as avg_duration,
                        COUNT(CASE WHEN success = 1 THEN 1 END) * 100.0 / COUNT(*) as success_rate
                    FROM processing_metrics
                    WHERE start_time >= ? AND start_time <= ?
                    GROUP BY processor_type
                    ORDER BY count DESC
                ''', (start_time.isoformat(), end_time.isoformat()))
                
                processor_stats = [dict(row) for row in cursor.fetchall()]
                
                return {
                    'overall_stats': overall_stats,
                    'task_breakdown': task_breakdown,
                    'model_performance': model_performance,
                    'processor_stats': processor_stats,
                    'time_range': {
                        'start': start_time.isoformat(),
                        'end': end_time.isoformat()
                    }
                }
                
        except Exception as e:
            logger.error(f"Error getting processing summary: {e}")
            return {}
    
    def get_user_behavior_summary(self, start_time: datetime, end_time: datetime) -> Dict[str, Any]:
        """Get user behavior analysis"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                
                # User activity stats
                cursor = conn.execute('''
                    SELECT 
                        COUNT(DISTINCT user_id) as unique_users,
                        COUNT(DISTINCT session_id) as unique_sessions,
                        COUNT(*) as total_actions,
                        AVG(duration_seconds) as avg_action_duration,
                        COUNT(CASE WHEN success = 1 THEN 1 END) * 100.0 / COUNT(*) as success_rate
                    FROM user_behavior
                    WHERE timestamp >= ? AND timestamp <= ?
                ''', (start_time.isoformat(), end_time.isoformat()))
                
                activity_stats = dict(cursor.fetchone())
                
                # Popular actions
                cursor = conn.execute('''
                    SELECT 
                        action,
                        COUNT(*) as count,
                        AVG(duration_seconds) as avg_duration,
                        COUNT(CASE WHEN success = 1 THEN 1 END) * 100.0 / COUNT(*) as success_rate
                    FROM user_behavior
                    WHERE timestamp >= ? AND timestamp <= ?
                    GROUP BY action
                    ORDER BY count DESC
                    LIMIT 20
                ''', (start_time.isoformat(), end_time.isoformat()))
                
                popular_actions = [dict(row) for row in cursor.fetchall()]
                
                # Feature usage
                cursor = conn.execute('''
                    SELECT 
                        feature_used,
                        COUNT(*) as count,
                        COUNT(CASE WHEN feature_success = 1 THEN 1 END) * 100.0 / COUNT(*) as success_rate
                    FROM user_behavior
                    WHERE timestamp >= ? AND timestamp <= ? AND feature_used IS NOT NULL
                    GROUP BY feature_used
                    ORDER BY count DESC
                ''', (start_time.isoformat(), end_time.isoformat()))
                
                feature_usage = [dict(row) for row in cursor.fetchall()]
                
                # User journey analysis
                cursor = conn.execute('''
                    SELECT 
                        previous_action,
                        action,
                        COUNT(*) as count
                    FROM user_behavior
                    WHERE timestamp >= ? AND timestamp <= ? AND previous_action IS NOT NULL
                    GROUP BY previous_action, action
                    ORDER BY count DESC
                    LIMIT 50
                ''', (start_time.isoformat(), end_time.isoformat()))
                
                user_journeys = [dict(row) for row in cursor.fetchall()]
                
                return {
                    'activity_stats': activity_stats,
                    'popular_actions': popular_actions,
                    'feature_usage': feature_usage,
                    'user_journeys': user_journeys,
                    'time_range': {
                        'start': start_time.isoformat(),
                        'end': end_time.isoformat()
                    }
                }
                
        except Exception as e:
            logger.error(f"Error getting user behavior summary: {e}")
            return {}
    
    def get_system_health_summary(self, start_time: datetime, end_time: datetime) -> Dict[str, Any]:
        """Get system health metrics summary"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                
                # Overall health stats
                cursor = conn.execute('''
                    SELECT 
                        AVG(cpu_usage) as avg_cpu,
                        MAX(cpu_usage) as max_cpu,
                        AVG(memory_usage) as avg_memory,
                        MAX(memory_usage) as max_memory,
                        AVG(disk_usage) as avg_disk,
                        MAX(disk_usage) as max_disk,
                        AVG(active_sessions) as avg_active_sessions,
                        MAX(active_sessions) as max_active_sessions,
                        AVG(queue_size) as avg_queue_size,
                        MAX(queue_size) as max_queue_size,
                        AVG(error_rate) as avg_error_rate,
                        MAX(error_rate) as max_error_rate,
                        AVG(response_time_avg) as avg_response_time,
                        MAX(response_time_avg) as max_response_time,
                        AVG(throughput) as avg_throughput,
                        AVG(availability) as avg_availability
                    FROM system_health
                    WHERE timestamp >= ? AND timestamp <= ?
                ''', (start_time.isoformat(), end_time.isoformat()))
                
                health_stats = dict(cursor.fetchone())
                
                # Service status distribution
                cursor = conn.execute('''
                    SELECT 
                        'ollama' as service,
                        ollama_status as status,
                        COUNT(*) as count
                    FROM system_health
                    WHERE timestamp >= ? AND timestamp <= ?
                    GROUP BY ollama_status
                    UNION ALL
                    SELECT 
                        'vector_db' as service,
                        vector_db_status as status,
                        COUNT(*) as count
                    FROM system_health
                    WHERE timestamp >= ? AND timestamp <= ?
                    GROUP BY vector_db_status
                    UNION ALL
                    SELECT 
                        'web_server' as service,
                        web_server_status as status,
                        COUNT(*) as count
                    FROM system_health
                    WHERE timestamp >= ? AND timestamp <= ?
                    GROUP BY web_server_status
                ''', (start_time.isoformat(), end_time.isoformat()) * 3)
                
                service_status = [dict(row) for row in cursor.fetchall()]
                
                return {
                    'health_stats': health_stats,
                    'service_status': service_status,
                    'time_range': {
                        'start': start_time.isoformat(),
                        'end': end_time.isoformat()
                    }
                }
                
        except Exception as e:
            logger.error(f"Error getting system health summary: {e}")
            return {}
    
    def get_time_series_data(self, metric_name: str, start_time: datetime, 
                           end_time: datetime, interval: str = "1h") -> TimeSeriesData:
        """Get time series data for a specific metric"""
        try:
            # Convert interval to seconds
            interval_seconds = self._parse_interval(interval)
            
            with sqlite3.connect(self.db_path) as conn:
                conn.row_factory = sqlite3.Row
                
                # Determine which table to query based on metric name
                if metric_name in ['duration_seconds', 'tokens_per_second', 'quality_score']:
                    table = 'processing_metrics'
                    timestamp_col = 'start_time'
                elif metric_name in ['cpu_usage', 'memory_usage', 'disk_usage', 'error_rate']:
                    table = 'system_health'
                    timestamp_col = 'timestamp'
                else:
                    # Try performance_metrics table
                    table = 'performance_metrics'
                    timestamp_col = 'timestamp'
                
                # Build query based on table
                if table == 'performance_metrics':
                    cursor = conn.execute(f'''
                        SELECT 
                            DATETIME(
                                ROUND(
                                    (JULIANDAY(timestamp) - JULIANDAY('{start_time.isoformat()}')) * 86400 / {interval_seconds}
                                ) * {interval_seconds} / 86400 + JULIANDAY('{start_time.isoformat()}')
                            ) as bucket,
                            AVG(value) as avg_value,
                            COUNT(*) as count
                        FROM {table}
                        WHERE metric_name = ? AND timestamp >= ? AND timestamp <= ?
                        GROUP BY bucket
                        ORDER BY bucket
                    ''', (metric_name, start_time.isoformat(), end_time.isoformat()))
                else:
                    cursor = conn.execute(f'''
                        SELECT 
                            DATETIME(
                                ROUND(
                                    (JULIANDAY({timestamp_col}) - JULIANDAY('{start_time.isoformat()}')) * 86400 / {interval_seconds}
                                ) * {interval_seconds} / 86400 + JULIANDAY('{start_time.isoformat()}')
                            ) as bucket,
                            AVG({metric_name}) as avg_value,
                            COUNT(*) as count
                        FROM {table}
                        WHERE {timestamp_col} >= ? AND {timestamp_col} <= ?
                        GROUP BY bucket
                        ORDER BY bucket
                    ''', (start_time.isoformat(), end_time.isoformat()))
                
                rows = cursor.fetchall()
                
                points = []
                for row in rows:
                    if row['avg_value'] is not None:
                        points.append(TimeSeriesPoint(
                            timestamp=datetime.fromisoformat(row['bucket']),
                            value=float(row['avg_value']),
                            labels={'count': str(row['count'])}
                        ))
                
                return TimeSeriesData(
                    metric_name=metric_name,
                    points=points,
                    unit=self._get_metric_unit(metric_name),
                    description=self._get_metric_description(metric_name)
                )
                
        except Exception as e:
            logger.error(f"Error getting time series data for {metric_name}: {e}")
            return TimeSeriesData(metric_name=metric_name, points=[])
    
    def get_aggregated_metrics(self, start_time: datetime, end_time: datetime) -> Dict[str, AggregatedMetric]:
        """Get aggregated metrics for all key performance indicators"""
        try:
            metrics = {}
            
            with sqlite3.connect(self.db_path) as conn:
                # Processing metrics
                cursor = conn.execute('''
                    SELECT duration_seconds FROM processing_metrics
                    WHERE start_time >= ? AND start_time <= ? AND duration_seconds IS NOT NULL
                ''', (start_time.isoformat(), end_time.isoformat()))
                
                duration_values = [row[0] for row in cursor.fetchall()]
                if duration_values:
                    metrics['processing_duration'] = AggregatedMetric.from_values(
                        'processing_duration', duration_values
                    )
                
                # Tokens per second
                cursor = conn.execute('''
                    SELECT tokens_per_second FROM processing_metrics
                    WHERE start_time >= ? AND start_time <= ? AND tokens_per_second IS NOT NULL
                ''', (start_time.isoformat(), end_time.isoformat()))
                
                tokens_values = [row[0] for row in cursor.fetchall()]
                if tokens_values:
                    metrics['tokens_per_second'] = AggregatedMetric.from_values(
                        'tokens_per_second', tokens_values
                    )
                
                # Quality scores
                cursor = conn.execute('''
                    SELECT quality_score FROM processing_metrics
                    WHERE start_time >= ? AND start_time <= ? AND quality_score IS NOT NULL
                ''', (start_time.isoformat(), end_time.isoformat()))
                
                quality_values = [row[0] for row in cursor.fetchall()]
                if quality_values:
                    metrics['quality_score'] = AggregatedMetric.from_values(
                        'quality_score', quality_values
                    )
                
                # System health metrics
                for metric_name in ['cpu_usage', 'memory_usage', 'disk_usage', 'error_rate']:
                    cursor = conn.execute(f'''
                        SELECT {metric_name} FROM system_health
                        WHERE timestamp >= ? AND timestamp <= ?
                    ''', (start_time.isoformat(), end_time.isoformat()))
                    
                    values = [row[0] for row in cursor.fetchall()]
                    if values:
                        metrics[metric_name] = AggregatedMetric.from_values(metric_name, values)
                
                return metrics
                
        except Exception as e:
            logger.error(f"Error getting aggregated metrics: {e}")
            return {}
    
    def get_trend_analysis(self, metric_name: str, days: int = 7) -> Dict[str, Any]:
        """Get trend analysis for a specific metric"""
        try:
            end_time = datetime.now()
            start_time = end_time - timedelta(days=days)
            
            # Get daily aggregated values
            time_series = self.get_time_series_data(metric_name, start_time, end_time, "1d")
            
            if len(time_series.points) < 2:
                return {
                    'trend': 'insufficient_data',
                    'change_percentage': 0.0,
                    'prediction': None,
                    'confidence': 0.0
                }
            
            values = time_series.get_values()
            
            # Calculate trend
            first_value = values[0]
            last_value = values[-1]
            change_percentage = ((last_value - first_value) / first_value) * 100 if first_value != 0 else 0
            
            # Simple trend classification
            if change_percentage > 5:
                trend = 'increasing'
            elif change_percentage < -5:
                trend = 'decreasing'
            else:
                trend = 'stable'
            
            # Simple prediction (linear extrapolation)
            if len(values) > 1:
                slope = (values[-1] - values[0]) / (len(values) - 1)
                prediction = values[-1] + slope
                confidence = min(1.0, max(0.0, 1.0 - abs(change_percentage) / 100))
            else:
                prediction = values[-1]
                confidence = 0.5
            
            return {
                'trend': trend,
                'change_percentage': change_percentage,
                'prediction': prediction,
                'confidence': confidence,
                'data_points': len(values),
                'time_range': {
                    'start': start_time.isoformat(),
                    'end': end_time.isoformat()
                }
            }
            
        except Exception as e:
            logger.error(f"Error getting trend analysis for {metric_name}: {e}")
            return {
                'trend': 'error',
                'change_percentage': 0.0,
                'prediction': None,
                'confidence': 0.0
            }
    
    def _parse_interval(self, interval: str) -> int:
        """Parse interval string to seconds"""
        if interval.endswith('s'):
            return int(interval[:-1])
        elif interval.endswith('m'):
            return int(interval[:-1]) * 60
        elif interval.endswith('h'):
            return int(interval[:-1]) * 3600
        elif interval.endswith('d'):
            return int(interval[:-1]) * 86400
        else:
            return 3600  # default to 1 hour
    
    def _get_metric_unit(self, metric_name: str) -> str:
        """Get unit for metric"""
        units = {
            'duration_seconds': 'seconds',
            'tokens_per_second': 'tokens/sec',
            'quality_score': 'score',
            'cpu_usage': 'percentage',
            'memory_usage': 'percentage',
            'disk_usage': 'percentage',
            'error_rate': 'percentage',
            'response_time_avg': 'seconds',
            'throughput': 'ops/sec',
            'availability': 'percentage'
        }
        return units.get(metric_name, '')
    
    def _get_metric_description(self, metric_name: str) -> str:
        """Get description for metric"""
        descriptions = {
            'duration_seconds': 'Processing time in seconds',
            'tokens_per_second': 'Token processing rate',
            'quality_score': 'AI processing quality score',
            'cpu_usage': 'CPU utilization percentage',
            'memory_usage': 'Memory usage percentage',
            'disk_usage': 'Disk usage percentage',
            'error_rate': 'Error rate percentage',
            'response_time_avg': 'Average response time',
            'throughput': 'System throughput',
            'availability': 'System availability percentage'
        }
        return descriptions.get(metric_name, metric_name.replace('_', ' ').title())