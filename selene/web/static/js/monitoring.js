// Real-time LLM Processing Monitor
// Connects to WebSocket for live updates and displays processing stages

class ProcessingMonitor {
    constructor() {
        this.websocket = null;
        this.isConnected = false;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 5;
        this.reconnectDelay = 1000;
        this.activeSessions = new Map();
        this.selectedSessionId = null;
        
        this.init();
    }

    init() {
        this.setupWebSocket();
        this.setupEventListeners();
        this.setupUI();
    }

    setupWebSocket() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${protocol}//${window.location.host}/ws/monitoring`;
        
        try {
            this.websocket = new WebSocket(wsUrl);
            this.setupWebSocketEventHandlers();
        } catch (error) {
            console.error('WebSocket connection failed:', error);
            this.showConnectionError();
        }
    }

    setupWebSocketEventHandlers() {
        this.websocket.onopen = () => {
            console.log('WebSocket connected');
            this.isConnected = true;
            this.reconnectAttempts = 0;
            this.showConnectionStatus(true);
            
            // Request initial data
            this.requestStatistics();
            this.requestActiveSessions();
            this.requestRecentSessions();
        };

        this.websocket.onmessage = (event) => {
            try {
                const message = JSON.parse(event.data);
                this.handleMessage(message);
            } catch (error) {
                console.error('Failed to parse WebSocket message:', error);
            }
        };

        this.websocket.onclose = () => {
            console.log('WebSocket disconnected');
            this.isConnected = false;
            this.showConnectionStatus(false);
            this.attemptReconnect();
        };

        this.websocket.onerror = (error) => {
            console.error('WebSocket error:', error);
            this.showConnectionError();
        };
    }

    handleMessage(message) {
        const { type, data } = message;

        switch (type) {
            case 'statistics':
                this.updateStatistics(data);
                break;
            case 'active_sessions':
                this.updateActiveSessions(data);
                break;
            case 'recent_sessions':
                this.updateRecentSessions(data);
                break;
            case 'session_details':
                this.updateSessionDetails(data);
                break;
            case 'processing_event':
                this.updateProcessingEvent(data);
                break;
            case 'error':
                this.showError(message.message);
                break;
            default:
                console.log('Unknown message type:', type);
        }
    }

    updateStatistics(stats) {
        const statsContainer = document.getElementById('monitoring-stats');
        
        const html = `
            <div class="stats-grid">
                <div class="stat-item">
                    <div class="stat-value">${stats.total_sessions}</div>
                    <div class="stat-label">Total Sessions</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value">${stats.active_sessions}</div>
                    <div class="stat-label">Active Sessions</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value">${stats.completed_sessions}</div>
                    <div class="stat-label">Completed</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value">${stats.failed_sessions}</div>
                    <div class="stat-label">Failed</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value">${(stats.success_rate * 100).toFixed(1)}%</div>
                    <div class="stat-label">Success Rate</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value">${stats.avg_processing_time.toFixed(2)}s</div>
                    <div class="stat-label">Avg Time</div>
                </div>
            </div>
        `;
        
        statsContainer.innerHTML = html;
    }

    updateActiveSessions(sessions) {
        const container = document.getElementById('active-sessions');
        
        if (sessions.length === 0) {
            container.innerHTML = '<p class="text-center">No active sessions</p>';
            return;
        }
        
        let html = '<div class="session-list">';
        sessions.forEach(session => {
            this.activeSessions.set(session.session_id, session);
            html += this.renderSessionCard(session, true);
        });
        html += '</div>';
        
        container.innerHTML = html;
    }

    updateRecentSessions(sessions) {
        const container = document.getElementById('recent-sessions');
        
        if (sessions.length === 0) {
            container.innerHTML = '<p class="text-center">No recent sessions</p>';
            return;
        }
        
        let html = '<div class="session-list">';
        sessions.forEach(session => {
            html += this.renderSessionCard(session, false);
        });
        html += '</div>';
        
        container.innerHTML = html;
    }

    renderSessionCard(session, isActive) {
        const statusClass = this.getStatusClass(session.current_stage);
        const progressWidth = (session.progress * 100).toFixed(1);
        
        return `
            <div class="session-card ${isActive ? 'active' : ''}" 
                 data-session-id="${session.session_id}"
                 onclick="monitor.selectSession('${session.session_id}')">
                <div class="session-header">
                    <div class="session-title">
                        <span class="task-badge">${session.task}</span>
                        <span class="model-badge">${session.model}</span>
                    </div>
                    <div class="session-status ${statusClass}">${session.current_stage}</div>
                </div>
                <div class="session-progress">
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: ${progressWidth}%"></div>
                    </div>
                    <span class="progress-text">${progressWidth}%</span>
                </div>
                <div class="session-meta">
                    <span class="content-preview">${session.content_preview}</span>
                    <span class="elapsed-time">${session.elapsed_time.toFixed(2)}s</span>
                </div>
            </div>
        `;
    }

    updateSessionDetails(session) {
        const container = document.getElementById('session-details');
        
        let html = `
            <div class="session-detail">
                <div class="session-info">
                    <h4>Session: ${session.session_id}</h4>
                    <div class="info-grid">
                        <div class="info-item">
                            <label>Task:</label>
                            <span>${session.task}</span>
                        </div>
                        <div class="info-item">
                            <label>Model:</label>
                            <span>${session.model}</span>
                        </div>
                        <div class="info-item">
                            <label>Processor:</label>
                            <span>${session.processor_type}</span>
                        </div>
                        <div class="info-item">
                            <label>Progress:</label>
                            <span>${(session.progress * 100).toFixed(1)}%</span>
                        </div>
                        <div class="info-item">
                            <label>Status:</label>
                            <span class="${this.getStatusClass(session.current_stage)}">${session.current_stage}</span>
                        </div>
                        <div class="info-item">
                            <label>Duration:</label>
                            <span>${session.elapsed_time.toFixed(2)}s</span>
                        </div>
                    </div>
                </div>
                
                <div class="session-content">
                    <h5>Content Preview</h5>
                    <div class="content-preview">${session.content_preview}</div>
                </div>
        `;
        
        // Add streaming tokens if available
        if (session.streaming_tokens && session.streaming_tokens.length > 0) {
            html += `
                <div class="session-output">
                    <h5>Live Output</h5>
                    <div class="streaming-output">${session.streaming_tokens.join('')}</div>
                </div>
            `;
        }
        
        // Add events timeline
        html += `
            <div class="session-events">
                <h5>Processing Timeline</h5>
                <div class="events-timeline">
        `;
        
        session.events.forEach(event => {
            const timestamp = new Date(event.timestamp * 1000).toLocaleTimeString();
            html += `
                <div class="event-item ${this.getStatusClass(event.stage)}">
                    <div class="event-time">${timestamp}</div>
                    <div class="event-stage">${event.stage}</div>
                    <div class="event-message">${event.message}</div>
                    <div class="event-progress">${(event.progress * 100).toFixed(1)}%</div>
                </div>
            `;
        });
        
        html += `
                </div>
            </div>
        </div>
        `;
        
        container.innerHTML = html;
    }

    updateProcessingEvent(event) {
        // Update active session if it exists
        const session = this.activeSessions.get(event.session_id);
        if (session) {
            session.current_stage = event.stage;
            session.progress = event.progress;
            session.events.push(event);
            
            // Update UI if this is the selected session
            if (this.selectedSessionId === event.session_id) {
                this.requestSessionDetails(event.session_id);
            }
        }
        
        // Refresh active sessions display
        this.requestActiveSessions();
    }

    selectSession(sessionId) {
        this.selectedSessionId = sessionId;
        this.requestSessionDetails(sessionId);
        
        // Update UI to show selected state
        document.querySelectorAll('.session-card').forEach(card => {
            card.classList.remove('selected');
        });
        
        const selectedCard = document.querySelector(`[data-session-id="${sessionId}"]`);
        if (selectedCard) {
            selectedCard.classList.add('selected');
        }
    }

    getStatusClass(stage) {
        const stageClasses = {
            'initializing': 'status-initializing',
            'validating_input': 'status-validating',
            'resolving_template': 'status-resolving',
            'generating_prompt': 'status-generating',
            'selecting_model': 'status-selecting',
            'connecting_to_model': 'status-connecting',
            'sending_request': 'status-sending',
            'streaming_response': 'status-streaming',
            'processing_response': 'status-processing',
            'collecting_metadata': 'status-collecting',
            'finalizing_result': 'status-finalizing',
            'completed': 'status-completed',
            'failed': 'status-failed'
        };
        
        return stageClasses[stage] || 'status-unknown';
    }

    // WebSocket request methods
    requestStatistics() {
        this.sendMessage({ type: 'get_statistics' });
    }

    requestActiveSessions() {
        this.sendMessage({ type: 'get_active_sessions' });
    }

    requestRecentSessions(limit = 10) {
        this.sendMessage({ type: 'get_recent_sessions', limit });
    }

    requestSessionDetails(sessionId) {
        this.sendMessage({ type: 'get_session', session_id: sessionId });
    }

    sendMessage(message) {
        if (this.websocket && this.websocket.readyState === WebSocket.OPEN) {
            this.websocket.send(JSON.stringify(message));
        }
    }

    // UI Setup and Event Handlers
    setupEventListeners() {
        // Refresh button
        document.addEventListener('click', (e) => {
            if (e.target.classList.contains('refresh-monitoring')) {
                this.requestStatistics();
                this.requestActiveSessions();
                this.requestRecentSessions();
            }
        });
        
        // Tab switching
        document.addEventListener('click', (e) => {
            if (e.target.closest('.nav-tab[data-tab="monitoring"]')) {
                this.onTabActivated();
            }
        });
    }

    setupUI() {
        // Add refresh button to monitoring tab
        const monitoringTab = document.getElementById('monitoring-tab');
        if (monitoringTab) {
            const refreshButton = document.createElement('button');
            refreshButton.className = 'btn btn-secondary refresh-monitoring';
            refreshButton.innerHTML = '<i class="fas fa-sync-alt"></i> Refresh';
            refreshButton.style.position = 'absolute';
            refreshButton.style.top = '10px';
            refreshButton.style.right = '10px';
            
            monitoringTab.style.position = 'relative';
            monitoringTab.appendChild(refreshButton);
        }
    }

    onTabActivated() {
        // Refresh data when monitoring tab is activated
        setTimeout(() => {
            this.requestStatistics();
            this.requestActiveSessions();
            this.requestRecentSessions();
        }, 100);
    }

    // Connection Management
    attemptReconnect() {
        if (this.reconnectAttempts < this.maxReconnectAttempts) {
            this.reconnectAttempts++;
            console.log(`Attempting to reconnect (${this.reconnectAttempts}/${this.maxReconnectAttempts})...`);
            
            setTimeout(() => {
                this.setupWebSocket();
            }, this.reconnectDelay * this.reconnectAttempts);
        } else {
            console.error('Max reconnection attempts reached');
            this.showConnectionError();
        }
    }

    showConnectionStatus(connected) {
        const statusIndicator = document.getElementById('connection-status');
        if (statusIndicator) {
            statusIndicator.textContent = connected ? 'Connected' : 'Disconnected';
            statusIndicator.className = connected ? 'connected' : 'disconnected';
        }
    }

    showConnectionError() {
        const container = document.getElementById('monitoring-stats');
        if (container) {
            container.innerHTML = `
                <div class="error-message">
                    <i class="fas fa-exclamation-triangle"></i>
                    <p>WebSocket connection failed. Real-time monitoring unavailable.</p>
                    <button class="btn btn-primary" onclick="monitor.setupWebSocket()">
                        Try Again
                    </button>
                </div>
            `;
        }
    }

    showError(message) {
        console.error('Monitor error:', message);
        // Could show user-friendly error messages here
    }

    // Cleanup
    destroy() {
        if (this.websocket) {
            this.websocket.close();
        }
    }
}

// Initialize monitor when page loads
let monitor;

document.addEventListener('DOMContentLoaded', () => {
    monitor = new ProcessingMonitor();
});

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    if (monitor) {
        monitor.destroy();
    }
});

// Export for use in other scripts
window.ProcessingMonitor = ProcessingMonitor;