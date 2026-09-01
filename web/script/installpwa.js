(function () {
  var deferredPrompt = null;
  var installBtn = document.getElementById('installPwa');
  var status = document.getElementById('installStatus');
  var manualSteps = document.getElementById('manualSteps');
  var manifestLink = document.querySelector('link[rel="manifest"]');
  var isInstalled = false;

  function setStatus(message) {
    status.textContent = message;
  }

  function isIos() {
    var agent = navigator.userAgent || '';
    return /iPhone|iPad|iPod/i.test(agent) ||
      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  }

  function setManualSteps() {
    manualSteps.hidden = false;
    if (isIos()) {
      manualSteps.innerHTML = '<strong>Install on iPhone or iPad</strong><span>1. Tap the Share button.</span><span>2. Choose Add to Home Screen.</span>';
      return;
    }
    manualSteps.innerHTML = '<strong>Install from Chrome</strong><span>1. Tap the three-dot menu.</span><span>2. Choose Install app or Add to Home screen.</span>';
  }

  function setInstalled() {
    isInstalled = true;
    installBtn.textContent = 'Open app';
    setStatus('Paltranco is installed on this device.');
    manualSteps.hidden = true;
  }

  function isStandalone() {
    return window.matchMedia('(display-mode: standalone)').matches ||
      window.navigator.standalone === true;
  }

  async function validateManifest() {
    if (!manifestLink) {
      setStatus('The app manifest could not be found.');
      return false;
    }
    try {
      var response = await fetch(manifestLink.href, { cache: 'no-store' });
      if (!response.ok) {
        throw new Error('Manifest request failed');
      }
      return true;
    } catch (_) {
      setStatus('The app configuration could not be loaded.');
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
      var choice = await promptEvent.userChoice;
      setStatus(choice && choice.outcome === 'accepted' ? 'Installing Paltranco...' : 'Installation was cancelled.');
      return;
    }
    setManualSteps();
    setStatus('Use your browser menu to add Paltranco to your device.');
  });

  window.addEventListener('beforeinstallprompt', function (event) {
    event.preventDefault();
    deferredPrompt = event;
    manualSteps.hidden = true;
    setStatus('Paltranco is ready to install.');
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
      setStatus('Install may be unavailable until the page can load its offline support.');
      setManualSteps();
      return;
    }
    setStatus('Tap Install app, or use your browser menu to add it to your home screen.');
  })();
})();
