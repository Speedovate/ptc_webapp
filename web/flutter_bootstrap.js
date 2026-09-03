{{flutter_js}}
{{flutter_build_config}}

(function () {
  const deployVersion = '2026-09-04-ios-safari-startup-1';
  const flutterServiceWorkerVersion =
    {{flutter_service_worker_version}} || String(Date.now());
  const serviceWorkerVersion =
    `${deployVersion}-${flutterServiceWorkerVersion}`;
  const swVersionKey = 'paltranco_sw_version';
  const flutterConfig = {
    canvasKitBaseUrl: 'canvaskit/',
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
      return true;
    }

    // Keep the active worker during upgrades. Removing it on every deploy
    // briefly makes the site ineligible for the browser install prompt.
    // app_service_worker.js performs its own versioned cache cleanup on
    // activation, so an explicit client-side cache purge is not needed.

    try {
      window.localStorage.setItem(swVersionKey, serviceWorkerVersion);
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

  const bootstrapStart = isLocalDevelopmentHost
    ? Promise.resolve(true)
    : clearStaleWebCachesIfNeeded();

  bootstrapStart
    .then(function (shouldLoadFlutter) {
      return loadFlutterWithSettings(!isLocalDevelopmentHost).catch(function () {
        return loadFlutterWithSettings(false);
      });
    })
    .catch(function () {
      return loadFlutterWithSettings(false);
    });
})();
