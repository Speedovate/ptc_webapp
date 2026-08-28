{{flutter_js}}
{{flutter_build_config}}

(function () {
  const serviceWorkerVersion =
    {{flutter_service_worker_version}} || String(Date.now());
  const swVersionKey = 'paltranco_sw_version';

  async function clearStaleWebCachesIfNeeded() {
    if (
      typeof window === 'undefined' ||
      typeof navigator === 'undefined' ||
      !('serviceWorker' in navigator) ||
      !('caches' in window)
    ) {
      return;
    }

    const previousVersion = window.localStorage.getItem(swVersionKey);
    if (previousVersion === serviceWorkerVersion) {
      return;
    }

    try {
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(registrations.map((registration) => registration.unregister()));
    } catch (_) {}

    try {
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((key) => key.startsWith('paltranco-'))
          .map((key) => caches.delete(key)),
      );
    } catch (_) {}

    try {
      window.localStorage.setItem(swVersionKey, serviceWorkerVersion);
    } catch (_) {}
  }

  clearStaleWebCachesIfNeeded().finally(function () {
    _flutter.loader.load({
      serviceWorkerSettings: {
        serviceWorkerVersion,
        serviceWorkerUrl: `app_service_worker.js?v=${serviceWorkerVersion}`,
        timeoutMillis: 10000,
      },
    });
  });
})();
