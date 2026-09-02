{{flutter_js}}
{{flutter_build_config}}

(function () {
  const deployVersion = '2026-09-03-persistent-images-1';
  const flutterServiceWorkerVersion =
    {{flutter_service_worker_version}} || String(Date.now());
  const serviceWorkerVersion =
    `${deployVersion}-${flutterServiceWorkerVersion}`;
  const swVersionKey = 'paltranco_sw_version';
  const refreshFlagKey = 'paltranco_sw_forced_refresh_done';
  const flutterConfig = {
    canvasKitBaseUrl: 'canvaskit/',
    canvasKitVariant: 'chromium',
  };
  const isLocalDevelopmentHost =
    typeof window !== 'undefined' &&
    ['localhost', '127.0.0.1', '::1'].includes(window.location.hostname);

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

    // Keep the active worker during upgrades. Removing it on every deploy
    // briefly makes the site ineligible for the browser install prompt.
    // app_service_worker.js performs its own versioned cache cleanup on
    // activation, so an explicit client-side cache purge is not needed.

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

  function loadFlutterWithSettings(useServiceWorker) {
    const options = useServiceWorker
      ? {
          config: flutterConfig,
          serviceWorkerSettings: {
            serviceWorkerVersion,
            serviceWorkerUrl: `app_service_worker.js?v=${serviceWorkerVersion}`,
            timeoutMillis: 10000,
          },
        }
      : {
          config: flutterConfig,
        };
    return _flutter.loader.load(options);
  }

  function finalizeCacheBustUrl() {
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
  }

  const bootstrapStart = isLocalDevelopmentHost
    ? Promise.resolve(true)
    : clearStaleWebCachesIfNeeded();

  bootstrapStart
    .then(function (shouldLoadFlutter) {
      if (shouldLoadFlutter === false) {
        return;
      }
      finalizeCacheBustUrl();
      return loadFlutterWithSettings(!isLocalDevelopmentHost).catch(function () {
        return loadFlutterWithSettings(false);
      });
    })
    .catch(function () {
      return loadFlutterWithSettings(false);
    });
})();
