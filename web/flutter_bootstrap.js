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

  function registerAppServiceWorker() {
    if (isLocalDevelopmentHost || !('serviceWorker' in navigator)) {
      return;
    }

    // Do not await this. Flutter's deprecated loader registration attempts a
    // network update before starting the app, which can leave a cold offline
    // launch on the HTML splash. An already-active worker still controls this
    // page and serves the cached shell immediately.
    navigator.serviceWorker
      .register(`app_service_worker.js?v=${serviceWorkerVersion}`, {
        scope: './',
      })
      .catch(function () {});
  }

  function loadFlutter() {
    return _flutter.loader.load({ config: flutterConfig });
  }

  const bootstrapStart = isLocalDevelopmentHost
    ? Promise.resolve(true)
    : clearStaleWebCachesIfNeeded();

  bootstrapStart
    .then(function () {
      registerAppServiceWorker();
      return loadFlutter();
    })
    .catch(function () {
      // A storage exception must not prevent an offline app-shell startup.
      registerAppServiceWorker();
      return loadFlutter();
    });
})();
