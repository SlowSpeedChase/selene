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
}

class SeleneUI {
    constructor() {
        this.api = new SeleneAPI();
        this.currentTab = 'dashboard';
        this.statusInterval = null;
        
        this.init();
    }

    init() {
        this.setupTabNavigation();
        this.setupForms();
        this.setupEventListeners();
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