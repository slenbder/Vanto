// Cookie consent for Microsoft Clarity (session recordings and heatmaps).
// Clarity is never loaded until the visitor chooses Allow; Umami is cookieless
// and runs regardless. Any [data-consent-open] element reopens the prompt.
(() => {
  const STORAGE_KEY = 'vanto-consent';
  const CLARITY_ID = 'yntsvccfk0';
  const PRODUCTION_HOST = 'vanto.slenbder.com';

  const readChoice = () => {
    try { return localStorage.getItem(STORAGE_KEY); } catch { return null; }
  };
  const saveChoice = choice => {
    try { localStorage.setItem(STORAGE_KEY, choice); } catch {}
  };

  let clarityLoaded = false;
  const loadClarity = () => {
    if (clarityLoaded || location.hostname !== PRODUCTION_HOST) return;
    clarityLoaded = true;
    window.clarity = window.clarity || function () {
      (window.clarity.q = window.clarity.q || []).push(arguments);
    };
    window.clarity('consentv2', { ad_Storage: 'denied', analytics_Storage: 'granted' });
    const script = document.createElement('script');
    script.async = true;
    script.src = `https://www.clarity.ms/tag/${CLARITY_ID}`;
    document.head.appendChild(script);
  };

  // Clarity's first-party cookies; its third-party ones on clarity.ms are not ours to clear.
  const clearClarityCookies = () => {
    const host = location.hostname;
    const domains = ['', host, `.${host}`, `.${host.split('.').slice(-2).join('.')}`];
    ['_clck', '_clsk'].forEach(name => domains.forEach(domain => {
      document.cookie = `${name}=; Max-Age=0; path=/${domain ? `; domain=${domain}` : ''}`;
    }));
  };

  const banner = document.createElement('section');
  banner.className = 'consent';
  banner.setAttribute('aria-label', 'Cookie preferences');
  banner.hidden = true;
  banner.innerHTML = `
    <p class="consent-title">Help make this page better?</p>
    <p class="consent-text">If you allow it, Microsoft Clarity records how visitors scroll and click, using cookies. Visit counts never use cookies. <a href="/privacy#analytics">Details</a></p>
    <div class="consent-actions">
      <button class="consent-button" type="button" data-consent="granted">Allow</button>
      <button class="consent-button" type="button" data-consent="denied">Decline</button>
    </div>`;
  document.body.appendChild(banner);

  const showBanner = () => {
    banner.hidden = false;
  };

  banner.addEventListener('click', event => {
    const button = event.target.closest('[data-consent]');
    if (!button) return;
    const choice = button.dataset.consent;
    const wasGranted = readChoice() === 'granted';
    saveChoice(choice);
    banner.hidden = true;
    window.vantoAnalytics?.track('Consent Choice', { choice });

    if (choice === 'granted') {
      loadClarity();
    } else if (wasGranted || clarityLoaded) {
      clearClarityCookies();
      if (clarityLoaded) window.setTimeout(() => location.reload(), 150);
    }
  });

  document.addEventListener('click', event => {
    if (!event.target.closest?.('[data-consent-open]')) return;
    showBanner();
    banner.querySelector('.consent-button')?.focus();
  });

  const choice = readChoice();
  if (choice === 'granted') {
    loadClarity();
  } else if (choice !== 'denied') {
    showBanner();
  }
})();
