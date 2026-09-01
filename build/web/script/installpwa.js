(function () {
  var deferredPrompt = null;
  var installBtn = document.getElementById('installPwa');
  var manifestLink = document.querySelector('link[rel="manifest"]');
  var isOpenMode = false;
  var manifestUrl = null;
  var appStartUrl = '/';

  function isIos() {
    var agent = navigator.userAgent || '';
    return /iPhone|iPad|iPod/i.test(agent) ||
      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  }

  function showManualInstallHelp() {
    if (isIos()) {
      window.alert('To install Paltranco: tap Share, then choose Add to Home Screen.');
      return;
    }
    window.alert('To install Paltranco: open the Chrome three-dot menu, then choose Install app or Add to Home screen.');
  }

  function setOpenMode() {
    isOpenMode = true;
    installBtn.textContent = 'Open App';
    installBtn.disabled = false;
  }

  function isStandalone() {
    return window.matchMedia('(display-mode: standalone)').matches ||
      window.navigator.standalone === true;
  }

  async function checkIfInstalled() {
    if (isStandalone()) {
      setOpenMode();
      return true;
    }

    if (!navigator.getInstalledRelatedApps || !manifestUrl) {
      return false;
    }

    try {
      var relatedApps = await navigator.getInstalledRelatedApps();
      var isRelatedWebAppInstalled = relatedApps.some(function (app) {
        return app.platform === 'webapp' && app.url === manifestUrl.href;
      });
      if (isRelatedWebAppInstalled) {
        setOpenMode();
      }
      return isRelatedWebAppInstalled;
    } catch (_) {
      return false;
    }
  }

  function openInstalledWebApp() {
    if (isStandalone()) {
      window.location.href = appStartUrl;
      return;
    }

    var launchLink = document.createElement('a');
    launchLink.href = appStartUrl;
    launchLink.target = '_blank';
    launchLink.rel = 'noopener noreferrer';
    launchLink.style.display = 'none';
    document.body.appendChild(launchLink);
    launchLink.click();
    launchLink.remove();
  }

  async function validateManifest() {
    if (!manifestLink) {
      return false;
    }
    try {
      manifestUrl = new URL(manifestLink.getAttribute('href'), window.location.href);
      var response = await fetch(manifestUrl.href, { cache: 'no-store' });
      if (!response.ok) {
        throw new Error('Manifest request failed');
      }
      var manifest = await response.json();
      if (manifest.start_url) {
        appStartUrl = new URL(manifest.start_url, manifestUrl.href).href;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  async function prepareServiceWorker() {
    if (!('serviceWorker' in navigator)) {
      return false;
    }
    try {
      await navigator.serviceWorker.register('/app_service_worker.js', { scope: '/' });
      await Promise.race([
        navigator.serviceWorker.ready,
        new Promise(function (resolve) { window.setTimeout(resolve, 5000); }),
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }

  installBtn.addEventListener('click', async function () {
    if (isOpenMode) {
      openInstalledWebApp();
      return;
    }
    if (deferredPrompt) {
      var promptEvent = deferredPrompt;
      deferredPrompt = null;
      promptEvent.prompt();
      await promptEvent.userChoice;
      return;
    }
    showManualInstallHelp();
  });

  window.addEventListener('beforeinstallprompt', function (event) {
    event.preventDefault();
    deferredPrompt = event;
  });

  window.addEventListener('appinstalled', function () {
    deferredPrompt = null;
    setOpenMode();
  });

  (async function initialize() {
    installBtn.disabled = true;
    var manifestReady = await validateManifest();
    var workerReady = await prepareServiceWorker();
    installBtn.disabled = false;

    if (await checkIfInstalled()) {
      return;
    }
    if (!manifestReady || !workerReady) {
      return;
    }
  })();
})();
