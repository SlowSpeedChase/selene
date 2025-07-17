// Selene Second Brain Processing System - Web UI JavaScript

class SeleneAPI {
    constructor() {
        this.baseURL = '';
    }

    async request(endpoint, options = {}) {
        try {
            const response = await fetch(`${this.baseURL}/api${endpoint}`, {
                headers: {
                    'Content-Type': 'application/json',
                    ...options.headers
                },
                ...options
            });

            if (!response.ok) {
                const error = await response.json();
                throw new Error(error.detail || `HTTP ${response.status}`);
            }

            return await response.json();
        } catch (error) {
            console.error('API request failed:', error);
            throw error;
        }
    }

    // Content processing
    async processContent(data) {
        return this.request('/process', {
            method: 'POST',
            body: JSON.stringify(data)
        });
    }

    // Vector search
    async searchVector(query, nResults = 5) {
        return this.request('/vector/search', {
            method: 'POST',
            body: JSON.stringify({
                query: query,
                n_results: nResults
            })
        });
    }

    // Monitor status
    async getMonitorStatus() {
        return this.request('/monitor/status');
    }

    async startMonitoring() {
        return this.request('/monitor/start', { method: 'POST' });
    }

    async stopMonitoring() {
        return this.request('/monitor/stop', { method: 'POST' });
    }

    // Configuration
    async getConfiguration() {
        return this.request('/monitor/config');
    }

    async addDirectory(data) {
        return this.request('/monitor/add-directory', {
            method: 'POST',
            body: JSON.stringify(data)
        });
    }

    async removeDirectory(path) {
        return this.request('/monitor/remove-directory', {
            method: 'POST',
            body: JSON.stringify({ path: path })
        });
    }

    // Chat API methods
    async createChatSession(data) {
        return this.request('/chat/sessions', {
            method: 'POST',
            body: JSON.stringify(data)
        });
    }

    async getChatSessions() {
        return this.request('/chat/sessions');
    }

    async getChatSession(sessionId) {
        return this.request(`/chat/sessions/${sessionId}`);
    }

    async deleteChatSession(sessionId) {
        return this.request(`/chat/sessions/${sessionId}`, {
            method: 'DELETE'
        });
    }

    async getChatHistory(sessionId) {
        return this.request(`/chat/sessions/${sessionId}/history`);
    }

    async sendChatMessage(sessionId, message) {
        return this.request(`/chat/sessions/${sessionId}/message`, {
            method: 'POST',
            body: JSON.stringify({ message })
        });
    }
}

class SeleneUI {
    constructor() {
        this.api = new SeleneAPI();
        this.currentTab = 'dashboard';
        this.statusInterval = null;
        
        // Chat state
        this.currentSession = null;
        this.chatWebSocket = null;
        this.chatSessions = [];
        
        this.init();
    }

    init() {
        this.setupTabNavigation();
        this.setupForms();
        this.setupEventListeners();
        this.setupChatInterface();
        this.loadDashboard();
        this.startStatusPolling();
    }

    setupTabNavigation() {
        const tabs = document.querySelectorAll('.nav-tab');
        const tabContents = document.querySelectorAll('.tab-content');

        tabs.forEach(tab => {
            tab.addEventListener('click', () => {
                const tabName = tab.dataset.tab;
                
                // Update active tab
                tabs.forEach(t => t.classList.remove('active'));
                tab.classList.add('active');

                // Show corresponding content
                tabContents.forEach(content => {
                    content.classList.add('hidden');
                    if (content.id === `${tabName}-tab`) {
                        content.classList.remove('hidden');
                    }
                });

                this.currentTab = tabName;
                this.loadTabContent(tabName);
            });
        });
    }

    setupForms() {
        // Input method toggle
        document.getElementById('input-method').addEventListener('change', (e) => {
            const contentGroup = document.getElementById('content-group');
            const fileGroup = document.getElementById('file-group');
            
            if (e.target.value === 'content') {
                contentGroup.classList.remove('hidden');
                fileGroup.classList.add('hidden');
            } else {
                contentGroup.classList.add('hidden');
                fileGroup.classList.remove('hidden');
            }
        });

        // Process form
        document.getElementById('process-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            await this.handleProcessContent();
        });

        // Search form
        document.getElementById('search-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            await this.handleVectorSearch();
        });

        // Add directory form
        document.getElementById('add-directory-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            await this.handleAddDirectory();
        });
    }

    setupEventListeners() {
        // Monitor control buttons
        document.getElementById('start-monitor').addEventListener('click', async () => {
            await this.handleStartMonitoring();
        });

        document.getElementById('stop-monitor').addEventListener('click', async () => {
            await this.handleStopMonitoring();
        });
    }

    async loadTabContent(tabName) {
        switch (tabName) {
            case 'dashboard':
                await this.loadDashboard();
                break;
            case 'chat':
                await this.loadChatSessions();
                break;
            case 'monitor':
                await this.loadMonitorStatus();
                break;
            case 'config':
                await this.loadConfiguration();
                break;
        }
    }

    async loadDashboard() {
        try {
            const status = await this.api.getMonitorStatus();
            
            // Update stats
            document.getElementById('monitor-status').textContent = 
                status.is_watching ? 'Active' : 'Inactive';
            document.getElementById('watched-dirs').textContent = status.watched_directories;
            document.getElementById('queue-size').textContent = 
                status.queue_status.queue_size || 0;
            document.getElementById('processed-files').textContent = 
                status.statistics.total_processed || 0;

            // Update system status
            const systemStatus = document.getElementById('system-status');
            systemStatus.innerHTML = `
                <div class="status ${status.is_watching ? 'status-online' : 'status-offline'}">
                    <div class="status-dot"></div>
                    File Monitor: ${status.is_watching ? 'Running' : 'Stopped'}
                </div>
                ${status.watched_paths.length > 0 ? `
                    <div class="mt-2">
                        <strong>Watched Paths:</strong>
                        <ul>
                            ${status.watched_paths.map(path => `<li>${path}</li>`).join('')}
                        </ul>
                    </div>
                ` : ''}
            `;
        } catch (error) {
            this.showError('Failed to load dashboard: ' + error.message);
        }
    }

    async loadMonitorStatus() {
        try {
            const status = await this.api.getMonitorStatus();
            const config = await this.api.getConfiguration();
            
            // Update monitor status display
            const statusDisplay = document.getElementById('monitor-status-display');
            statusDisplay.innerHTML = `
                <div class="status ${status.is_watching ? 'status-online' : 'status-offline'} mb-2">
                    <div class="status-dot"></div>
                    ${status.is_watching ? 'Monitoring Active' : 'Monitoring Inactive'}
                </div>
                <p><strong>Watched Directories:</strong> ${status.watched_directories}</p>
                <p><strong>Queue Size:</strong> ${status.queue_status.queue_size || 0}</p>
                <p><strong>Files Processed:</strong> ${status.statistics.total_processed || 0}</p>
            `;

            // Update directories list
            const directoriesList = document.getElementById('watched-directories-list');
            if (config.watched_directories.length > 0) {
                directoriesList.innerHTML = config.watched_directories.map(dir => `
                    <div class="result-item">
                        <div class="result-meta">
                            <span><strong>${dir.path}</strong></span>
                            <button class="btn btn-danger" onclick="ui.removeDirectory('${dir.path}')">
                                <i class="fas fa-trash"></i>
                            </button>
                        </div>
                        <div class="result-content">
                            <p><strong>Patterns:</strong> ${dir.patterns.join(', ')}</p>
                            <p><strong>Tasks:</strong> ${dir.processing_tasks.join(', ')}</p>
                            <p><strong>Recursive:</strong> ${dir.recursive ? 'Yes' : 'No'}</p>
                        </div>
                    </div>
                `).join('');
            } else {
                directoriesList.innerHTML = '<p class="text-center">No directories configured</p>';
            }
        } catch (error) {
            this.showError('Failed to load monitor status: ' + error.message);
        }
    }

    async loadConfiguration() {
        try {
            const config = await this.api.getConfiguration();
            
            const configDisplay = document.getElementById('current-config');
            configDisplay.innerHTML = `
                <div class="result-item">
                    <h4>System Configuration</h4>
                    <p><strong>Processing Enabled:</strong> ${config.processing_enabled ? 'Yes' : 'No'}</p>
                    <p><strong>Default Processor:</strong> ${config.default_processor}</p>
                    <p><strong>Max Concurrent Jobs:</strong> ${config.max_concurrent_jobs}</p>
                    <p><strong>Batch Size:</strong> ${config.batch_size}</p>
                </div>
                
                <div class="result-item">
                    <h4>Watched Directories (${config.watched_directories.length})</h4>
                    ${config.watched_directories.length > 0 ? 
                        config.watched_directories.map(dir => `
                            <div class="mb-2">
                                <strong>${dir.path}</strong><br>
                                <small>Patterns: ${dir.patterns.join(', ')}</small><br>
                                <small>Tasks: ${dir.processing_tasks.join(', ')}</small>
                            </div>
                        `).join('') : 
                        '<p>No directories configured</p>'
                    }
                </div>
            `;
        } catch (error) {
            this.showError('Failed to load configuration: ' + error.message);
        }
    }

    async handleProcessContent() {
        const inputMethod = document.getElementById('input-method').value;
        const content = document.getElementById('content-input').value;
        const filePath = document.getElementById('file-input').value;
        const task = document.getElementById('task-select').value;
        const processor = document.getElementById('processor-select').value;
        const model = document.getElementById('model-select').value;

        if (inputMethod === 'content' && !content) {
            this.showError('Please enter content to process');
            return;
        }

        if (inputMethod === 'file' && !filePath) {
            this.showError('Please enter a file path');
            return;
        }

        const resultDiv = document.getElementById('process-result');
        const outputDiv = document.getElementById('process-output');
        
        resultDiv.classList.remove('hidden');
        outputDiv.innerHTML = '<div class="loading"><div class="spinner"></div>Processing...</div>';

        try {
            const requestData = {
                task: task,
                processor: processor,
                model: model
            };

            if (inputMethod === 'content') {
                requestData.content = content;
            } else {
                requestData.file_path = filePath;
            }

            const result = await this.api.processContent(requestData);

            if (result.success) {
                outputDiv.innerHTML = `
                    <div class="alert alert-success">
                        <strong>Processing completed in ${result.processing_time.toFixed(2)}s</strong>
                    </div>
                    <div class="result-item">
                        <div class="result-meta">
                            <span>Task: ${task}</span>
                            <span>Processor: ${processor}</span>
                            <span>Model: ${model}</span>
                        </div>
                        <div class="result-content">
                            ${result.content.replace(/\n/g, '<br>')}
                        </div>
                    </div>
                `;
                this.showSuccess('Content processed successfully!');
            } else {
                throw new Error(result.error);
            }
        } catch (error) {
            outputDiv.innerHTML = `
                <div class="alert alert-error">
                    <strong>Processing failed:</strong> ${error.message}
                </div>
            `;
            this.showError('Processing failed: ' + error.message);
        }
    }

    async handleVectorSearch() {
        const query = document.getElementById('search-query').value;
        const nResults = parseInt(document.getElementById('search-results').value);

        if (!query) {
            this.showError('Please enter a search query');
            return;
        }

        const resultsContainer = document.getElementById('search-results-container');
        const resultsList = document.getElementById('search-results-list');
        
        resultsContainer.classList.remove('hidden');
        resultsList.innerHTML = '<div class="loading"><div class="spinner"></div>Searching...</div>';

        try {
            const result = await this.api.searchVector(query, nResults);

            if (result.success && result.results.length > 0) {
                resultsList.innerHTML = result.results.map((item, index) => `
                    <div class="result-item">
                        <div class="result-meta">
                            <span>Rank #${item.rank || index + 1}</span>
                            <span>Score: ${(item.similarity_score || 0).toFixed(3)}</span>
                            <span>ID: ${item.document_id}</span>
                        </div>
                        <div class="result-content">
                            ${item.content_preview || item.content || 'No preview available'}
                        </div>
                    </div>
                `).join('');
                this.showSuccess(`Found ${result.results.length} results`);
            } else {
                resultsList.innerHTML = '<p class="text-center">No results found</p>';
            }
        } catch (error) {
            resultsList.innerHTML = `
                <div class="alert alert-error">
                    <strong>Search failed:</strong> ${error.message}
                </div>
            `;
            this.showError('Search failed: ' + error.message);
        }
    }

    async handleAddDirectory() {
        const path = document.getElementById('directory-path').value;
        const patterns = document.getElementById('file-patterns').value.split(',').map(p => p.trim());
        const recursive = document.getElementById('recursive-watch').checked;
        const autoProcess = document.getElementById('auto-process').checked;
        const storeVector = document.getElementById('store-vector').checked;

        // Get selected tasks
        const taskCheckboxes = document.querySelectorAll('#add-directory-form input[type="checkbox"][value]');
        const tasks = Array.from(taskCheckboxes)
            .filter(cb => cb.checked)
            .map(cb => cb.value);

        if (!path) {
            this.showError('Please enter a directory path');
            return;
        }

        if (tasks.length === 0) {
            this.showError('Please select at least one processing task');
            return;
        }

        try {
            const result = await this.api.addDirectory({
                path: path,
                patterns: patterns,
                recursive: recursive,
                auto_process: autoProcess,
                processing_tasks: tasks,
                store_in_vector_db: storeVector
            });

            if (result.success) {
                this.showSuccess(result.message);
                // Reset form
                document.getElementById('add-directory-form').reset();
                document.getElementById('file-patterns').value = '*.txt,*.md,*.pdf';
                // Reload configuration
                await this.loadConfiguration();
            } else {
                throw new Error(result.message);
            }
        } catch (error) {
            this.showError('Failed to add directory: ' + error.message);
        }
    }

    async handleStartMonitoring() {
        try {
            const result = await this.api.startMonitoring();
            this.showSuccess(result.message);
            await this.loadMonitorStatus();
        } catch (error) {
            this.showError('Failed to start monitoring: ' + error.message);
        }
    }

    async handleStopMonitoring() {
        try {
            const result = await this.api.stopMonitoring();
            this.showSuccess(result.message);
            await this.loadMonitorStatus();
        } catch (error) {
            this.showError('Failed to stop monitoring: ' + error.message);
        }
    }

    async removeDirectory(path) {
        if (confirm(`Remove directory "${path}" from monitoring?`)) {
            try {
                const result = await this.api.removeDirectory(path);
                this.showSuccess(result.message);
                await this.loadMonitorStatus();
                await this.loadConfiguration();
            } catch (error) {
                this.showError('Failed to remove directory: ' + error.message);
            }
        }
    }

    startStatusPolling() {
        // Poll status every 30 seconds
        this.statusInterval = setInterval(async () => {
            if (this.currentTab === 'dashboard') {
                await this.loadDashboard();
            }
        }, 30000);
    }

    // Chat Interface Methods
    setupChatInterface() {
        // New session button
        document.getElementById('new-chat-session').addEventListener('click', async () => {
            await this.createNewSession();
        });

        // Chat form submission
        document.getElementById('chat-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            await this.sendMessage();
        });

        // Chat input auto-resize and enter key handling
        const chatInput = document.getElementById('chat-input');
        chatInput.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                this.sendMessage();
            }
        });

        chatInput.addEventListener('input', (e) => {
            this.autoResizeTextarea(e.target);
        });

        // Disconnect button
        document.getElementById('chat-disconnect').addEventListener('click', () => {
            this.disconnectFromSession();
        });

        // Clear history button
        document.getElementById('chat-clear-history').addEventListener('click', () => {
            this.clearChatHistory();
        });
    }

    async loadChatSessions() {
        try {
            const response = await this.api.getChatSessions();
            this.chatSessions = response.sessions;
            this.renderChatSessions();
        } catch (error) {
            this.showError('Failed to load chat sessions: ' + error.message);
        }
    }

    renderChatSessions() {
        const container = document.getElementById('chat-sessions-list');
        
        if (this.chatSessions.length === 0) {
            container.innerHTML = '<div class="text-center" style="padding: 2rem; color: #6b7280;">No chat sessions yet. Create one to get started!</div>';
            return;
        }

        container.innerHTML = this.chatSessions.map(session => `
            <div class="chat-session-item ${session.session_id === this.currentSession?.session_id ? 'active' : ''}" 
                 data-session-id="${session.session_id}">
                <div class="chat-session-name">${session.session_name}</div>
                <div class="chat-session-meta">
                    ${session.vault_path ? `📁 ${session.vault_path}` : '📝 No vault'} • 
                    ${new Date(session.created_at).toLocaleDateString()}
                </div>
            </div>
        `).join('');

        // Add click handlers
        container.querySelectorAll('.chat-session-item').forEach(item => {
            item.addEventListener('click', () => {
                const sessionId = item.dataset.sessionId;
                this.connectToSession(sessionId);
            });
        });
    }

    async createNewSession() {
        const vaultPath = document.getElementById('chat-vault-path').value.trim();
        const sessionName = document.getElementById('chat-session-name').value.trim() || 'New Session';
        const enableMemory = document.getElementById('chat-enable-memory').checked;
        const debugMode = document.getElementById('chat-debug-mode').checked;

        try {
            const session = await this.api.createChatSession({
                vault_path: vaultPath || null,
                session_name: sessionName,
                enable_memory: enableMemory,
                debug_mode: debugMode
            });

            await this.loadChatSessions();
            await this.connectToSession(session.session_id);
            
            // Clear form
            document.getElementById('chat-vault-path').value = '';
            document.getElementById('chat-session-name').value = '';
            
            this.showSuccess(`Created session: ${session.session_name}`);
        } catch (error) {
            this.showError('Failed to create session: ' + error.message);
        }
    }

    async connectToSession(sessionId) {
        if (this.chatWebSocket) {
            this.chatWebSocket.close();
        }

        try {
            const session = await this.api.getChatSession(sessionId);
            this.currentSession = session;

            // Update UI
            document.getElementById('current-session-name').textContent = session.session_name;
            document.getElementById('current-session-status').textContent = 'Connecting...';
            document.getElementById('current-session-status').className = 'status-indicator connecting';

            // Enable chat controls
            document.getElementById('chat-input').disabled = false;
            document.getElementById('chat-send').disabled = false;
            document.getElementById('chat-disconnect').disabled = false;
            document.getElementById('chat-clear-history').disabled = false;

            // Connect WebSocket
            const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            const wsUrl = `${wsProtocol}//${window.location.host}/ws/chat/${sessionId}`;
            
            this.chatWebSocket = new WebSocket(wsUrl);
            
            this.chatWebSocket.onopen = () => {
                document.getElementById('current-session-status').textContent = 'Connected';
                document.getElementById('current-session-status').className = 'status-indicator connected';
                this.showSuccess(`Connected to ${session.session_name}`);
            };

            this.chatWebSocket.onmessage = (event) => {
                const data = JSON.parse(event.data);
                this.handleWebSocketMessage(data);
            };

            this.chatWebSocket.onclose = () => {
                document.getElementById('current-session-status').textContent = 'Disconnected';
                document.getElementById('current-session-status').className = 'status-indicator disconnected';
            };

            this.chatWebSocket.onerror = (error) => {
                this.showError('WebSocket error: ' + error.message);
            };

            // Load chat history
            await this.loadChatHistory(sessionId);

            // Update session list
            this.renderChatSessions();

        } catch (error) {
            this.showError('Failed to connect to session: ' + error.message);
        }
    }

    async loadChatHistory(sessionId) {
        try {
            const history = await this.api.getChatHistory(sessionId);
            this.renderChatMessages(history.messages);
        } catch (error) {
            console.error('Failed to load chat history:', error);
        }
    }

    renderChatMessages(messages) {
        const container = document.getElementById('chat-messages');
        
        if (messages.length === 0) {
            container.innerHTML = `
                <div class="chat-welcome">
                    <div class="chat-welcome-icon">💬</div>
                    <h4>Start your conversation</h4>
                    <p>Ask me about your notes, or try commands like:</p>
                    <ul style="text-align: left; display: inline-block; margin-top: 1rem;">
                        <li>"list my notes"</li>
                        <li>"search for machine learning"</li>
                        <li>"summarize my meeting notes"</li>
                    </ul>
                </div>
            `;
            return;
        }

        container.innerHTML = messages.map(msg => this.renderChatMessage(msg)).join('');
        this.scrollToBottom();
    }

    renderChatMessage(message) {
        const timestamp = new Date(message.timestamp).toLocaleTimeString();
        const avatarText = message.message_type === 'user' ? 'U' : 'AI';
        
        return `
            <div class="chat-message ${message.message_type}">
                <div class="message-avatar ${message.message_type}">${avatarText}</div>
                <div class="message-content">
                    ${this.formatMessageContent(message.content)}
                    <div class="message-meta">${timestamp}</div>
                </div>
            </div>
        `;
    }

    formatMessageContent(content) {
        // Basic formatting for better readability
        return content
            .replace(/\n/g, '<br>')
            .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
            .replace(/\*(.*?)\*/g, '<em>$1</em>')
            .replace(/`(.*?)`/g, '<code>$1</code>');
    }

    async sendMessage() {
        const input = document.getElementById('chat-input');
        const message = input.value.trim();
        
        if (!message || !this.currentSession) return;

        try {
            // Clear input
            input.value = '';
            this.autoResizeTextarea(input);

            // Add user message to UI immediately
            this.addMessageToUI({
                message_id: Date.now().toString(),
                content: message,
                timestamp: new Date().toISOString(),
                message_type: 'user'
            });

            // Show typing indicator
            this.showTypingIndicator();

            // Send via WebSocket
            if (this.chatWebSocket && this.chatWebSocket.readyState === WebSocket.OPEN) {
                this.chatWebSocket.send(JSON.stringify({
                    type: 'message',
                    message: message
                }));
            } else {
                throw new Error('Not connected to chat session');
            }

        } catch (error) {
            this.hideTypingIndicator();
            this.showError('Failed to send message: ' + error.message);
        }
    }

    addMessageToUI(message) {
        const container = document.getElementById('chat-messages');
        
        // Remove welcome message if it exists
        const welcome = container.querySelector('.chat-welcome');
        if (welcome) {
            welcome.remove();
        }

        container.insertAdjacentHTML('beforeend', this.renderChatMessage(message));
        this.scrollToBottom();
    }

    handleWebSocketMessage(data) {
        switch (data.type) {
            case 'message':
                this.hideTypingIndicator();
                this.addMessageToUI(data.data);
                break;
            case 'error':
                this.hideTypingIndicator();
                this.addMessageToUI({
                    message_id: Date.now().toString(),
                    content: data.message,
                    timestamp: new Date().toISOString(),
                    message_type: 'error'
                });
                break;
            case 'connected':
                console.log('Chat connected:', data.message);
                break;
            case 'session_info':
                console.log('Session info:', data.data);
                break;
        }
    }

    showTypingIndicator() {
        document.getElementById('chat-typing-indicator').innerHTML = 
            '<span class="typing-indicator">AI is typing...</span>';
    }

    hideTypingIndicator() {
        document.getElementById('chat-typing-indicator').innerHTML = '';
    }

    disconnectFromSession() {
        if (this.chatWebSocket) {
            this.chatWebSocket.close();
        }

        this.currentSession = null;
        
        // Update UI
        document.getElementById('current-session-name').textContent = 'No Session Selected';
        document.getElementById('current-session-status').textContent = 'Disconnected';
        document.getElementById('current-session-status').className = 'status-indicator disconnected';
        
        // Disable chat controls
        document.getElementById('chat-input').disabled = true;
        document.getElementById('chat-send').disabled = true;
        document.getElementById('chat-disconnect').disabled = true;
        document.getElementById('chat-clear-history').disabled = true;

        // Clear messages
        document.getElementById('chat-messages').innerHTML = `
            <div class="chat-welcome">
                <div class="chat-welcome-icon">🤖</div>
                <h4>Welcome to SELENE Chat Assistant</h4>
                <p>Create a new session or select an existing one to start chatting with your vault.</p>
                <p>Your AI assistant can help you read, write, search, and organize your notes.</p>
            </div>
        `;

        // Update session list
        this.renderChatSessions();
    }

    clearChatHistory() {
        if (confirm('Clear all messages in this chat session?')) {
            document.getElementById('chat-messages').innerHTML = `
                <div class="chat-welcome">
                    <div class="chat-welcome-icon">💬</div>
                    <h4>Chat history cleared</h4>
                    <p>Start a new conversation!</p>
                </div>
            `;
        }
    }

    autoResizeTextarea(textarea) {
        textarea.style.height = 'auto';
        textarea.style.height = Math.min(textarea.scrollHeight, 120) + 'px';
    }

    scrollToBottom() {
        const container = document.getElementById('chat-messages');
        container.scrollTop = container.scrollHeight;
    }

    showMessage(message, type = 'info') {
        const container = document.getElementById('message-container');
        const messageDiv = document.createElement('div');
        messageDiv.className = `alert alert-${type}`;
        messageDiv.innerHTML = message;
        
        container.appendChild(messageDiv);
        
        // Auto-remove after 5 seconds
        setTimeout(() => {
            if (messageDiv.parentNode) {
                messageDiv.parentNode.removeChild(messageDiv);
            }
        }, 5000);
    }

    showSuccess(message) {
        this.showMessage(message, 'success');
    }

    showError(message) {
        this.showMessage(message, 'error');
    }
}

// Initialize the UI when page loads
let ui;
document.addEventListener('DOMContentLoaded', () => {
    ui = new SeleneUI();
});