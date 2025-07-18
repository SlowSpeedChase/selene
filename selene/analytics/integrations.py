"""
SMS-22: Analytics Integrations

Integration hooks for existing Selene systems to collect analytics data.
These integrations are designed to be minimally invasive and optional.
"""

import asyncio
from datetime import datetime
from typing import Dict, List, Optional, Any, Callable
from functools import wraps
import logging
import traceback
import time
import psutil
import threading
from contextlib import contextmanager

from .models import (
    AnalyticsEvent,
    EventType,
    ProcessingMetrics,
    UserBehavior,
    SystemHealth,
    PerformanceMetrics,
    MetricType
)
from .collector import get_analytics_collector


logger = logging.getLogger(__name__)


class AnalyticsIntegration:
    """
    Main integration class that provides hooks for analytics collection.
    
    This class is designed to be singleton and thread-safe.
    """
    
    _instance = None
    _lock = threading.Lock()
    
    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
        return cls._instance
    
    def __init__(self):
        if hasattr(self, '_initialized'):
            return
        
        self._initialized = True
        self.collector = get_analytics_collector()
        self.enabled = True
        self.system_health_interval = 60  # 1 minute
        self.last_system_health_check = 0
        
        # System health monitoring thread
        self.health_thread = None
        self.stop_health_monitoring = threading.Event()
        self.start_system_health_monitoring()
    
    def start_system_health_monitoring(self):
        """Start system health monitoring thread"""
        if self.health_thread is None or not self.health_thread.is_alive():
            self.stop_health_monitoring.clear()
            self.health_thread = threading.Thread(target=self._health_monitoring_worker)
            self.health_thread.daemon = True
            self.health_thread.start()
            logger.info("System health monitoring started")
    
    def stop_system_health_monitoring(self):
        """Stop system health monitoring thread"""
        self.stop_health_monitoring.set()
        if self.health_thread and self.health_thread.is_alive():
            self.health_thread.join(timeout=5)
            logger.info("System health monitoring stopped")
    
    def _health_monitoring_worker(self):
        """Worker thread for system health monitoring"""
        while not self.stop_health_monitoring.is_set():
            try:
                self.collect_system_health()
                time.sleep(self.system_health_interval)
            except Exception as e:
                logger.error(f"Error in health monitoring: {e}")
                time.sleep(self.system_health_interval)
    
    def collect_system_health(self):
        """Collect current system health metrics"""
        try:
            # Get system metrics
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            
            # Get process-specific metrics
            process = psutil.Process()
            process_memory = process.memory_info()
            
            # Create system health metric
            health = SystemHealth(
                timestamp=datetime.now(),
                cpu_usage=cpu_percent,
                memory_usage=memory.percent,
                disk_usage=disk.percent,
                active_sessions=0,  # Will be updated by other integrations
                queue_size=0,  # Will be updated by other integrations
                processed_files=0,  # Will be updated by other integrations
                error_rate=0.0,  # Will be calculated from events
                response_time_avg=0.0,  # Will be calculated from events
                ollama_status="unknown",
                vector_db_status="unknown", 
                web_server_status="unknown",
                throughput=0.0,
                latency_p95=0.0,
                availability=100.0
            )
            
            self.collector.collect_metric(health)
            
            # Also collect performance metrics
            self.collector.collect_metric(PerformanceMetrics(
                metric_name="cpu_usage",
                metric_type=MetricType.GAUGE,
                value=cpu_percent,
                timestamp=datetime.now(),
                labels={"unit": "percentage"},
                threshold_warning=80.0,
                threshold_critical=90.0
            ))
            
            self.collector.collect_metric(PerformanceMetrics(
                metric_name="memory_usage",
                metric_type=MetricType.GAUGE,
                value=memory.percent,
                timestamp=datetime.now(),
                labels={"unit": "percentage"},
                threshold_warning=80.0,
                threshold_critical=90.0
            ))
            
        except Exception as e:
            logger.error(f"Error collecting system health: {e}")
    
    def track_processing_session(self, session_id: str, task_type: str, 
                                model_name: str, processor_type: str):
        """Track a processing session start"""
        if not self.enabled:
            return
        
        try:
            # Create analytics event
            event = AnalyticsEvent(
                event_type=EventType.PROCESSING_START,
                session_id=session_id,
                data={
                    "task_type": task_type,
                    "model_name": model_name,
                    "processor_type": processor_type
                }
            )
            self.collector.collect_event(event)
            
            # Create processing metrics entry
            metrics = ProcessingMetrics(
                session_id=session_id,
                task_type=task_type,
                model_name=model_name,
                processor_type=processor_type,
                start_time=datetime.now()
            )
            self.collector.collect_metric(metrics)
            
        except Exception as e:
            logger.error(f"Error tracking processing session: {e}")
    
    def track_processing_complete(self, session_id: str, success: bool, 
                                 duration: float, tokens_processed: Optional[int] = None,
                                 quality_score: Optional[float] = None,
                                 error_message: Optional[str] = None):
        """Track processing session completion"""
        if not self.enabled:
            return
        
        try:
            # Create analytics event
            event = AnalyticsEvent(
                event_type=EventType.PROCESSING_COMPLETE if success else EventType.PROCESSING_ERROR,
                session_id=session_id,
                data={
                    "success": success,
                    "duration": duration,
                    "tokens_processed": tokens_processed,
                    "quality_score": quality_score,
                    "error_message": error_message
                }
            )
            self.collector.collect_event(event)
            
            # Update processing metrics
            end_time = datetime.now()
            tokens_per_second = tokens_processed / duration if tokens_processed and duration > 0 else None
            
            metrics = ProcessingMetrics(
                session_id=session_id,
                task_type="unknown",  # Will be updated by lookup
                model_name="unknown",  # Will be updated by lookup
                processor_type="unknown",  # Will be updated by lookup
                start_time=end_time,  # Will be updated by lookup
                end_time=end_time,
                duration_seconds=duration,
                tokens_processed=tokens_processed,
                tokens_per_second=tokens_per_second,
                success=success,
                error_message=error_message,
                quality_score=quality_score
            )
            self.collector.collect_metric(metrics)
            
        except Exception as e:
            logger.error(f"Error tracking processing completion: {e}")
    
    def track_user_action(self, user_id: str, session_id: str, action: str,
                         page_path: Optional[str] = None, duration: Optional[float] = None,
                         success: bool = True, context: Optional[Dict] = None):
        """Track user action"""
        if not self.enabled:
            return
        
        try:
            # Create analytics event
            event = AnalyticsEvent(
                event_type=EventType.USER_ACTION,
                user_id=user_id,
                session_id=session_id,
                data={
                    "action": action,
                    "page_path": page_path,
                    "duration": duration,
                    "success": success,
                    "context": context or {}
                }
            )
            self.collector.collect_event(event)
            
            # Create user behavior metric
            behavior = UserBehavior(
                user_id=user_id,
                session_id=session_id,
                timestamp=datetime.now(),
                action=action,
                page_path=page_path,
                duration_seconds=duration,
                success=success,
                context=context or {}
            )
            self.collector.collect_metric(behavior)
            
        except Exception as e:
            logger.error(f"Error tracking user action: {e}")
    
    def track_template_usage(self, template_id: str, user_id: Optional[str] = None,
                           session_id: Optional[str] = None, success: bool = True,
                           execution_time: Optional[float] = None):
        """Track template usage"""
        if not self.enabled:
            return
        
        try:
            event = AnalyticsEvent(
                event_type=EventType.TEMPLATE_USAGE,
                user_id=user_id,
                session_id=session_id,
                data={
                    "template_id": template_id,
                    "success": success,
                    "execution_time": execution_time
                }
            )
            self.collector.collect_event(event)
            
        except Exception as e:
            logger.error(f"Error tracking template usage: {e}")
    
    def track_vector_operation(self, operation: str, collection_name: str,
                             document_count: Optional[int] = None,
                             execution_time: Optional[float] = None,
                             success: bool = True):
        """Track vector database operation"""
        if not self.enabled:
            return
        
        try:
            event = AnalyticsEvent(
                event_type=EventType.VECTOR_OPERATION,
                data={
                    "operation": operation,
                    "collection_name": collection_name,
                    "document_count": document_count,
                    "execution_time": execution_time,
                    "success": success
                }
            )
            self.collector.collect_event(event)
            
        except Exception as e:
            logger.error(f"Error tracking vector operation: {e}")
    
    def track_chat_interaction(self, user_id: str, session_id: str, 
                             message_type: str, success: bool = True,
                             response_time: Optional[float] = None):
        """Track chat interaction"""
        if not self.enabled:
            return
        
        try:
            event = AnalyticsEvent(
                event_type=EventType.CHAT_INTERACTION,
                user_id=user_id,
                session_id=session_id,
                data={
                    "message_type": message_type,
                    "success": success,
                    "response_time": response_time
                }
            )
            self.collector.collect_event(event)
            
        except Exception as e:
            logger.error(f"Error tracking chat interaction: {e}")
    
    def track_web_request(self, method: str, path: str, status_code: int,
                         response_time: float, user_id: Optional[str] = None):
        """Track web request"""
        if not self.enabled:
            return
        
        try:
            event = AnalyticsEvent(
                event_type=EventType.WEB_REQUEST,
                user_id=user_id,
                data={
                    "method": method,
                    "path": path,
                    "status_code": status_code,
                    "response_time": response_time
                }
            )
            self.collector.collect_event(event)
            
        except Exception as e:
            logger.error(f"Error tracking web request: {e}")


# Global integration instance
_analytics_integration = None


def get_analytics_integration() -> AnalyticsIntegration:
    """Get the global analytics integration instance"""
    global _analytics_integration
    if _analytics_integration is None:
        _analytics_integration = AnalyticsIntegration()
    return _analytics_integration


# Decorator for tracking processing functions
def track_processing(task_type: str, model_name: str = "unknown", 
                    processor_type: str = "unknown"):
    """Decorator to track processing function calls"""
    def decorator(func):
        @wraps(func)
        async def async_wrapper(*args, **kwargs):
            integration = get_analytics_integration()
            session_id = f"proc_{int(time.time() * 1000)}"
            
            # Track session start
            integration.track_processing_session(
                session_id=session_id,
                task_type=task_type,
                model_name=model_name,
                processor_type=processor_type
            )
            
            start_time = time.time()
            try:
                result = await func(*args, **kwargs)
                duration = time.time() - start_time
                
                # Track successful completion
                integration.track_processing_complete(
                    session_id=session_id,
                    success=True,
                    duration=duration
                )
                
                return result
                
            except Exception as e:
                duration = time.time() - start_time
                
                # Track error
                integration.track_processing_complete(
                    session_id=session_id,
                    success=False,
                    duration=duration,
                    error_message=str(e)
                )
                
                raise
        
        @wraps(func)
        def sync_wrapper(*args, **kwargs):
            integration = get_analytics_integration()
            session_id = f"proc_{int(time.time() * 1000)}"
            
            # Track session start
            integration.track_processing_session(
                session_id=session_id,
                task_type=task_type,
                model_name=model_name,
                processor_type=processor_type
            )
            
            start_time = time.time()
            try:
                result = func(*args, **kwargs)
                duration = time.time() - start_time
                
                # Track successful completion
                integration.track_processing_complete(
                    session_id=session_id,
                    success=True,
                    duration=duration
                )
                
                return result
                
            except Exception as e:
                duration = time.time() - start_time
                
                # Track error
                integration.track_processing_complete(
                    session_id=session_id,
                    success=False,
                    duration=duration,
                    error_message=str(e)
                )
                
                raise
        
        if asyncio.iscoroutinefunction(func):
            return async_wrapper
        else:
            return sync_wrapper
    
    return decorator


# Context manager for tracking user actions
@contextmanager
def track_user_action(user_id: str, session_id: str, action: str,
                     page_path: Optional[str] = None, context: Optional[Dict] = None):
    """Context manager for tracking user actions with timing"""
    integration = get_analytics_integration()
    start_time = time.time()
    success = True
    
    try:
        yield
    except Exception as e:
        success = False
        raise
    finally:
        duration = time.time() - start_time
        integration.track_user_action(
            user_id=user_id,
            session_id=session_id,
            action=action,
            page_path=page_path,
            duration=duration,
            success=success,
            context=context
        )


# Convenience functions for common tracking scenarios
def track_template_usage(template_id: str, user_id: Optional[str] = None,
                        session_id: Optional[str] = None, success: bool = True,
                        execution_time: Optional[float] = None):
    """Track template usage"""
    integration = get_analytics_integration()
    integration.track_template_usage(
        template_id=template_id,
        user_id=user_id,
        session_id=session_id,
        success=success,
        execution_time=execution_time
    )


def track_vector_operation(operation: str, collection_name: str,
                          document_count: Optional[int] = None,
                          execution_time: Optional[float] = None,
                          success: bool = True):
    """Track vector database operation"""
    integration = get_analytics_integration()
    integration.track_vector_operation(
        operation=operation,
        collection_name=collection_name,
        document_count=document_count,
        execution_time=execution_time,
        success=success
    )


def track_chat_interaction(user_id: str, session_id: str, 
                          message_type: str, success: bool = True,
                          response_time: Optional[float] = None):
    """Track chat interaction"""
    integration = get_analytics_integration()
    integration.track_chat_interaction(
        user_id=user_id,
        session_id=session_id,
        message_type=message_type,
        success=success,
        response_time=response_time
    )


def track_web_request(method: str, path: str, status_code: int,
                     response_time: float, user_id: Optional[str] = None):
    """Track web request"""
    integration = get_analytics_integration()
    integration.track_web_request(
        method=method,
        path=path,
        status_code=status_code,
        response_time=response_time,
        user_id=user_id
    )


# Cleanup function
def cleanup_analytics():
    """Cleanup analytics integration"""
    global _analytics_integration
    if _analytics_integration:
        _analytics_integration.stop_system_health_monitoring()
        _analytics_integration = None