{{flutter_js}}
{{flutter_build_config}}

(function () {
  const deployVersion = '2026-08-28-login-rollout-2';
  const flutterServiceWorkerVersion =
    {{flutter_service_worker_version}} || String(Date.now());
  const serviceWorkerVersion =
    `${deployVersion}-${flutterServiceWorkerVersion}`;
  const swVersionKey = 'paltranco_sw_version';
  const refreshFlagKey = 'paltranco_sw_forced_refresh_done';

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
      try {
        window.localStorage.removeItem(refreshFlagKey);
      } catch (_) {}
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

    const url = new URL(window.location.href);
    const hasFreshVersion = url.searchParams.get('pv') == deployVersion;
    const forcedRefreshDone = window.localStorage.getItem(refreshFlagKey) == 'true';
    if (!hasFreshVersion || !forcedRefreshDone) {
      try {
        window.localStorage.setItem(refreshFlagKey, 'true');
      } catch (_) {}
      url.searchParams.set('pv', deployVersion);
      window.location.replace(url.toString());
      return false;
    }

    try {
      window.localStorage.removeItem(refreshFlagKey);
    } catch (_) {}
    return true;
  }

  clearStaleWebCachesIfNeeded()
    .then(function (shouldLoadFlutter) {
      if (shouldLoadFlutter === false) {
        return;
      }
      if (
        typeof window !== 'undefined' &&
        window.localStorage.getItem(swVersionKey) === serviceWorkerVersion &&
        new URL(window.location.href).searchParams.get('pv') === deployVersion
      ) {
        try {
          window.history.replaceState(
            {},
            '',
            window.location.pathname + window.location.hash,
          );
        } catch (_) {}
      }
      _flutter.loader.load({
        serviceWorkerSettings: {
          serviceWorkerVersion,
          serviceWorkerUrl: `app_service_worker.js?v=${serviceWorkerVersion}`,
          timeoutMillis: 10000,
        },
      });
    })
    .catch(function () {
      _flutter.loader.load({
        serviceWorkerSettings: {
          serviceWorkerVersion,
          serviceWorkerUrl: `app_service_worker.js?v=${serviceWorkerVersion}`,
          timeoutMillis: 10000,
        },
      });
    });
})();
