// Analytics Dashboard JavaScript for Selene SMS-22
// Provides interactive charts and data visualization

class AnalyticsDashboard {
    constructor() {
        this.charts = {};
        this.refreshInterval = 30000; // 30 seconds
        this.intervalId = null;
        this.currentTimeRange = 7; // 7 days
        
        this.init();
    }

    init() {
        this.setupEventListeners();
        this.loadDashboard();
        this.startAutoRefresh();
    }

    setupEventListeners() {
        // Time range selector
        const timeRangeSelect = document.getElementById('analytics-time-range');
        if (timeRangeSelect) {
            timeRangeSelect.addEventListener('change', (e) => {
                this.currentTimeRange = parseInt(e.target.value);
                this.loadDashboard();
            });
        }

        // Refresh button
        const refreshBtn = document.getElementById('analytics-refresh');
        if (refreshBtn) {
            refreshBtn.addEventListener('click', () => this.loadDashboard());
        }

        // Export buttons
        const exportBtns = document.querySelectorAll('.export-btn');
        exportBtns.forEach(btn => {
            btn.addEventListener('click', (e) => {
                const metric = e.target.dataset.metric;
                this.exportMetric(metric);
            });
        });

        // Metric detail buttons
        const detailBtns = document.querySelectorAll('.metric-detail-btn');
        detailBtns.forEach(btn => {
            btn.addEventListener('click', (e) => {
                const metric = e.target.dataset.metric;
                this.showMetricDetails(metric);
            });
        });
    }

    async loadDashboard() {
        try {
            this.showLoading();
            
            // Load dashboard data
            const response = await fetch(`/api/analytics/dashboard?days=${this.currentTimeRange}`);
            if (!response.ok) throw new Error('Failed to load dashboard data');
            
            const data = await response.json();
            
            // Update various dashboard sections
            this.updateProcessingSummary(data.processing_summary);
            this.updateUserBehavior(data.user_behavior);
            this.updateSystemHealth(data.system_health);
            this.updateAggregatedMetrics(data.aggregated_metrics);
            
            // Load time series charts
            await this.loadTimeSeriesCharts();
            
            this.hideLoading();
            
        } catch (error) {
            console.error('Error loading dashboard:', error);
            this.showError('Failed to load analytics dashboard');
        }
    }

    updateProcessingSummary(summary) {
        const container = document.getElementById('processing-summary');
        if (!container || !summary.overall_stats) return;

        const stats = summary.overall_stats;
        
        container.innerHTML = `
            <div class="analytics-grid">
                <div class="analytics-card">
                    <div class="analytics-card-header">
                        <h4>Processing Sessions</h4>
                        <span class="trend-indicator ${this.getTrendClass(stats.success_rate)}">
                            ${stats.success_rate ? stats.success_rate.toFixed(1) : 0}%
                        </span>
                    </div>
                    <div class="analytics-card-content">
                        <div class="stat-row">
                            <span>Total Sessions:</span>
                            <span class="stat-value">${stats.total_sessions || 0}</span>
                        </div>
                        <div class="stat-row">
                            <span>Successful:</span>
                            <span class="stat-value success">${stats.successful_sessions || 0}</span>
                        </div>
                        <div class="stat-row">
                            <span>Failed:</span>
                            <span class="stat-value error">${stats.failed_sessions || 0}</span>
                        </div>
                    </div>
                </div>
                
                <div class="analytics-card">
                    <div class="analytics-card-header">
                        <h4>Performance</h4>
                    </div>
                    <div class="analytics-card-content">
                        <div class="stat-row">
                            <span>Avg Duration:</span>
                            <span class="stat-value">${this.formatDuration(stats.avg_duration)}</span>
                        </div>
                        <div class="stat-row">
                            <span>Total Tokens:</span>
                            <span class="stat-value">${this.formatNumber(stats.total_tokens)}</span>
                        </div>
                        <div class="stat-row">
                            <span>Tokens/Second:</span>
                            <span class="stat-value">${stats.avg_tokens_per_second ? stats.avg_tokens_per_second.toFixed(1) : 0}</span>
                        </div>
                    </div>
                </div>
                
                <div class="analytics-card">
                    <div class="analytics-card-header">
                        <h4>Quality</h4>
                    </div>
                    <div class="analytics-card-content">
                        <div class="stat-row">
                            <span>Avg Quality Score:</span>
                            <span class="stat-value">${stats.avg_quality_score ? stats.avg_quality_score.toFixed(2) : 'N/A'}</span>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="analytics-breakdown">
                <h4>Task Type Breakdown</h4>
                <div class="breakdown-table">
                    ${this.renderTaskBreakdown(summary.task_breakdown)}
                </div>
            </div>
        `;
    }

    updateUserBehavior(behavior) {
        const container = document.getElementById('user-behavior');
        if (!container || !behavior.activity_stats) return;

        const stats = behavior.activity_stats;
        
        container.innerHTML = `
            <div class="analytics-grid">
                <div class="analytics-card">
                    <div class="analytics-card-header">
                        <h4>User Activity</h4>
                    </div>
                    <div class="analytics-card-content">
                        <div class="stat-row">
                            <span>Unique Users:</span>
                            <span class="stat-value">${stats.unique_users || 0}</span>
                        </div>
                        <div class="stat-row">
                            <span>Sessions:</span>
                            <span class="stat-value">${stats.unique_sessions || 0}</span>
                        </div>
                        <div class="stat-row">
                            <span>Total Actions:</span>
                            <span class="stat-value">${stats.total_actions || 0}</span>
                        </div>
                    </div>
                </div>
                
                <div class="analytics-card">
                    <div class="analytics-card-header">
                        <h4>Popular Actions</h4>
                    </div>
                    <div class="analytics-card-content">
                        ${this.renderPopularActions(behavior.popular_actions)}
                    </div>
                </div>
            </div>
        `;
    }

    updateSystemHealth(health) {
        const container = document.getElementById('system-health');
        if (!container || !health.health_stats) return;

        const stats = health.health_stats;
        
        container.innerHTML = `
            <div class="analytics-grid">
                <div class="analytics-card">
                    <div class="analytics-card-header">
                        <h4>Resource Usage</h4>
                    </div>
                    <div class="analytics-card-content">
                        <div class="stat-row">
                            <span>CPU Usage:</span>
                            <span class="stat-value ${this.getHealthClass(stats.avg_cpu)}">${stats.avg_cpu ? stats.avg_cpu.toFixed(1) : 0}%</span>
                        </div>
                        <div class="stat-row">
                            <span>Memory Usage:</span>
                            <span class="stat-value ${this.getHealthClass(stats.avg_memory)}">${stats.avg_memory ? stats.avg_memory.toFixed(1) : 0}%</span>
                        </div>
                        <div class="stat-row">
                            <span>Disk Usage:</span>
                            <span class="stat-value ${this.getHealthClass(stats.avg_disk)}">${stats.avg_disk ? stats.avg_disk.toFixed(1) : 0}%</span>
                        </div>
                    </div>
                </div>
                
                <div class="analytics-card">
                    <div class="analytics-card-header">
                        <h4>System Performance</h4>
                    </div>
                    <div class="analytics-card-content">
                        <div class="stat-row">
                            <span>Avg Response Time:</span>
                            <span class="stat-value">${this.formatDuration(stats.avg_response_time)}</span>
                        </div>
                        <div class="stat-row">
                            <span>Error Rate:</span>
                            <span class="stat-value ${this.getHealthClass(stats.avg_error_rate)}">${stats.avg_error_rate ? stats.avg_error_rate.toFixed(2) : 0}%</span>
                        </div>
                        <div class="stat-row">
                            <span>Availability:</span>
                            <span class="stat-value">${stats.avg_availability ? stats.avg_availability.toFixed(2) : 100}%</span>
                        </div>
                    </div>
                </div>
            </div>
        `;
    }

    updateAggregatedMetrics(metrics) {
        const container = document.getElementById('aggregated-metrics');
        if (!container || !metrics) return;

        const metricsHtml = Object.entries(metrics).map(([name, metric]) => `
            <div class="analytics-card">
                <div class="analytics-card-header">
                    <h4>${this.formatMetricName(name)}</h4>
                    <span class="trend-indicator ${this.getTrendClass(metric.trend)}">${metric.trend}</span>
                </div>
                <div class="analytics-card-content">
                    <div class="metric-summary">
                        <div class="metric-value">${metric.mean ? metric.mean.toFixed(2) : 0}</div>
                        <div class="metric-details">
                            <span>Min: ${metric.min ? metric.min.toFixed(2) : 0}</span>
                            <span>Max: ${metric.max ? metric.max.toFixed(2) : 0}</span>
                            <span>Count: ${metric.count || 0}</span>
                        </div>
                    </div>
                    <button class="metric-detail-btn" data-metric="${name}">View Details</button>
                </div>
            </div>
        `).join('');

        container.innerHTML = `<div class="analytics-grid">${metricsHtml}</div>`;
    }

    async loadTimeSeriesCharts() {
        const chartContainer = document.getElementById('time-series-charts');
        if (!chartContainer) return;

        const metrics = [
            'duration_seconds',
            'tokens_per_second',
            'cpu_usage',
            'memory_usage',
            'error_rate'
        ];

        const chartsHtml = metrics.map(metric => `
            <div class="chart-container">
                <h4>${this.formatMetricName(metric)}</h4>
                <canvas id="chart-${metric}" width="400" height="200"></canvas>
                <button class="export-btn" data-metric="${metric}">Export CSV</button>
            </div>
        `).join('');

        chartContainer.innerHTML = chartsHtml;

        // Load chart data and render
        for (const metric of metrics) {
            try {
                const response = await fetch(`/api/analytics/timeseries/${metric}?days=${this.currentTimeRange}&interval=1h`);
                if (response.ok) {
                    const data = await response.json();
                    this.renderChart(metric, data);
                }
            } catch (error) {
                console.error(`Error loading chart for ${metric}:`, error);
            }
        }
    }

    renderChart(metricName, data) {
        const canvas = document.getElementById(`chart-${metricName}`);
        if (!canvas) return;

        const ctx = canvas.getContext('2d');
        
        // Simple line chart implementation
        // In production, you'd use Chart.js or similar
        this.drawSimpleLineChart(ctx, data, canvas.width, canvas.height);
    }

    drawSimpleLineChart(ctx, data, width, height) {
        const padding = 40;
        const chartWidth = width - 2 * padding;
        const chartHeight = height - 2 * padding;

        // Clear canvas
        ctx.clearRect(0, 0, width, height);

        if (!data.points || data.points.length === 0) {
            ctx.fillStyle = '#666';
            ctx.font = '16px Arial';
            ctx.textAlign = 'center';
            ctx.fillText('No data available', width / 2, height / 2);
            return;
        }

        const values = data.points.map(p => p.value);
        const minValue = Math.min(...values);
        const maxValue = Math.max(...values);
        const valueRange = maxValue - minValue || 1;

        // Draw axes
        ctx.strokeStyle = '#ddd';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(padding, padding);
        ctx.lineTo(padding, height - padding);
        ctx.lineTo(width - padding, height - padding);
        ctx.stroke();

        // Draw data line
        ctx.strokeStyle = '#4CAF50';
        ctx.lineWidth = 2;
        ctx.beginPath();

        data.points.forEach((point, index) => {
            const x = padding + (index / (data.points.length - 1)) * chartWidth;
            const y = height - padding - ((point.value - minValue) / valueRange) * chartHeight;

            if (index === 0) {
                ctx.moveTo(x, y);
            } else {
                ctx.lineTo(x, y);
            }
        });

        ctx.stroke();

        // Draw points
        ctx.fillStyle = '#4CAF50';
        data.points.forEach((point, index) => {
            const x = padding + (index / (data.points.length - 1)) * chartWidth;
            const y = height - padding - ((point.value - minValue) / valueRange) * chartHeight;
            
            ctx.beginPath();
            ctx.arc(x, y, 3, 0, 2 * Math.PI);
            ctx.fill();
        });

        // Add labels
        ctx.fillStyle = '#666';
        ctx.font = '12px Arial';
        ctx.textAlign = 'left';
        ctx.fillText(minValue.toFixed(2), 5, height - padding + 15);
        ctx.fillText(maxValue.toFixed(2), 5, padding);
    }

    renderTaskBreakdown(breakdown) {
        if (!breakdown || breakdown.length === 0) {
            return '<div class="no-data">No task data available</div>';
        }

        return `
            <table class="breakdown-table">
                <thead>
                    <tr>
                        <th>Task Type</th>
                        <th>Count</th>
                        <th>Avg Duration</th>
                        <th>Success Rate</th>
                    </tr>
                </thead>
                <tbody>
                    ${breakdown.map(task => `
                        <tr>
                            <td>${task.task_type}</td>
                            <td>${task.count}</td>
                            <td>${this.formatDuration(task.avg_duration)}</td>
                            <td class="${this.getHealthClass(task.success_rate)}">${task.success_rate ? task.success_rate.toFixed(1) : 0}%</td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        `;
    }

    renderPopularActions(actions) {
        if (!actions || actions.length === 0) {
            return '<div class="no-data">No action data available</div>';
        }

        return actions.slice(0, 5).map(action => `
            <div class="action-item">
                <span class="action-name">${action.action}</span>
                <span class="action-count">${action.count}</span>
            </div>
        `).join('');
    }

    async showMetricDetails(metricName) {
        try {
            const response = await fetch(`/api/analytics/trends/${metricName}?days=${this.currentTimeRange}`);
            if (!response.ok) throw new Error('Failed to load metric details');
            
            const data = await response.json();
            
            // Show modal with detailed information
            this.showMetricModal(metricName, data);
            
        } catch (error) {
            console.error('Error loading metric details:', error);
            this.showError('Failed to load metric details');
        }
    }

    showMetricModal(metricName, data) {
        const modal = document.getElementById('metric-modal');
        if (!modal) return;

        const modalContent = modal.querySelector('.modal-content');
        modalContent.innerHTML = `
            <div class="modal-header">
                <h3>${this.formatMetricName(metricName)} Details</h3>
                <button class="modal-close">&times;</button>
            </div>
            <div class="modal-body">
                <div class="metric-details">
                    <div class="detail-item">
                        <span>Trend:</span>
                        <span class="trend-indicator ${this.getTrendClass(data.trend)}">${data.trend}</span>
                    </div>
                    <div class="detail-item">
                        <span>Change:</span>
                        <span class="${this.getTrendClass(data.change_percentage)}">${data.change_percentage.toFixed(2)}%</span>
                    </div>
                    <div class="detail-item">
                        <span>Data Points:</span>
                        <span>${data.data_points}</span>
                    </div>
                    <div class="detail-item">
                        <span>Confidence:</span>
                        <span>${(data.confidence * 100).toFixed(1)}%</span>
                    </div>
                    ${data.prediction ? `
                        <div class="detail-item">
                            <span>Prediction:</span>
                            <span>${data.prediction.toFixed(2)}</span>
                        </div>
                    ` : ''}
                </div>
            </div>
        `;

        modal.style.display = 'block';

        // Close modal handlers
        modal.querySelector('.modal-close').addEventListener('click', () => {
            modal.style.display = 'none';
        });

        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                modal.style.display = 'none';
            }
        });
    }

    async exportMetric(metricName) {
        try {
            const response = await fetch(`/api/analytics/export/csv/${metricName}?days=${this.currentTimeRange}`);
            if (!response.ok) throw new Error('Failed to export metric');
            
            const blob = await response.blob();
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `${metricName}_${new Date().toISOString().split('T')[0]}.csv`;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            window.URL.revokeObjectURL(url);
            
        } catch (error) {
            console.error('Error exporting metric:', error);
            this.showError('Failed to export metric');
        }
    }

    startAutoRefresh() {
        if (this.intervalId) {
            clearInterval(this.intervalId);
        }
        
        this.intervalId = setInterval(() => {
            this.loadDashboard();
        }, this.refreshInterval);
    }

    stopAutoRefresh() {
        if (this.intervalId) {
            clearInterval(this.intervalId);
            this.intervalId = null;
        }
    }

    showLoading() {
        const loader = document.getElementById('analytics-loader');
        if (loader) loader.style.display = 'block';
    }

    hideLoading() {
        const loader = document.getElementById('analytics-loader');
        if (loader) loader.style.display = 'none';
    }

    showError(message) {
        const errorDiv = document.getElementById('analytics-error');
        if (errorDiv) {
            errorDiv.textContent = message;
            errorDiv.style.display = 'block';
            setTimeout(() => {
                errorDiv.style.display = 'none';
            }, 5000);
        }
    }

    // Utility methods
    formatDuration(seconds) {
        if (!seconds) return '0s';
        if (seconds < 60) return `${seconds.toFixed(1)}s`;
        if (seconds < 3600) return `${(seconds / 60).toFixed(1)}m`;
        return `${(seconds / 3600).toFixed(1)}h`;
    }

    formatNumber(num) {
        if (!num) return '0';
        if (num < 1000) return num.toString();
        if (num < 1000000) return `${(num / 1000).toFixed(1)}K`;
        return `${(num / 1000000).toFixed(1)}M`;
    }

    formatMetricName(name) {
        return name.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
    }

    getTrendClass(trend) {
        if (typeof trend === 'string') {
            if (trend === 'increasing') return 'trend-up';
            if (trend === 'decreasing') return 'trend-down';
            return 'trend-stable';
        }
        // For numeric values (percentages)
        if (trend > 0) return 'trend-up';
        if (trend < 0) return 'trend-down';
        return 'trend-stable';
    }

    getHealthClass(value) {
        if (!value) return 'health-good';
        if (value < 50) return 'health-good';
        if (value < 80) return 'health-warning';
        return 'health-critical';
    }
}

// Initialize dashboard when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    if (document.getElementById('analytics-dashboard')) {
        window.analyticsDashboard = new AnalyticsDashboard();
    }
});

// Export for use in other scripts
window.AnalyticsDashboard = AnalyticsDashboard;