// Mobile-specific functionality for Selene PWA

class MobileApp {
    constructor() {
        this.isOnline = navigator.onLine;
        this.offlineQueue = [];
        this.isInstalled = false;
        this.deferredPrompt = null;
        
        this.init();
    }

    init() {
        this.setupPWA();
        this.setupVoiceInput();
        this.setupOfflineHandling();
        this.setupMobileUI();
        this.setupNotifications();
        this.setupGestures();
    }

    // PWA Installation and Service Worker
    setupPWA() {
        // Register service worker
        if ('serviceWorker' in navigator) {
            navigator.serviceWorker.register('/static/sw.js')
                .then(registration => {
                    console.log('SW registered:', registration);
                    this.serviceWorkerRegistration = registration;
                    
                    // Check for updates
                    registration.addEventListener('updatefound', () => {
                        const newWorker = registration.installing;
                        newWorker.addEventListener('statechange', () => {
                            if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
                                this.showUpdateNotification();
                            }
                        });
                    });
                })
                .catch(error => console.error('SW registration failed:', error));
        }

        // Handle install prompt
        window.addEventListener('beforeinstallprompt', (e) => {
            e.preventDefault();
            this.deferredPrompt = e;
            this.showInstallButton();
        });

        // Handle app installation
        window.addEventListener('appinstalled', () => {
            console.log('PWA installed');
            this.isInstalled = true;
            this.hideInstallButton();
            this.showNotification('App installed successfully!', 'success');
        });

        // Listen for messages from service worker
        navigator.serviceWorker.addEventListener('message', (event) => {
            if (event.data.type === 'OFFLINE_PROCESSING_COMPLETE') {
                this.showNotification('Offline processing completed!', 'success');
                this.refreshResults();
            }
        });
    }

    // Voice Input functionality
    setupVoiceInput() {
        if (!('webkitSpeechRecognition' in window) && !('SpeechRecognition' in window)) {
            console.log('Speech recognition not supported');
            return;
        }

        const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
        this.recognition = new SpeechRecognition();
        this.recognition.continuous = false;
        this.recognition.interimResults = false;
        this.recognition.lang = 'en-US';

        this.recognition.onresult = (event) => {
            const transcript = event.results[0][0].transcript;
            this.handleVoiceInput(transcript);
        };

        this.recognition.onerror = (event) => {
            console.error('Speech recognition error:', event.error);
            this.showNotification('Voice recognition failed', 'error');
        };

        this.recognition.onend = () => {
            this.updateVoiceButton(false);
        };

        this.addVoiceButton();
    }

    // Offline functionality
    setupOfflineHandling() {
        window.addEventListener('online', () => {
            this.isOnline = true;
            this.updateConnectionStatus();
            this.processOfflineQueue();
        });

        window.addEventListener('offline', () => {
            this.isOnline = false;
            this.updateConnectionStatus();
        });

        this.updateConnectionStatus();
    }

    // Mobile UI enhancements
    setupMobileUI() {
        // Add mobile-specific CSS classes
        document.body.classList.add('mobile-optimized');
        
        // Mobile navigation
        this.setupMobileNavigation();
        
        // Touch-friendly forms
        this.setupMobileForms();
        
        // Responsive layout adjustments
        this.setupResponsiveLayout();
        
        // Add pull-to-refresh
        this.setupPullToRefresh();
    }

    // Push notifications
    setupNotifications() {
        if ('Notification' in window) {
            if (Notification.permission === 'default') {
                // Don't ask immediately, wait for user interaction
                this.addNotificationButton();
            }
        }
    }

    // Touch gestures
    setupGestures() {
        let touchStartX = 0;
        let touchStartY = 0;
        let touchEndX = 0;
        let touchEndY = 0;

        document.addEventListener('touchstart', (e) => {
            touchStartX = e.changedTouches[0].screenX;
            touchStartY = e.changedTouches[0].screenY;
        });

        document.addEventListener('touchend', (e) => {
            touchEndX = e.changedTouches[0].screenX;
            touchEndY = e.changedTouches[0].screenY;
            this.handleGesture(touchStartX, touchStartY, touchEndX, touchEndY);
        });
    }

    // Voice input handling
    addVoiceButton() {
        const processTab = document.getElementById('process-tab');
        const contentGroup = document.getElementById('content-group');
        
        const voiceButton = document.createElement('button');
        voiceButton.type = 'button';
        voiceButton.className = 'btn btn-voice';
        voiceButton.innerHTML = '<i class="fas fa-microphone"></i>';
        voiceButton.title = 'Voice Input';
        voiceButton.addEventListener('click', () => this.startVoiceInput());
        
        contentGroup.appendChild(voiceButton);
    }

    startVoiceInput() {
        if (!this.recognition) return;
        
        this.updateVoiceButton(true);
        this.recognition.start();
        this.showNotification('Listening...', 'info');
    }

    updateVoiceButton(listening) {
        const voiceButton = document.querySelector('.btn-voice');
        if (voiceButton) {
            voiceButton.classList.toggle('listening', listening);
            voiceButton.innerHTML = listening ? 
                '<i class="fas fa-stop"></i>' : 
                '<i class="fas fa-microphone"></i>';
        }
    }

    handleVoiceInput(transcript) {
        const contentInput = document.getElementById('content-input');
        if (contentInput) {
            contentInput.value = transcript;
            this.showNotification('Voice input captured', 'success');
        }
    }

    // Mobile navigation
    setupMobileNavigation() {
        const nav = document.querySelector('.nav');
        const navTabs = document.querySelectorAll('.nav-tab');
        
        // Make navigation scrollable on mobile
        nav.classList.add('mobile-nav');
        
        // Add mobile hamburger menu for smaller screens
        if (window.innerWidth <= 480) {
            this.createMobileMenu();
        }
    }

    createMobileMenu() {
        const header = document.querySelector('.header');
        const nav = document.querySelector('.nav');
        
        const menuToggle = document.createElement('button');
        menuToggle.className = 'mobile-menu-toggle';
        menuToggle.innerHTML = '<i class="fas fa-bars"></i>';
        menuToggle.addEventListener('click', () => {
            nav.classList.toggle('mobile-nav-open');
            menuToggle.classList.toggle('active');
        });
        
        header.querySelector('.container').appendChild(menuToggle);
    }

    // Mobile-optimized forms
    setupMobileForms() {
        const textareas = document.querySelectorAll('textarea');
        const inputs = document.querySelectorAll('input[type="text"]');
        
        [...textareas, ...inputs].forEach(element => {
            element.addEventListener('focus', () => {
                // Scroll to element on focus (mobile keyboard handling)
                setTimeout(() => {
                    element.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }, 300);
            });
        });
    }

    // Responsive layout
    setupResponsiveLayout() {
        const resizeObserver = new ResizeObserver(entries => {
            for (const entry of entries) {
                if (entry.target === document.body) {
                    this.handleResize();
                }
            }
        });
        
        resizeObserver.observe(document.body);
    }

    handleResize() {
        const isMobile = window.innerWidth <= 768;
        document.body.classList.toggle('mobile-layout', isMobile);
        
        if (isMobile) {
            this.optimizeForMobile();
        } else {
            this.optimizeForDesktop();
        }
    }

    optimizeForMobile() {
        // Stack grid items vertically
        const grids = document.querySelectorAll('.grid-2, .grid-3');
        grids.forEach(grid => grid.classList.add('mobile-stack'));
        
        // Adjust form layouts
        const forms = document.querySelectorAll('form');
        forms.forEach(form => form.classList.add('mobile-form'));
    }

    optimizeForDesktop() {
        // Remove mobile optimizations
        const grids = document.querySelectorAll('.grid-2, .grid-3');
        grids.forEach(grid => grid.classList.remove('mobile-stack'));
        
        const forms = document.querySelectorAll('form');
        forms.forEach(form => form.classList.remove('mobile-form'));
    }

    // Pull to refresh
    setupPullToRefresh() {
        let startY = 0;
        let currentY = 0;
        let pulling = false;
        
        const refreshThreshold = 60;
        const refreshElement = document.createElement('div');
        refreshElement.className = 'pull-refresh';
        refreshElement.innerHTML = '<i class="fas fa-sync-alt"></i> Pull to refresh';
        document.body.insertBefore(refreshElement, document.body.firstChild);
        
        document.addEventListener('touchstart', (e) => {
            startY = e.touches[0].pageY;
            pulling = window.scrollY === 0;
        });
        
        document.addEventListener('touchmove', (e) => {
            if (!pulling) return;
            
            currentY = e.touches[0].pageY;
            const pullDistance = currentY - startY;
            
            if (pullDistance > 0) {
                e.preventDefault();
                const opacity = Math.min(pullDistance / refreshThreshold, 1);
                refreshElement.style.opacity = opacity;
                refreshElement.style.transform = `translateY(${Math.min(pullDistance, refreshThreshold)}px)`;
                
                if (pullDistance >= refreshThreshold) {
                    refreshElement.classList.add('ready');
                }
            }
        });
        
        document.addEventListener('touchend', () => {
            if (!pulling) return;
            
            const pullDistance = currentY - startY;
            if (pullDistance >= refreshThreshold) {
                this.refreshPage();
            }
            
            refreshElement.style.opacity = '0';
            refreshElement.style.transform = 'translateY(0)';
            refreshElement.classList.remove('ready');
            pulling = false;
        });
    }

    // Offline queue management
    processOfflineQueue() {
        if (this.offlineQueue.length === 0) return;
        
        console.log('Processing offline queue:', this.offlineQueue.length, 'items');
        
        this.offlineQueue.forEach(async (item, index) => {
            try {
                const response = await fetch(item.url, item.options);
                if (response.ok) {
                    this.offlineQueue.splice(index, 1);
                    this.showNotification('Offline item processed', 'success');
                }
            } catch (error) {
                console.error('Error processing offline item:', error);
            }
        });
    }

    queueOfflineRequest(url, options) {
        this.offlineQueue.push({ url, options });
        this.showNotification('Request queued for when online', 'info');
        
        // Also queue in service worker
        if (navigator.serviceWorker.controller) {
            navigator.serviceWorker.controller.postMessage({
                type: 'QUEUE_OFFLINE_PROCESSING',
                payload: { url, options }
            });
        }
    }

    // UI helpers
    showInstallButton() {
        const existingButton = document.querySelector('.install-button');
        if (existingButton) return;
        
        const installButton = document.createElement('button');
        installButton.className = 'btn btn-install install-button';
        installButton.innerHTML = '<i class="fas fa-download"></i> Install App';
        installButton.addEventListener('click', () => this.installApp());
        
        const header = document.querySelector('.header .container');
        header.appendChild(installButton);
    }

    hideInstallButton() {
        const installButton = document.querySelector('.install-button');
        if (installButton) {
            installButton.remove();
        }
    }

    installApp() {
        if (!this.deferredPrompt) return;
        
        this.deferredPrompt.prompt();
        this.deferredPrompt.userChoice.then((choiceResult) => {
            if (choiceResult.outcome === 'accepted') {
                console.log('User accepted the install prompt');
            }
            this.deferredPrompt = null;
        });
    }

    addNotificationButton() {
        const notifyButton = document.createElement('button');
        notifyButton.className = 'btn btn-notify';
        notifyButton.innerHTML = '<i class="fas fa-bell"></i> Enable Notifications';
        notifyButton.addEventListener('click', () => this.requestNotificationPermission());
        
        const header = document.querySelector('.header .container');
        header.appendChild(notifyButton);
    }

    async requestNotificationPermission() {
        const permission = await Notification.requestPermission();
        if (permission === 'granted') {
            this.showNotification('Notifications enabled!', 'success');
            document.querySelector('.btn-notify').remove();
        }
    }

    showUpdateNotification() {
        this.showNotification('App update available. Refresh to update.', 'info', 10000);
    }

    updateConnectionStatus() {
        const statusElement = document.querySelector('.connection-status') || 
                              this.createConnectionStatus();
        
        statusElement.textContent = this.isOnline ? 'Online' : 'Offline';
        statusElement.className = `connection-status ${this.isOnline ? 'online' : 'offline'}`;
    }

    createConnectionStatus() {
        const statusElement = document.createElement('div');
        statusElement.className = 'connection-status';
        const header = document.querySelector('.header .container');
        header.appendChild(statusElement);
        return statusElement;
    }

    handleGesture(startX, startY, endX, endY) {
        const deltaX = endX - startX;
        const deltaY = endY - startY;
        const minSwipeDistance = 50;
        
        if (Math.abs(deltaX) > Math.abs(deltaY) && Math.abs(deltaX) > minSwipeDistance) {
            if (deltaX > 0) {
                this.handleSwipeRight();
            } else {
                this.handleSwipeLeft();
            }
        }
    }

    handleSwipeRight() {
        // Navigate to previous tab
        const activeTabs = document.querySelectorAll('.nav-tab.active');
        if (activeTabs.length > 0) {
            const currentTab = activeTabs[0];
            const prevTab = currentTab.parentElement.previousElementSibling?.querySelector('.nav-tab');
            if (prevTab) {
                prevTab.click();
            }
        }
    }

    handleSwipeLeft() {
        // Navigate to next tab
        const activeTabs = document.querySelectorAll('.nav-tab.active');
        if (activeTabs.length > 0) {
            const currentTab = activeTabs[0];
            const nextTab = currentTab.parentElement.nextElementSibling?.querySelector('.nav-tab');
            if (nextTab) {
                nextTab.click();
            }
        }
    }

    refreshPage() {
        this.showNotification('Refreshing...', 'info');
        // Trigger refresh of current tab content
        const activeTab = document.querySelector('.nav-tab.active');
        if (activeTab) {
            activeTab.click();
        }
    }

    refreshResults() {
        // Refresh current tab content
        const activeTabContent = document.querySelector('.tab-content.active');
        if (activeTabContent) {
            // Trigger refresh based on current tab
            const tabId = activeTabContent.id;
            if (tabId === 'dashboard-tab') {
                window.loadDashboard?.();
            } else if (tabId === 'process-tab') {
                // Clear previous results
                const resultElement = document.getElementById('process-result');
                if (resultElement) {
                    resultElement.classList.add('hidden');
                }
            }
        }
    }

    showNotification(message, type = 'info', duration = 3000) {
        const notification = document.createElement('div');
        notification.className = `notification notification-${type}`;
        notification.textContent = message;
        
        const container = document.getElementById('message-container') || document.body;
        container.appendChild(notification);
        
        // Animate in
        setTimeout(() => notification.classList.add('show'), 10);
        
        // Remove after duration
        setTimeout(() => {
            notification.classList.remove('show');
            setTimeout(() => notification.remove(), 300);
        }, duration);
    }
}

// Initialize mobile app when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    window.mobileApp = new MobileApp();
});

// Export for use in other scripts
window.MobileApp = MobileApp;