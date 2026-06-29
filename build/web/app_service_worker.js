'use strict';

const version = new URL(self.location.href).searchParams.get('v') || 'v1';
const SHELL_CACHE = `paltranco-shell-${version}`;
const RUNTIME_CACHE = `paltranco-runtime-${version}`;

const APP_SHELL_URLS = [
  '/',
  '/index.html',
  '/flutter_bootstrap.js',
  '/flutter.js',
  '/manifest.json',
  '/version.json',
  '/favicon.png',
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
          if (key !== SHELL_CACHE && key !== RUNTIME_CACHE) {
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
