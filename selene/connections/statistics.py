"""
Connection Statistics and Analytics

Provides comprehensive analytics and statistics for connection patterns,
including trend analysis, quality metrics, and reporting capabilities.
"""

import json
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Tuple
from collections import Counter, defaultdict
import statistics

from .models import Connection, ConnectionType, ConnectionStatistics
from .storage import ConnectionStorage
from loguru import logger


class ConnectionStatisticsCollector:
    """Collects and analyzes statistics about connections between notes."""
    
    def __init__(self, storage: ConnectionStorage):
        """Initialize statistics collector.
        
        Args:
            storage: Connection storage instance
        """
        self.storage = storage
    
    def collect_statistics(self) -> ConnectionStatistics:
        """Collect comprehensive connection statistics.
        
        Returns:
            ConnectionStatistics object with all metrics
        """
        logger.info("Collecting connection statistics")
        
        # Get all connections
        connections = self.storage.get_connections()
        
        if not connections:
            return ConnectionStatistics()
        
        # Calculate basic metrics
        total_connections = len(connections)
        connections_by_type = self._calculate_type_distribution(connections)
        average_confidence = self._calculate_average_confidence(connections)
        confidence_distribution = self._calculate_confidence_distribution(connections)
        
        # Calculate advanced metrics
        most_connected_notes = self._find_most_connected_notes(connections)
        connection_patterns = self._analyze_connection_patterns(connections)
        
        return ConnectionStatistics(
            total_connections=total_connections,
            connections_by_type=connections_by_type,
            average_confidence=average_confidence,
            confidence_distribution=confidence_distribution,
            most_connected_notes=most_connected_notes,
            connection_patterns=connection_patterns,
            last_updated=datetime.now()
        )
    
    def _calculate_type_distribution(self, connections: List[Connection]) -> Dict[str, int]:
        """Calculate distribution of connection types."""
        type_counts = Counter(c.connection_type.value for c in connections)
        return dict(type_counts)
    
    def _calculate_average_confidence(self, connections: List[Connection]) -> float:
        """Calculate average confidence score."""
        if not connections:
            return 0.0
        
        confidences = [c.confidence for c in connections]
        return statistics.mean(confidences)
    
    def _calculate_confidence_distribution(self, connections: List[Connection]) -> Dict[str, int]:
        """Calculate distribution of confidence scores."""
        ranges = {
            '0.0-0.2': 0,
            '0.2-0.4': 0,
            '0.4-0.6': 0,
            '0.6-0.8': 0,
            '0.8-1.0': 0
        }
        
        for connection in connections:
            confidence = connection.confidence
            if confidence < 0.2:
                ranges['0.0-0.2'] += 1
            elif confidence < 0.4:
                ranges['0.2-0.4'] += 1
            elif confidence < 0.6:
                ranges['0.4-0.6'] += 1
            elif confidence < 0.8:
                ranges['0.6-0.8'] += 1
            else:
                ranges['0.8-1.0'] += 1
        
        return ranges
    
    def _find_most_connected_notes(self, connections: List[Connection]) -> List[Dict[str, Any]]:
        """Find notes with the most connections."""
        note_connections = defaultdict(int)
        
        for connection in connections:
            note_connections[connection.source_id] += 1
            note_connections[connection.target_id] += 1
        
        # Sort by connection count and return top 10
        sorted_notes = sorted(note_connections.items(), key=lambda x: x[1], reverse=True)
        
        return [
            {
                'note_id': note_id,
                'connection_count': count,
                'connection_density': count / len(connections) if connections else 0
            }
            for note_id, count in sorted_notes[:10]
        ]
    
    def _analyze_connection_patterns(self, connections: List[Connection]) -> Dict[str, Any]:
        """Analyze patterns in connections."""
        patterns = {}
        
        # Time-based patterns
        patterns['temporal_patterns'] = self._analyze_temporal_patterns(connections)
        
        # Type combination patterns
        patterns['type_combinations'] = self._analyze_type_combinations(connections)
        
        # Confidence patterns
        patterns['confidence_patterns'] = self._analyze_confidence_patterns(connections)
        
        # Quality patterns
        patterns['quality_patterns'] = self._analyze_quality_patterns(connections)
        
        return patterns
    
    def _analyze_temporal_patterns(self, connections: List[Connection]) -> Dict[str, Any]:
        """Analyze temporal patterns in connection creation."""
        if not connections:
            return {}
        
        # Group connections by creation time
        daily_counts = defaultdict(int)
        hourly_counts = defaultdict(int)
        
        for connection in connections:
            day = connection.created_at.strftime('%Y-%m-%d')
            hour = connection.created_at.hour
            
            daily_counts[day] += 1
            hourly_counts[hour] += 1
        
        # Calculate trends
        sorted_days = sorted(daily_counts.keys())
        if len(sorted_days) >= 2:
            # Simple trend calculation
            recent_days = sorted_days[-7:]  # Last 7 days
            older_days = sorted_days[-14:-7] if len(sorted_days) >= 14 else sorted_days[:-7]
            
            recent_avg = statistics.mean([daily_counts[day] for day in recent_days]) if recent_days else 0
            older_avg = statistics.mean([daily_counts[day] for day in older_days]) if older_days else 0
            
            trend = 'increasing' if recent_avg > older_avg else 'decreasing' if recent_avg < older_avg else 'stable'
        else:
            trend = 'insufficient_data'
        
        return {
            'daily_counts': dict(daily_counts),
            'hourly_distribution': dict(hourly_counts),
            'most_active_hour': max(hourly_counts, key=hourly_counts.get) if hourly_counts else None,
            'trend': trend,
            'total_days': len(daily_counts)
        }
    
    def _analyze_type_combinations(self, connections: List[Connection]) -> Dict[str, Any]:
        """Analyze combinations of connection types."""
        # Group connections by note pairs
        note_pairs = defaultdict(list)
        for connection in connections:
            # Use sorted pair to handle bidirectional connections
            pair = tuple(sorted([connection.source_id, connection.target_id]))
            note_pairs[pair].append(connection.connection_type)
        
        # Analyze type combinations
        combination_counts = defaultdict(int)
        for types in note_pairs.values():
            if len(types) > 1:
                # Sort types for consistent combination naming
                combo = tuple(sorted(t.value for t in types))
                combination_counts[combo] += 1
        
        return {
            'multi_type_pairs': len([types for types in note_pairs.values() if len(types) > 1]),
            'single_type_pairs': len([types for types in note_pairs.values() if len(types) == 1]),
            'common_combinations': dict(combination_counts),
            'average_types_per_pair': statistics.mean([len(types) for types in note_pairs.values()]) if note_pairs else 0
        }
    
    def _analyze_confidence_patterns(self, connections: List[Connection]) -> Dict[str, Any]:
        """Analyze confidence score patterns."""
        if not connections:
            return {}
        
        confidences = [c.confidence for c in connections]
        
        # Basic statistics
        confidence_stats = {
            'mean': statistics.mean(confidences),
            'median': statistics.median(confidences),
            'std_dev': statistics.stdev(confidences) if len(confidences) > 1 else 0,
            'min': min(confidences),
            'max': max(confidences),
            'range': max(confidences) - min(confidences)
        }
        
        # Confidence by type
        type_confidence = defaultdict(list)
        for connection in connections:
            type_confidence[connection.connection_type.value].append(connection.confidence)
        
        type_avg_confidence = {
            conn_type: statistics.mean(conf_list)
            for conn_type, conf_list in type_confidence.items()
        }
        
        return {
            'overall_stats': confidence_stats,
            'by_type': type_avg_confidence,
            'high_confidence_count': len([c for c in confidences if c >= 0.8]),
            'low_confidence_count': len([c for c in confidences if c < 0.5])
        }
    
    def _analyze_quality_patterns(self, connections: List[Connection]) -> Dict[str, Any]:
        """Analyze quality patterns in connections."""
        if not connections:
            return {}
        
        # Explanation quality
        explanation_lengths = [len(c.explanation) for c in connections]
        avg_explanation_length = statistics.mean(explanation_lengths)
        
        # Metadata completeness
        metadata_scores = []
        for connection in connections:
            metadata = connection.metadata
            score = 0
            if metadata.get('discovery_method'):
                score += 0.25
            if metadata.get('similarity_score') or metadata.get('reference_count'):
                score += 0.25
            if len(metadata) > 2:
                score += 0.25
            if connection.explanation and len(connection.explanation) > 20:
                score += 0.25
            metadata_scores.append(score)
        
        avg_metadata_score = statistics.mean(metadata_scores)
        
        # Connection freshness
        now = datetime.now()
        ages = [(now - c.created_at).days for c in connections]
        avg_age = statistics.mean(ages)
        
        return {
            'explanation_quality': {
                'average_length': avg_explanation_length,
                'short_explanations': len([l for l in explanation_lengths if l < 20]),
                'detailed_explanations': len([l for l in explanation_lengths if l > 50])
            },
            'metadata_completeness': {
                'average_score': avg_metadata_score,
                'well_documented': len([s for s in metadata_scores if s >= 0.75]),
                'poorly_documented': len([s for s in metadata_scores if s < 0.25])
            },
            'freshness': {
                'average_age_days': avg_age,
                'recent_connections': len([age for age in ages if age <= 7]),
                'old_connections': len([age for age in ages if age > 30])
            }
        }
    
    def generate_connection_report(self, note_id: Optional[str] = None) -> Dict[str, Any]:
        """Generate a comprehensive connection report.
        
        Args:
            note_id: Optional note ID to focus report on specific note
            
        Returns:
            Comprehensive connection report
        """
        logger.info(f"Generating connection report for {'all notes' if not note_id else note_id}")
        
        if note_id:
            return self._generate_note_specific_report(note_id)
        else:
            return self._generate_global_report()
    
    def _generate_note_specific_report(self, note_id: str) -> Dict[str, Any]:
        """Generate report focused on a specific note."""
        # Get connections for the note
        connections = self.storage.get_connections_for_note(note_id)
        summary = self.storage.get_note_connection_summary(note_id)
        
        # Analyze connection patterns for this note
        incoming = [c for c in connections if c.target_id == note_id]
        outgoing = [c for c in connections if c.source_id == note_id]
        
        # Most connected peers
        peer_counts = defaultdict(int)
        for connection in connections:
            peer_id = connection.target_id if connection.source_id == note_id else connection.source_id
            peer_counts[peer_id] += 1
        
        top_peers = sorted(peer_counts.items(), key=lambda x: x[1], reverse=True)[:5]
        
        # Connection strength analysis
        strengths = {
            'strong': len([c for c in connections if c.confidence >= 0.8]),
            'moderate': len([c for c in connections if 0.6 <= c.confidence < 0.8]),
            'weak': len([c for c in connections if c.confidence < 0.6])
        }
        
        return {
            'note_id': note_id,
            'summary': summary.to_dict(),
            'connection_details': {
                'total': len(connections),
                'incoming': len(incoming),
                'outgoing': len(outgoing),
                'bidirectional': len(incoming) + len(outgoing) - len(connections)
            },
            'strength_distribution': strengths,
            'top_connected_peers': [{'note_id': peer_id, 'connections': count} for peer_id, count in top_peers],
            'type_breakdown': dict(Counter(c.connection_type.value for c in connections)),
            'average_confidence': statistics.mean([c.confidence for c in connections]) if connections else 0,
            'recommendations': self._generate_note_recommendations(note_id, connections)
        }
    
    def _generate_global_report(self) -> Dict[str, Any]:
        """Generate global connection report."""
        stats = self.collect_statistics()
        connections = self.storage.get_connections()
        
        # Network health metrics
        network_health = self._calculate_network_health(connections)
        
        # Growth trends
        growth_trends = self._calculate_growth_trends(connections)
        
        # Quality assessment
        quality_assessment = self._assess_overall_quality(connections)
        
        return {
            'overview': {
                'total_connections': stats.total_connections,
                'average_confidence': stats.average_confidence,
                'last_updated': stats.last_updated.isoformat()
            },
            'statistics': stats.to_dict(),
            'network_health': network_health,
            'growth_trends': growth_trends,
            'quality_assessment': quality_assessment,
            'recommendations': self._generate_global_recommendations(connections)
        }
    
    def _calculate_network_health(self, connections: List[Connection]) -> Dict[str, Any]:
        """Calculate network health metrics."""
        if not connections:
            return {'health_score': 0, 'status': 'no_connections'}
        
        # Calculate various health metrics
        total_notes = len(set([c.source_id for c in connections] + [c.target_id for c in connections]))
        connection_density = len(connections) / (total_notes * (total_notes - 1) / 2) if total_notes > 1 else 0
        
        # Average confidence
        avg_confidence = statistics.mean([c.confidence for c in connections])
        
        # Type diversity
        unique_types = len(set(c.connection_type for c in connections))
        type_diversity = unique_types / len(ConnectionType)
        
        # Calculate overall health score
        health_score = (avg_confidence * 0.4 + connection_density * 0.3 + type_diversity * 0.3)
        
        # Determine status
        if health_score >= 0.8:
            status = 'excellent'
        elif health_score >= 0.6:
            status = 'good'
        elif health_score >= 0.4:
            status = 'fair'
        else:
            status = 'poor'
        
        return {
            'health_score': health_score,
            'status': status,
            'metrics': {
                'connection_density': connection_density,
                'average_confidence': avg_confidence,
                'type_diversity': type_diversity,
                'total_notes': total_notes,
                'connections_per_note': len(connections) / total_notes if total_notes > 0 else 0
            }
        }
    
    def _calculate_growth_trends(self, connections: List[Connection]) -> Dict[str, Any]:
        """Calculate growth trends for connections."""
        if not connections:
            return {'trend': 'no_data'}
        
        # Group by creation date
        daily_counts = defaultdict(int)
        for connection in connections:
            day = connection.created_at.strftime('%Y-%m-%d')
            daily_counts[day] += 1
        
        # Calculate trend over last 7 days vs previous 7 days
        sorted_days = sorted(daily_counts.keys())
        if len(sorted_days) >= 7:
            recent_days = sorted_days[-7:]
            previous_days = sorted_days[-14:-7] if len(sorted_days) >= 14 else []
            
            recent_total = sum(daily_counts[day] for day in recent_days)
            previous_total = sum(daily_counts[day] for day in previous_days) if previous_days else 0
            
            if previous_total > 0:
                growth_rate = (recent_total - previous_total) / previous_total
            else:
                growth_rate = 1.0 if recent_total > 0 else 0.0
            
            trend = 'increasing' if growth_rate > 0.1 else 'decreasing' if growth_rate < -0.1 else 'stable'
        else:
            growth_rate = 0.0
            trend = 'insufficient_data'
        
        return {
            'trend': trend,
            'growth_rate': growth_rate,
            'total_days': len(daily_counts),
            'daily_average': statistics.mean(daily_counts.values()) if daily_counts else 0
        }
    
    def _assess_overall_quality(self, connections: List[Connection]) -> Dict[str, Any]:
        """Assess overall quality of connections."""
        if not connections:
            return {'quality_score': 0, 'grade': 'F'}
        
        # Quality factors
        avg_confidence = statistics.mean([c.confidence for c in connections])
        explanation_quality = statistics.mean([min(1.0, len(c.explanation) / 50) for c in connections])
        metadata_quality = statistics.mean([min(1.0, len(c.metadata) / 3) for c in connections])
        
        # Overall quality score
        quality_score = (avg_confidence * 0.5 + explanation_quality * 0.3 + metadata_quality * 0.2)
        
        # Assign grade
        if quality_score >= 0.9:
            grade = 'A'
        elif quality_score >= 0.8:
            grade = 'B'
        elif quality_score >= 0.7:
            grade = 'C'
        elif quality_score >= 0.6:
            grade = 'D'
        else:
            grade = 'F'
        
        return {
            'quality_score': quality_score,
            'grade': grade,
            'factors': {
                'confidence': avg_confidence,
                'explanation_quality': explanation_quality,
                'metadata_quality': metadata_quality
            }
        }
    
    def _generate_note_recommendations(self, note_id: str, connections: List[Connection]) -> List[str]:
        """Generate recommendations for a specific note."""
        recommendations = []
        
        if not connections:
            recommendations.append("No connections found. Consider adding more content or running connection discovery.")
            return recommendations
        
        # Connection count recommendations
        if len(connections) < 3:
            recommendations.append("Few connections found. Consider expanding note content or creating related notes.")
        elif len(connections) > 20:
            recommendations.append("Many connections found. Consider reviewing and pruning low-confidence connections.")
        
        # Confidence recommendations
        avg_confidence = statistics.mean([c.confidence for c in connections])
        if avg_confidence < 0.5:
            recommendations.append("Low average confidence. Consider reviewing connection quality and strengthening relationships.")
        
        # Type diversity recommendations
        unique_types = len(set(c.connection_type for c in connections))
        if unique_types < 2:
            recommendations.append("Limited connection types. Consider adding more varied content to enable different connection types.")
        
        return recommendations
    
    def _generate_global_recommendations(self, connections: List[Connection]) -> List[str]:
        """Generate global recommendations for connection system."""
        recommendations = []
        
        if not connections:
            recommendations.append("No connections found. Run connection discovery to start building relationships.")
            return recommendations
        
        # Overall health recommendations
        health = self._calculate_network_health(connections)
        if health['health_score'] < 0.6:
            recommendations.append("Connection network health is below optimal. Consider improving connection quality and discovery methods.")
        
        # Growth recommendations
        growth = self._calculate_growth_trends(connections)
        if growth['trend'] == 'decreasing':
            recommendations.append("Connection growth is declining. Consider adding more content or improving discovery algorithms.")
        
        # Quality recommendations
        quality = self._assess_overall_quality(connections)
        if quality['quality_score'] < 0.7:
            recommendations.append("Connection quality could be improved. Focus on enhancing explanations and metadata.")
        
        return recommendations