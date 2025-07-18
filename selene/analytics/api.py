"""
SMS-22: Analytics REST API

FastAPI endpoints for analytics data retrieval and visualization.
Integrates with existing web interface to provide comprehensive analytics.
"""

from fastapi import APIRouter, HTTPException, Query, Depends
from pydantic import BaseModel, Field
from typing import Dict, List, Optional, Any
from datetime import datetime, timedelta
import logging
from pathlib import Path

from .collector import AnalyticsCollector, get_analytics_collector
from .aggregator import AnalyticsAggregator, TimeSeriesData, AggregatedMetric
from .models import AnalyticsEvent, EventType, AnalyticsQuery


logger = logging.getLogger(__name__)


# Pydantic models for API responses
class AnalyticsEventResponse(BaseModel):
    """Analytics event response model"""
    id: str
    timestamp: datetime
    event_type: str
    user_id: Optional[str] = None
    session_id: Optional[str] = None
    data: Dict[str, Any] = {}
    metadata: Dict[str, Any] = {}


class TimeSeriesPointResponse(BaseModel):
    """Time series point response model"""
    timestamp: datetime
    value: float
    labels: Dict[str, str] = {}


class TimeSeriesResponse(BaseModel):
    """Time series response model"""
    metric_name: str
    points: List[TimeSeriesPointResponse]
    unit: str = ""
    description: str = ""


class AggregatedMetricResponse(BaseModel):
    """Aggregated metric response model"""
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
    trend: str


class ProcessingSummaryResponse(BaseModel):
    """Processing summary response model"""
    overall_stats: Dict[str, Any]
    task_breakdown: List[Dict[str, Any]]
    model_performance: List[Dict[str, Any]]
    processor_stats: List[Dict[str, Any]]
    time_range: Dict[str, str]


class UserBehaviorResponse(BaseModel):
    """User behavior response model"""
    activity_stats: Dict[str, Any]
    popular_actions: List[Dict[str, Any]]
    feature_usage: List[Dict[str, Any]]
    user_journeys: List[Dict[str, Any]]
    time_range: Dict[str, str]


class SystemHealthResponse(BaseModel):
    """System health response model"""
    health_stats: Dict[str, Any]
    service_status: List[Dict[str, Any]]
    time_range: Dict[str, str]


class TrendAnalysisResponse(BaseModel):
    """Trend analysis response model"""
    trend: str
    change_percentage: float
    prediction: Optional[float] = None
    confidence: float
    data_points: int = 0
    time_range: Dict[str, str]


class AnalyticsStatsResponse(BaseModel):
    """Analytics database statistics response model"""
    analytics_events_count: int
    processing_metrics_count: int
    user_behavior_count: int
    system_health_count: int
    performance_metrics_count: int
    database_size_bytes: int


# Create router
analytics_router = APIRouter(prefix="/api/analytics", tags=["analytics"])


def get_analytics_aggregator() -> AnalyticsAggregator:
    """Get analytics aggregator instance"""
    return AnalyticsAggregator()


def parse_time_range(
    start_time: Optional[str] = None,
    end_time: Optional[str] = None,
    days: int = 7
) -> tuple[datetime, datetime]:
    """Parse time range parameters"""
    if end_time:
        end_dt = datetime.fromisoformat(end_time.replace('Z', '+00:00'))
    else:
        end_dt = datetime.now()
    
    if start_time:
        start_dt = datetime.fromisoformat(start_time.replace('Z', '+00:00'))
    else:
        start_dt = end_dt - timedelta(days=days)
    
    return start_dt, end_dt


@analytics_router.get("/events", response_model=List[AnalyticsEventResponse])
async def get_analytics_events(
    start_time: Optional[str] = Query(None, description="Start time in ISO format"),
    end_time: Optional[str] = Query(None, description="End time in ISO format"),
    event_type: Optional[str] = Query(None, description="Filter by event type"),
    user_id: Optional[str] = Query(None, description="Filter by user ID"),
    session_id: Optional[str] = Query(None, description="Filter by session ID"),
    limit: int = Query(100, ge=1, le=1000, description="Maximum number of events"),
    offset: int = Query(0, ge=0, description="Offset for pagination"),
    collector: AnalyticsCollector = Depends(get_analytics_collector)
):
    """Get analytics events with optional filtering"""
    try:
        start_dt, end_dt = parse_time_range(start_time, end_time)
        
        # Build query
        query = AnalyticsQuery(
            start_time=start_dt,
            end_time=end_dt,
            limit=limit,
            offset=offset
        )
        
        if event_type:
            query.event_types = [EventType(event_type)]
        
        if user_id:
            query.filters['user_id'] = user_id
        
        if session_id:
            query.filters['session_id'] = session_id
        
        # Get events
        events = collector.query_events(query)
        
        # Convert to response format
        return [
            AnalyticsEventResponse(
                id=event.id,
                timestamp=event.timestamp,
                event_type=event.event_type.value,
                user_id=event.user_id,
                session_id=event.session_id,
                data=event.data,
                metadata=event.metadata
            )
            for event in events
        ]
        
    except Exception as e:
        logger.error(f"Error getting analytics events: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@analytics_router.get("/processing/summary", response_model=ProcessingSummaryResponse)
async def get_processing_summary(
    start_time: Optional[str] = Query(None, description="Start time in ISO format"),
    end_time: Optional[str] = Query(None, description="End time in ISO format"),
    days: int = Query(7, ge=1, le=90, description="Number of days if no specific times provided"),
    aggregator: AnalyticsAggregator = Depends(get_analytics_aggregator)
):
    """Get processing metrics summary"""
    try:
        start_dt, end_dt = parse_time_range(start_time, end_time, days)
        
        summary = aggregator.get_processing_summary(start_dt, end_dt)
        
        return ProcessingSummaryResponse(**summary)
        
    except Exception as e:
        logger.error(f"Error getting processing summary: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@analytics_router.get("/user-behavior", response_model=UserBehaviorResponse)
async def get_user_behavior(
    start_time: Optional[str] = Query(None, description="Start time in ISO format"),
    end_time: Optional[str] = Query(None, description="End time in ISO format"),
    days: int = Query(7, ge=1, le=90, description="Number of days if no specific times provided"),
    aggregator: AnalyticsAggregator = Depends(get_analytics_aggregator)
):
    """Get user behavior analysis"""
    try:
        start_dt, end_dt = parse_time_range(start_time, end_time, days)
        
        behavior = aggregator.get_user_behavior_summary(start_dt, end_dt)
        
        return UserBehaviorResponse(**behavior)
        
    except Exception as e:
        logger.error(f"Error getting user behavior: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@analytics_router.get("/system-health", response_model=SystemHealthResponse)
async def get_system_health(
    start_time: Optional[str] = Query(None, description="Start time in ISO format"),
    end_time: Optional[str] = Query(None, description="End time in ISO format"),
    days: int = Query(7, ge=1, le=90, description="Number of days if no specific times provided"),
    aggregator: AnalyticsAggregator = Depends(get_analytics_aggregator)
):
    """Get system health metrics"""
    try:
        start_dt, end_dt = parse_time_range(start_time, end_time, days)
        
        health = aggregator.get_system_health_summary(start_dt, end_dt)
        
        return SystemHealthResponse(**health)
        
    except Exception as e:
        logger.error(f"Error getting system health: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@analytics_router.get("/timeseries/{metric_name}", response_model=TimeSeriesResponse)
async def get_time_series(
    metric_name: str,
    start_time: Optional[str] = Query(None, description="Start time in ISO format"),
    end_time: Optional[str] = Query(None, description="End time in ISO format"),
    days: int = Query(7, ge=1, le=90, description="Number of days if no specific times provided"),
    interval: str = Query("1h", description="Time interval (1m, 1h, 1d)"),
    aggregator: AnalyticsAggregator = Depends(get_analytics_aggregator)
):
    """Get time series data for a specific metric"""
    try:
        start_dt, end_dt = parse_time_range(start_time, end_time, days)
        
        time_series = aggregator.get_time_series_data(metric_name, start_dt, end_dt, interval)
        
        return TimeSeriesResponse(
            metric_name=time_series.metric_name,
            points=[
                TimeSeriesPointResponse(
                    timestamp=point.timestamp,
                    value=point.value,
                    labels=point.labels
                )
                for point in time_series.points
            ],
            unit=time_series.unit,
            description=time_series.description
        )
        
    except Exception as e:
        logger.error(f"Error getting time series for {metric_name}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@analytics_router.get("/metrics/aggregated", response_model=Dict[str, AggregatedMetricResponse])
async def get_aggregated_metrics(
    start_time: Optional[str] = Query(None, description="Start time in ISO format"),
    end_time: Optional[str] = Query(None, description="End time in ISO format"),
    days: int = Query(7, ge=1, le=90, description="Number of days if no specific times provided"),
    aggregator: AnalyticsAggregator = Depends(get_analytics_aggregator)
):
    """Get aggregated metrics for all key performance indicators"""
    try:
        start_dt, end_dt = parse_time_range(start_time, end_time, days)
        
        metrics = aggregator.get_aggregated_metrics(start_dt, end_dt)
        
        return {
            name: AggregatedMetricResponse(
                metric_name=metric.metric_name,
                count=metric.count,
                sum=metric.sum,
                mean=metric.mean,
                median=metric.median,
                min=metric.min,
                max=metric.max,
                std_dev=metric.std_dev,
                percentile_95=metric.percentile_95,
                percentile_99=metric.percentile_99,
                trend=metric.trend
            )
            for name, metric in metrics.items()
        }
        
    except Exception as e:
        logger.error(f"Error getting aggregated metrics: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@analytics_router.get("/trends/{metric_name}", response_model=TrendAnalysisResponse)
async def get_trend_analysis(
    metric_name: str,
    days: int = Query(7, ge=1, le=90, description="Number of days for trend analysis"),
    aggregator: AnalyticsAggregator = Depends(get_analytics_aggregator)
):
    """Get trend analysis for a specific metric"""
    try:
        analysis = aggregator.get_trend_analysis(metric_name, days)
        
        return TrendAnalysisResponse(**analysis)
        
    except Exception as e:
        logger.error(f"Error getting trend analysis for {metric_name}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@analytics_router.get("/stats", response_model=AnalyticsStatsResponse)
async def get_analytics_stats(
    collector: AnalyticsCollector = Depends(get_analytics_collector)
):
    """Get analytics database statistics"""
    try:
        stats = collector.get_database_stats()
        
        return AnalyticsStatsResponse(
            analytics_events_count=stats.get('analytics_events_count', 0),
            processing_metrics_count=stats.get('processing_metrics_count', 0),
            user_behavior_count=stats.get('user_behavior_count', 0),
            system_health_count=stats.get('system_health_count', 0),
            performance_metrics_count=stats.get('performance_metrics_count', 0),
            database_size_bytes=stats.get('database_size_bytes', 0)
        )
        
    except Exception as e:
        logger.error(f"Error getting analytics stats: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@analytics_router.post("/cleanup")
async def cleanup_analytics_data(
    days_to_keep: int = Query(30, ge=1, le=365, description="Number of days to keep"),
    collector: AnalyticsCollector = Depends(get_analytics_collector)
):
    """Clean up old analytics data"""
    try:
        collector.cleanup_old_data(days_to_keep)
        
        return {"message": f"Cleanup completed. Kept data from last {days_to_keep} days."}
        
    except Exception as e:
        logger.error(f"Error cleaning up analytics data: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@analytics_router.get("/export/csv/{metric_name}")
async def export_metric_csv(
    metric_name: str,
    start_time: Optional[str] = Query(None, description="Start time in ISO format"),
    end_time: Optional[str] = Query(None, description="End time in ISO format"),
    days: int = Query(7, ge=1, le=90, description="Number of days if no specific times provided"),
    aggregator: AnalyticsAggregator = Depends(get_analytics_aggregator)
):
    """Export metric data as CSV"""
    try:
        from fastapi.responses import StreamingResponse
        import io
        import csv
        
        start_dt, end_dt = parse_time_range(start_time, end_time, days)
        
        time_series = aggregator.get_time_series_data(metric_name, start_dt, end_dt, "1h")
        
        # Create CSV in memory
        output = io.StringIO()
        writer = csv.writer(output)
        
        # Write header
        writer.writerow(['timestamp', 'value', 'labels'])
        
        # Write data
        for point in time_series.points:
            writer.writerow([
                point.timestamp.isoformat(),
                point.value,
                ','.join([f"{k}={v}" for k, v in point.labels.items()])
            ])
        
        output.seek(0)
        
        # Return as streaming response
        return StreamingResponse(
            io.StringIO(output.getvalue()),
            media_type="text/csv",
            headers={"Content-Disposition": f"attachment; filename={metric_name}_{start_dt.strftime('%Y%m%d')}_{end_dt.strftime('%Y%m%d')}.csv"}
        )
        
    except Exception as e:
        logger.error(f"Error exporting CSV for {metric_name}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@analytics_router.get("/dashboard")
async def get_analytics_dashboard(
    days: int = Query(7, ge=1, le=90, description="Number of days for dashboard data"),
    aggregator: AnalyticsAggregator = Depends(get_analytics_aggregator)
):
    """Get comprehensive analytics dashboard data"""
    try:
        end_dt = datetime.now()
        start_dt = end_dt - timedelta(days=days)
        
        # Get all dashboard data
        dashboard_data = {
            'processing_summary': aggregator.get_processing_summary(start_dt, end_dt),
            'user_behavior': aggregator.get_user_behavior_summary(start_dt, end_dt),
            'system_health': aggregator.get_system_health_summary(start_dt, end_dt),
            'aggregated_metrics': aggregator.get_aggregated_metrics(start_dt, end_dt),
            'time_range': {
                'start': start_dt.isoformat(),
                'end': end_dt.isoformat(),
                'days': days
            }
        }
        
        # Convert aggregated metrics to dict format
        dashboard_data['aggregated_metrics'] = {
            name: {
                'metric_name': metric.metric_name,
                'count': metric.count,
                'mean': metric.mean,
                'median': metric.median,
                'min': metric.min,
                'max': metric.max,
                'std_dev': metric.std_dev,
                'trend': metric.trend
            }
            for name, metric in dashboard_data['aggregated_metrics'].items()
        }
        
        return dashboard_data
        
    except Exception as e:
        logger.error(f"Error getting analytics dashboard: {e}")
        raise HTTPException(status_code=500, detail=str(e))