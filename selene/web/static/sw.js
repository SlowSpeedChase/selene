// Service Worker for Selene PWA
// Enables offline functionality and caching

const CACHE_NAME = 'selene-v1';
const STATIC_CACHE_NAME = 'selene-static-v1';
const DYNAMIC_CACHE_NAME = 'selene-dynamic-v1';

// Files to cache for offline use
const STATIC_FILES = [
  '/',
  '/static/css/style.css',
  '/static/js/app.js',
  '/static/js/mobile.js',
  '/static/manifest.json',
  '/static/icons/icon-192x192.png',
  '/static/icons/icon-512x512.png'
];

// API endpoints to cache
const API_ENDPOINTS = [
  '/api/status',
  '/api/templates',
  '/api/processor-info'
];

// Install event - cache static files
self.addEventListener('install', event => {
  console.log('Service Worker: Installing...');
  event.waitUntil(
    caches.open(STATIC_CACHE_NAME)
      .then(cache => {
        console.log('Service Worker: Caching static files');
        return cache.addAll(STATIC_FILES);
      })
      .then(() => {
        console.log('Service Worker: Static files cached');
        return self.skipWaiting();
      })
      .catch(error => {
        console.error('Service Worker: Error caching static files:', error);
      })
  );
});

// Activate event - clean up old caches
self.addEventListener('activate', event => {
  console.log('Service Worker: Activating...');
  event.waitUntil(
    caches.keys()
      .then(cacheNames => {
        return Promise.all(
          cacheNames.map(cacheName => {
            if (cacheName !== STATIC_CACHE_NAME && cacheName !== DYNAMIC_CACHE_NAME) {
              console.log('Service Worker: Deleting old cache:', cacheName);
              return caches.delete(cacheName);
            }
          })
        );
      })
      .then(() => {
        console.log('Service Worker: Activated');
        return self.clients.claim();
      })
  );
});

// Fetch event - serve from cache or network
self.addEventListener('fetch', event => {
  const { request } = event;
  const url = new URL(request.url);
  
  // Skip non-GET requests
  if (request.method !== 'GET') {
    return;
  }
  
  // Skip chrome-extension requests
  if (url.protocol === 'chrome-extension:') {
    return;
  }
  
  // Handle static files
  if (STATIC_FILES.includes(url.pathname) || url.pathname.startsWith('/static/')) {
    event.respondWith(
      caches.match(request)
        .then(response => {
          if (response) {
            return response;
          }
          return fetch(request)
            .then(response => {
              if (response.status === 200) {
                const responseClone = response.clone();
                caches.open(STATIC_CACHE_NAME)
                  .then(cache => cache.put(request, responseClone));
              }
              return response;
            });
        })
    );
    return;
  }
  
  // Handle API requests
  if (url.pathname.startsWith('/api/')) {
    event.respondWith(
      fetch(request)
        .then(response => {
          if (response.status === 200) {
            const responseClone = response.clone();
            caches.open(DYNAMIC_CACHE_NAME)
              .then(cache => cache.put(request, responseClone));
          }
          return response;
        })
        .catch(() => {
          // If network fails, try cache
          return caches.match(request)
            .then(response => {
              if (response) {
                return response;
              }
              // Return offline response for critical APIs
              if (url.pathname === '/api/status') {
                return new Response(JSON.stringify({
                  status: 'offline',
                  message: 'System is offline'
                }), {
                  headers: { 'Content-Type': 'application/json' }
                });
              }
              throw new Error('Network unavailable');
            });
        })
    );
    return;
  }
  
  // Handle root and other requests
  event.respondWith(
    caches.match(request)
      .then(response => {
        if (response) {
          return response;
        }
        return fetch(request)
          .then(response => {
            if (response.status === 200) {
              const responseClone = response.clone();
              caches.open(DYNAMIC_CACHE_NAME)
                .then(cache => cache.put(request, responseClone));
            }
            return response;
          })
          .catch(() => {
            // Return cached root for navigation requests
            if (request.mode === 'navigate') {
              return caches.match('/');
            }
            throw new Error('Network unavailable');
          });
      })
  );
});

// Background sync for offline actions
self.addEventListener('sync', event => {
  console.log('Service Worker: Background sync triggered:', event.tag);
  
  if (event.tag === 'process-content') {
    event.waitUntil(processOfflineQueue());
  }
});

// Handle offline processing queue
async function processOfflineQueue() {
  try {
    const cache = await caches.open(DYNAMIC_CACHE_NAME);
    const requests = await cache.keys();
    
    for (const request of requests) {
      if (request.url.includes('/api/process') && request.method === 'POST') {
        try {
          const response = await fetch(request);
          if (response.ok) {
            await cache.delete(request);
            // Notify the client about successful processing
            self.clients.matchAll().then(clients => {
              clients.forEach(client => {
                client.postMessage({
                  type: 'OFFLINE_PROCESSING_COMPLETE',
                  success: true
                });
              });
            });
          }
        } catch (error) {
          console.error('Error processing offline request:', error);
        }
      }
    }
  } catch (error) {
    console.error('Error processing offline queue:', error);
  }
}

// Handle push notifications (for future use)
self.addEventListener('push', event => {
  console.log('Service Worker: Push message received:', event);
  
  const options = {
    body: event.data ? event.data.text() : 'Processing complete',
    icon: '/static/icons/icon-192x192.png',
    badge: '/static/icons/icon-96x96.png',
    vibrate: [200, 100, 200],
    data: {
      url: '/'
    }
  };
  
  event.waitUntil(
    self.registration.showNotification('Selene', options)
  );
});

// Handle notification click
self.addEventListener('notificationclick', event => {
  console.log('Service Worker: Notification clicked:', event);
  
  event.notification.close();
  
  event.waitUntil(
    clients.matchAll().then(clientList => {
      if (clientList.length > 0) {
        return clientList[0].focus();
      }
      return clients.openWindow('/');
    })
  );
});

// Handle messages from the main thread
self.addEventListener('message', event => {
  console.log('Service Worker: Message received:', event.data);
  
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
  
  if (event.data && event.data.type === 'QUEUE_OFFLINE_PROCESSING') {
    // Store the processing request for when we're back online
    caches.open(DYNAMIC_CACHE_NAME)
      .then(cache => {
        const request = new Request('/api/process', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify(event.data.payload)
        });
        return cache.put(request, new Response('queued'));
      });
  }
});

console.log('Service Worker: Loaded');