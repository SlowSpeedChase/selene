"""
SMS-22: Advanced Analytics System

This module provides comprehensive analytics capabilities for the Selene system,
including historical data analysis, user behavior tracking, performance monitoring,
and business intelligence dashboards.

The analytics system builds upon the existing monitoring infrastructure to provide:
- Time-series data aggregation and historical reporting
- User behavior analysis and usage patterns
- Performance optimization analytics
- Business intelligence dashboards
- Data export and integration capabilities
"""

from .models import (
    AnalyticsEvent,
    ProcessingMetrics,
    UserBehavior,
    SystemHealth,
    PerformanceMetrics,
    EventType,
    MetricType
)
from .collector import AnalyticsCollector
from .aggregator import AnalyticsAggregator

__all__ = [
    'AnalyticsEvent',
    'ProcessingMetrics',
    'UserBehavior',
    'SystemHealth',
    'PerformanceMetrics',
    'EventType',
    'MetricType',
    'AnalyticsCollector',
    'AnalyticsAggregator'
]

__version__ = '1.0.0'