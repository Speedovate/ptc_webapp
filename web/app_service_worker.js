'use strict';

const version = new URL(self.location.href).searchParams.get('v') || 'v1';
const SHELL_CACHE = `paltranco-shell-${version}`;
const RUNTIME_CACHE = `paltranco-runtime-${version}`;
// Images are user content, not versioned app shell assets. Keep them across
// deployments so already displayed photos remain available offline.
const IMAGE_CACHE = 'paltranco-images';
const IMAGE_CACHE_PREFIX = 'paltranco-images';
const NETWORK_FIRST_PATHS = new Set([
  '/',
  '/index.html',
  '/flutter_bootstrap.js',
  '/flutter.js',
  '/main.dart.js',
  '/manifest.json',
  '/version.json',
]);
const TRUSTED_IMAGE_HOSTS = new Set([
  'firebasestorage.googleapis.com',
  'storage.googleapis.com',
]);

const APP_SHELL_URLS = [
  '/',
  '/index.html',
  '/flutter_bootstrap.js',
  '/flutter.js',
  // The HTML splash can only hand off to Flutter offline when the compiled
  // app and the CanvasKit runtime are part of the install-time shell cache.
  '/main.dart.js',
  '/canvaskit/canvaskit.js',
  '/canvaskit/canvaskit.wasm',
  '/canvaskit/chromium/canvaskit.js',
  '/canvaskit/chromium/canvaskit.wasm',
  '/manifest.json',
  '/version.json',
  '/favicon.png',
  '/assets/assets/icon.png',
  '/assets/assets/sdv_footer_lite.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(SHELL_CACHE);
      await cache.addAll(APP_SHELL_URLS);
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(
        keys.map((key) => {
          if (
            key !== SHELL_CACHE &&
            key !== RUNTIME_CACHE &&
            key !== IMAGE_CACHE &&
            !key.startsWith(IMAGE_CACHE_PREFIX)
          ) {
            return caches.delete(key);
          }
          return Promise.resolve(false);
        }),
      );
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') {
    return;
  }

  const url = new URL(request.url);
  if (isTrustedCrossOriginImageRequest(request, url)) {
    event.respondWith(handleImageRequest(request));
    return;
  }

  if (url.origin !== self.location.origin) {
    return;
  }

  if (request.mode === 'navigate') {
    event.respondWith(handleNavigationRequest(request));
    return;
  }

  event.respondWith(handleAssetRequest(request));
});

async function handleNavigationRequest(request) {
  try {
    const networkResponse = await fetch(request);
    const cache = await caches.open(SHELL_CACHE);
    await cache.put('/index.html', networkResponse.clone());
    await cache.put('/', networkResponse.clone());
    return networkResponse;
  } catch (_) {
    const cache = await caches.open(SHELL_CACHE);
    const cached = (await cache.match(request, { ignoreSearch: true })) ||
        (await cache.match('/')) ||
        (await cache.match('/index.html'));
    if (cached) {
      return cached;
    }
    throw _;
  }
}

async function handleAssetRequest(request) {
  const url = new URL(request.url);
  if (NETWORK_FIRST_PATHS.has(url.pathname)) {
    return handleCriticalAssetRequest(request);
  }

  const runtimeCache = await caches.open(RUNTIME_CACHE);
  const cached = await runtimeCache.match(request, { ignoreSearch: false });
  if (cached) {
    return cached;
  }

  try {
    const response = await fetch(request);
    if (response && response.ok) {
      await runtimeCache.put(request, response.clone());
    }
    return response;
  } catch (error) {
    const shellCache = await caches.open(SHELL_CACHE);
    const fallback =
        (await runtimeCache.match(request, { ignoreSearch: true })) ||
        (await shellCache.match(request, { ignoreSearch: true }));
    if (fallback) {
      return fallback;
    }
    throw error;
  }
}

async function handleCriticalAssetRequest(request) {
  const runtimeCache = await caches.open(RUNTIME_CACHE);

  try {
    const response = await fetch(request);
    if (response && response.ok) {
      await runtimeCache.put(request, response.clone());
    }
    return response;
  } catch (error) {
    const shellCache = await caches.open(SHELL_CACHE);
    const fallback =
        (await runtimeCache.match(request, { ignoreSearch: true })) ||
        (await shellCache.match(request, { ignoreSearch: true }));
    if (fallback) {
      return fallback;
    }
    throw error;
  }
}

async function handleImageRequest(request) {
  const imageCache = await caches.open(IMAGE_CACHE);
  const cached = await matchPersistedImage(request, imageCache);
  if (cached) {
    return cached;
  }

  const response = await fetch(request);
  if (response && (response.ok || response.type === 'opaque')) {
    await imageCache.put(request, response.clone());
  }
  return response;
}

async function matchPersistedImage(request, imageCache) {
  const fromActiveCache =
      (await imageCache.match(request, { ignoreSearch: false })) ||
      (await imageCache.match(request, { ignoreSearch: true }));
  if (fromActiveCache) {
    return fromActiveCache;
  }

  // Migrate seamlessly from the former versioned image caches without a
  // network request or forcing users to view every image again.
  const cacheKeys = await caches.keys();
  for (const cacheKey of cacheKeys) {
    if (cacheKey === IMAGE_CACHE || !cacheKey.startsWith(IMAGE_CACHE_PREFIX)) {
      continue;
    }
    const previousCache = await caches.open(cacheKey);
    const cached =
        (await previousCache.match(request, { ignoreSearch: false })) ||
        (await previousCache.match(request, { ignoreSearch: true }));
    if (cached) {
      await imageCache.put(request, cached.clone());
      return cached;
    }
  }
  return null;
}

function isTrustedCrossOriginImageRequest(request, url) {
  return (
    url.origin !== self.location.origin &&
    request.method === 'GET' &&
    request.destination === 'image' &&
    TRUSTED_IMAGE_HOSTS.has(url.hostname)
  );
}
