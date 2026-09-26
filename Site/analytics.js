// Site analytics on top of Umami (cookieless, loaded from /u/script.js).
// Declarative clicks: any element with data-track="Event Name" sends that event
// on click, with data-track-<key>="value" attributes as event properties.
// Umami only reports on vanto.slenbder.com (its data-domains attribute), so
// localhost and *.pages.dev previews never pollute the stats. To watch events
// locally, run localStorage.setItem('vanto-analytics-debug', '1') and reload.
(() => {
  const debug = (() => {
    try { return localStorage.getItem('vanto-analytics-debug') === '1'; } catch { return false; }
  })();
  const pending = [];

  const track = (name, data) => {
    if (debug) console.info('[analytics]', name, data || '');
    if (window.umami?.track) {
      window.umami.track(name, data);
    } else {
      pending.push([name, data]);
    }
  };

  document.querySelector('script[data-website-id]')?.addEventListener('load', () => {
    pending.splice(0).forEach(([name, data]) => window.umami?.track(name, data));
  });

  window.vantoAnalytics = { track };

  // Who reads which language from where. Umami adds the IP country to every
  // event; the device time zone is what a VPN does not change, so a Dutch IP
  // with Europe/Moscow and Russian chosen on the site reads as a Russian
  // visitor behind a VPN. Sent once per tab session, and added to language events.
  const siteLanguage = () => window.vantoI18n?.code || document.documentElement.lang;
  const locale = (() => {
    let timezone = 'unknown';
    try { timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || timezone; } catch {}
    const full = navigator.language || 'unknown';
    return { browser: full.split('-')[0].toLowerCase(), browserLocale: full, timezone };
  })();
  try {
    if (!sessionStorage.getItem('vanto-locale-sent')) {
      sessionStorage.setItem('vanto-locale-sent', '1');
      track('Visitor Locale', { ...locale, site: siteLanguage() });
    }
  } catch {}

  // The English home page's first-visit language redirect leaves a note for the
  // page it lands on, so automatic hops are told apart from menu switches.
  try {
    const from = sessionStorage.getItem('vanto-lang-redirect');
    if (from) {
      sessionStorage.removeItem('vanto-lang-redirect');
      track('Language Redirect', { from, to: siteLanguage(), ...locale });
    }
  } catch {}

  document.addEventListener('click', event => {
    const element = event.target.closest?.('[data-track]');
    if (!element) return;
    const data = {};
    for (const { name, value } of element.attributes) {
      if (name.startsWith('data-track-')) data[name.slice('data-track-'.length)] = value;
    }
    if (element.dataset.track === 'Language Switch') Object.assign(data, locale);
    track(element.dataset.track, Object.keys(data).length ? data : undefined);
  }, { capture: true });

  // FAQ: count answers being opened. Listens to summary clicks rather than the
  // toggle event, which some browsers also fire for details open on load.
  document.addEventListener('click', event => {
    const summary = event.target.closest?.('details > summary');
    if (!summary || summary.parentElement.open) return;
    // The English question (data-faq) keeps every language's opens in one row.
    track('FAQ Open', { question: summary.parentElement.dataset.faq || summary.textContent.trim() });
  });

  // Section reach: fires once per section when its top passes 60% of the viewport.
  const sections = ['play', 'why', 'faq', 'download']
    .map(id => document.getElementById(id))
    .filter(Boolean);
  if (sections.length && 'IntersectionObserver' in window) {
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (!entry.isIntersecting) return;
        observer.unobserve(entry.target);
        track('Section View', { section: entry.target.id });
      });
    }, { rootMargin: '0px 0px -40% 0px' });
    sections.forEach(section => observer.observe(section));
  }

  // Scroll depth milestones, once each per page view.
  const milestones = [25, 50, 75, 100];
  let reached = 0;
  let frame = 0;
  const measureDepth = () => {
    frame = 0;
    const root = document.documentElement;
    if (root.scrollHeight <= window.innerHeight * 1.2) return;
    const percent = ((window.scrollY + window.innerHeight) / root.scrollHeight) * 100;
    while (reached < milestones.length && percent >= Math.min(milestones[reached], 98)) {
      track('Scroll Depth', { depth: String(milestones[reached]) });
      reached += 1;
    }
    if (reached === milestones.length) window.removeEventListener('scroll', onScroll);
  };
  const onScroll = () => {
    if (!frame) frame = window.requestAnimationFrame(measureDepth);
  };
  window.addEventListener('scroll', onScroll, { passive: true });
})();
