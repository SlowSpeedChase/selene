#!/usr/bin/env python3
"""
Test script for SMS-22 Advanced Analytics System

This script tests the analytics system with sample data to ensure
all components work correctly.
"""

import asyncio
import json
import random
import time
from datetime import datetime, timedelta
from pathlib import Path
import sys
import tempfile
import os

# Add the selene package to the path
sys.path.insert(0, str(Path(__file__).parent))

from selene.analytics import (
    AnalyticsEvent,
    EventType,
    ProcessingMetrics,
    UserBehavior,
    SystemHealth,
    PerformanceMetrics,
    MetricType,
    AnalyticsCollector,
    AnalyticsAggregator
)
from selene.analytics.integrations import (
    get_analytics_integration,
    track_processing,
    track_user_action,
    track_template_usage,
    track_vector_operation
)


def create_sample_data():
    """Create sample analytics data for testing"""
    print("🔄 Creating sample analytics data...")
    
    # Create temporary database
    temp_dir = tempfile.mkdtemp()
    db_path = os.path.join(temp_dir, "test_analytics.db")
    
    collector = AnalyticsCollector(db_path=db_path)
    
    # Generate sample data over the last 7 days
    now = datetime.now()
    start_time = now - timedelta(days=7)
    
    # Sample user IDs and session IDs
    user_ids = ["user_1", "user_2", "user_3", "user_4", "user_5"]
    session_ids = [f"session_{i}" for i in range(1, 21)]
    
    # Sample processing data
    tasks = ["summarize", "enhance", "extract_insights", "questions", "classify"]
    models = ["llama3.2", "mistral", "gpt-4o-mini"]
    processors = ["ollama", "openai", "vector"]
    
    # Generate processing metrics
    for i in range(100):
        timestamp = start_time + timedelta(
            seconds=random.randint(0, int((now - start_time).total_seconds()))
        )
        
        session_id = random.choice(session_ids)
        task = random.choice(tasks)
        model = random.choice(models)
        processor = random.choice(processors)
        
        # Processing metrics
        duration = random.uniform(1.0, 30.0)
        tokens = random.randint(50, 1000)
        success = random.random() > 0.1  # 90% success rate
        
        metrics = ProcessingMetrics(
            session_id=session_id,
            task_type=task,
            model_name=model,
            processor_type=processor,
            start_time=timestamp,
            end_time=timestamp + timedelta(seconds=duration),
            duration_seconds=duration,
            tokens_processed=tokens,
            tokens_per_second=tokens / duration,
            input_size=random.randint(100, 2000),
            output_size=random.randint(150, 3000),
            success=success,
            error_message=None if success else "Sample error message",
            template_id=f"template_{random.randint(1, 5)}",
            quality_score=random.uniform(0.7, 0.95) if success else None
        )
        
        collector.collect_metric(metrics)
        
        # Corresponding analytics event
        event = AnalyticsEvent(
            timestamp=timestamp,
            event_type=EventType.PROCESSING_COMPLETE if success else EventType.PROCESSING_ERROR,
            user_id=random.choice(user_ids),
            session_id=session_id,
            data={
                "task_type": task,
                "model_name": model,
                "processor_type": processor,
                "duration": duration,
                "tokens_processed": tokens,
                "success": success
            }
        )
        
        collector.collect_event(event)
    
    # Generate user behavior data
    actions = ["process_content", "search_vector", "chat_message", "view_dashboard", "export_data"]
    
    for i in range(200):
        timestamp = start_time + timedelta(
            seconds=random.randint(0, int((now - start_time).total_seconds()))
        )
        
        user_id = random.choice(user_ids)
        session_id = random.choice(session_ids)
        action = random.choice(actions)
        
        behavior = UserBehavior(
            user_id=user_id,
            session_id=session_id,
            timestamp=timestamp,
            action=action,
            page_path=f"/{action}",
            duration_seconds=random.uniform(1.0, 60.0),
            success=random.random() > 0.05,  # 95% success rate
            context={"sample": "context"},
            feature_used=random.choice(["ai_processing", "vector_search", "chat", "analytics"]),
            feature_success=random.random() > 0.1
        )
        
        collector.collect_metric(behavior)
    
    # Generate system health data
    for i in range(50):
        timestamp = start_time + timedelta(
            seconds=random.randint(0, int((now - start_time).total_seconds()))
        )
        
        health = SystemHealth(
            timestamp=timestamp,
            cpu_usage=random.uniform(10.0, 80.0),
            memory_usage=random.uniform(20.0, 70.0),
            disk_usage=random.uniform(30.0, 50.0),
            active_sessions=random.randint(1, 10),
            queue_size=random.randint(0, 5),
            processed_files=random.randint(0, 100),
            error_rate=random.uniform(0.0, 5.0),
            response_time_avg=random.uniform(0.1, 2.0),
            ollama_status=random.choice(["online", "offline", "degraded"]),
            vector_db_status=random.choice(["online", "offline"]),
            web_server_status="online",
            throughput=random.uniform(1.0, 10.0),
            latency_p95=random.uniform(0.5, 5.0),
            availability=random.uniform(95.0, 100.0)
        )
        
        collector.collect_metric(health)
    
    # Generate performance metrics
    metric_names = ["duration_seconds", "tokens_per_second", "cpu_usage", "memory_usage", "error_rate"]
    
    for metric_name in metric_names:
        for i in range(20):
            timestamp = start_time + timedelta(
                seconds=random.randint(0, int((now - start_time).total_seconds()))
            )
            
            if metric_name == "duration_seconds":
                value = random.uniform(1.0, 30.0)
            elif metric_name == "tokens_per_second":
                value = random.uniform(10.0, 100.0)
            elif metric_name in ["cpu_usage", "memory_usage"]:
                value = random.uniform(10.0, 80.0)
            elif metric_name == "error_rate":
                value = random.uniform(0.0, 5.0)
            else:
                value = random.uniform(0.0, 100.0)
            
            perf_metric = PerformanceMetrics(
                metric_name=metric_name,
                metric_type=MetricType.GAUGE,
                value=value,
                timestamp=timestamp,
                labels={"unit": "test"},
                threshold_warning=50.0,
                threshold_critical=80.0
            )
            
            collector.collect_metric(perf_metric)
    
    print(f"✅ Sample data created in {db_path}")
    
    # Wait for background processing to complete
    time.sleep(2)
    
    return db_path


def test_analytics_aggregator(db_path):
    """Test the analytics aggregator"""
    print("🔄 Testing analytics aggregator...")
    
    aggregator = AnalyticsAggregator(db_path=db_path)
    
    # Test time ranges
    end_time = datetime.now()
    start_time = end_time - timedelta(days=7)
    
    # Test processing summary
    print("  📊 Testing processing summary...")
    processing_summary = aggregator.get_processing_summary(start_time, end_time)
    print(f"     Total sessions: {processing_summary['overall_stats']['total_sessions']}")
    print(f"     Success rate: {processing_summary['overall_stats']['success_rate']:.1f}%")
    
    # Test user behavior
    print("  👥 Testing user behavior...")
    user_behavior = aggregator.get_user_behavior_summary(start_time, end_time)
    print(f"     Unique users: {user_behavior['activity_stats']['unique_users']}")
    print(f"     Total actions: {user_behavior['activity_stats']['total_actions']}")
    
    # Test system health
    print("  🔧 Testing system health...")
    system_health = aggregator.get_system_health_summary(start_time, end_time)
    avg_cpu = system_health['health_stats']['avg_cpu']
    avg_memory = system_health['health_stats']['avg_memory']
    print(f"     Avg CPU: {avg_cpu:.1f}%" if avg_cpu else "     Avg CPU: N/A")
    print(f"     Avg Memory: {avg_memory:.1f}%" if avg_memory else "     Avg Memory: N/A")
    
    # Test aggregated metrics
    print("  📈 Testing aggregated metrics...")
    aggregated_metrics = aggregator.get_aggregated_metrics(start_time, end_time)
    print(f"     Available metrics: {list(aggregated_metrics.keys())}")
    
    # Test time series
    print("  📉 Testing time series...")
    time_series = aggregator.get_time_series_data("duration_seconds", start_time, end_time, "1h")
    print(f"     Time series points: {len(time_series.points)}")
    
    # Test trend analysis
    print("  📊 Testing trend analysis...")
    trend = aggregator.get_trend_analysis("duration_seconds", days=7)
    print(f"     Trend: {trend['trend']}")
    print(f"     Change: {trend['change_percentage']:.2f}%")
    
    print("✅ Analytics aggregator tests completed")


def test_analytics_integration():
    """Test the analytics integration"""
    print("🔄 Testing analytics integration...")
    
    integration = get_analytics_integration()
    
    # Test processing tracking
    print("  ⚙️ Testing processing tracking...")
    session_id = "test_session_123"
    integration.track_processing_session(
        session_id=session_id,
        task_type="test_task",
        model_name="test_model",
        processor_type="test_processor"
    )
    
    integration.track_processing_complete(
        session_id=session_id,
        success=True,
        duration=5.0,
        tokens_processed=100,
        quality_score=0.95
    )
    
    # Test user action tracking
    print("  👤 Testing user action tracking...")
    integration.track_user_action(
        user_id="test_user",
        session_id="test_session",
        action="test_action",
        page_path="/test",
        duration=2.0,
        success=True,
        context={"test": "context"}
    )
    
    # Test template usage tracking
    print("  📝 Testing template usage tracking...")
    integration.track_template_usage(
        template_id="test_template",
        user_id="test_user",
        session_id="test_session",
        success=True,
        execution_time=1.5
    )
    
    # Test vector operation tracking
    print("  🔍 Testing vector operation tracking...")
    integration.track_vector_operation(
        operation="search",
        collection_name="test_collection",
        document_count=5,
        execution_time=0.5,
        success=True
    )
    
    print("✅ Analytics integration tests completed")


@track_processing(task_type="test_task", model_name="test_model", processor_type="test_processor")
async def test_processing_decorator():
    """Test the processing decorator"""
    await asyncio.sleep(1)
    return "test_result"


async def test_decorators():
    """Test analytics decorators"""
    print("🔄 Testing analytics decorators...")
    
    # Test processing decorator
    print("  🎯 Testing processing decorator...")
    result = await test_processing_decorator()
    print(f"     Result: {result}")
    
    # Test user action context manager
    print("  🎯 Testing user action context manager...")
    with track_user_action("test_user", "test_session", "test_action", "/test"):
        time.sleep(0.1)  # Simulate some work
    
    print("✅ Analytics decorators tests completed")


async def main():
    """Main test function"""
    print("🚀 Starting SMS-22 Advanced Analytics System Tests")
    print("=" * 60)
    
    try:
        # Create sample data
        db_path = create_sample_data()
        
        # Test aggregator
        test_analytics_aggregator(db_path)
        
        # Test integration
        test_analytics_integration()
        
        # Test decorators
        await test_decorators()
        
        print("=" * 60)
        print("✅ All analytics tests completed successfully!")
        print(f"📊 Test database created at: {db_path}")
        print("🌐 You can now start the web interface to view the analytics dashboard")
        print("   Command: python3 -m selene.main web")
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())