{{flutter_js}}
{{flutter_build_config}}

(function () {
  const serviceWorkerVersion =
    "{{flutter_service_worker_version}}" || String(Date.now());

  _flutter.loader.load({
    serviceWorkerSettings: {
      serviceWorkerVersion,
      serviceWorkerUrl: `app_service_worker.js?v=${serviceWorkerVersion}`,
      timeoutMillis: 10000,
    },
  });
})();
