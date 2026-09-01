(function () {
  var deferredPrompt = null;
  var installBtn = document.getElementById('installPwa');
  var manifestLink = document.querySelector('link[rel="manifest"]');
  var isInstalled = false;

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

  function setInstalled() {
    isInstalled = true;
    installBtn.textContent = 'Open App';
  }

  function isStandalone() {
    return window.matchMedia('(display-mode: standalone)').matches ||
      window.navigator.standalone === true;
  }

  async function validateManifest() {
    if (!manifestLink) {
      return false;
    }
    try {
      var response = await fetch(manifestLink.href, { cache: 'no-store' });
      if (!response.ok) {
        throw new Error('Manifest request failed');
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
    if (isInstalled) {
      window.location.assign('/');
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
    setInstalled();
  });

  (async function initialize() {
    installBtn.disabled = true;
    var manifestReady = await validateManifest();
    var workerReady = await prepareServiceWorker();
    installBtn.disabled = false;

    if (isStandalone()) {
      setInstalled();
      return;
    }
    if (!manifestReady || !workerReady) {
      return;
    }
  })();
})();
