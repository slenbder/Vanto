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

  // The cookie is a toy: biting it never counts as a choice, only the two
  // equal-weight buttons do. Its title doubles as a queue joke and a live region.
  const TITLE_IDLE = 'Queue: 1 cookie. Paste it?';
  const TITLE_BITES = ['Queue: ⅔ cookie. Paste it?', 'Queue: ⅓ cookie. Going fast.', 'Queue: crumbs. That settles it.'];
  const TITLE_REGROWN = 'Fresh batch. Queue: 1 cookie.';
  const TITLE_CHOICE = { granted: 'Pasted. Crumbs only, promise.', denied: 'Skipped. No hard feelings.' };
  const BITES = [
    { origin: '38px 10px', crumbs: [35, 13], teeth: [[37, 11, 7.5], [43, 18, 6], [30, 6, 5.5]] },
    { origin: '44px 29px', crumbs: [39, 29], teeth: [[43, 29, 7], [45, 21, 5.5], [39, 37, 5.5]] },
    { origin: '12px 39px', crumbs: [15, 36], teeth: [[12, 39, 7.5], [6, 32, 5.5], [20, 44, 5.5]] }
  ];

  const banner = document.createElement('section');
  banner.className = 'consent';
  banner.setAttribute('aria-label', 'Cookie preferences');
  banner.hidden = true;
  banner.innerHTML = `
    <button class="consent-treat" type="button" aria-label="Take a bite of the cookie">
      <span class="consent-treat-roll"><svg viewBox="0 0 48 48" aria-hidden="true">
        <defs>
          <mask id="consent-bites" maskUnits="userSpaceOnUse" x="0" y="0" width="48" height="48">
            <rect width="48" height="48" fill="#fff" />
            ${BITES.map(bite => `<g class="consent-bite" style="transform-origin: ${bite.origin}">${bite.teeth.map(([cx, cy, r]) => `<circle cx="${cx}" cy="${cy}" r="${r}" />`).join('')}</g>`).join('')}
          </mask>
        </defs>
        <g class="consent-treat-body"><g class="consent-dough-group" mask="url(#consent-bites)">
          <path class="consent-dough" d="M24 4.5c3.2 0 4.6 1.4 7.4 2.3 2.9.9 5 .6 7 2.6 2.1 2 1.8 4.2 2.7 7 .9 2.8 2.4 4.3 2.4 7.6s-1.5 4.8-2.4 7.6c-.9 2.8-.6 5-2.7 7-2 2-4.1 1.7-7 2.6-2.8.9-4.2 2.3-7.4 2.3s-4.6-1.4-7.4-2.3c-2.9-.9-5-.6-7-2.6-2.1-2-1.8-4.2-2.7-7-.9-2.8-2.4-4.3-2.4-7.6s1.5-4.8 2.4-7.6c.9-2.8.6-5 2.7-7 2-2 4.1-1.7 7-2.6 2.8-.9 4.2-2.3 7.4-2.3Z" />
          <path class="consent-glaze" d="M12.5 16.5c2.4-4.6 6.6-7.2 11.5-7.4" />
          <g class="consent-chips">
            <path d="M17.6 18.2c1.3-.9 3.2-.4 3.6 1.1.4 1.6-.9 3-2.5 2.9-1.9-.1-2.7-2.7-1.1-4Z" />
            <path d="M28.8 14.6c1-.6 2.4-.1 2.6 1 .3 1.2-.8 2.2-2 2-1.3-.2-1.8-2.2-.6-3Z" />
            <path d="M30.4 26.2c1.5-1 3.6-.3 3.9 1.4.3 1.8-1.3 3.1-3 2.8-2-.3-2.6-3.1-.9-4.2Z" />
            <path d="M19.4 30.4c1.1-.7 2.7-.2 3 1 .3 1.3-.9 2.4-2.2 2.2-1.5-.2-2-2.4-.8-3.2Z" />
            <path d="M12.8 25.3c.8-.5 1.9-.1 2.1.8.2.9-.6 1.7-1.5 1.6-1.1-.1-1.5-1.8-.6-2.4Z" />
            <path d="M25 22.2c.7-.4 1.6-.1 1.7.7.2.8-.5 1.4-1.3 1.3-.9-.1-1.2-1.5-.4-2Z" />
          </g>
        </g></g>
      </svg></span>
    </button>
    <div class="consent-copy">
      <p class="consent-title" aria-live="polite">${TITLE_IDLE}</p>
      <p class="consent-text">Microsoft Clarity records scrolls and clicks. <a href="/privacy#analytics" data-track="Consent Details Click">Details</a></p>
    </div>
    <div class="consent-actions">
      <button class="consent-button" type="button" data-consent="denied" aria-label="Skip — decline Clarity cookies">Skip</button>
      <button class="consent-button" type="button" data-consent="granted" aria-label="Paste it — allow Clarity cookies">Paste it</button>
    </div>`;
  document.body.appendChild(banner);

  const cookie = banner.querySelector('.consent-treat');
  const dough = banner.querySelector('.consent-dough-group');
  const bites = [...banner.querySelectorAll('.consent-bite')];
  const title = banner.querySelector('.consent-title');
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let biteCount = 0;
  let regrowTimer = 0;
  let idleTimer = 0;
  let leaveTimer = 0;
  let leaving = false;
  let returnFocusTo = null;
  let nudgeTimer = 0;
  let nudgesLeft = 0;
  let lastBiteAt = 0;
  // Per showing, for analytics: how the banner was opened and what happened
  // before the choice. `round` counts cookies, so it grows after each regrow.
  const session = { trigger: 'auto', bites: 0, shakes: 0, round: 1 };
  const track = (name, data) => window.vantoAnalytics?.track(name, data);

  // Crumbs are positioned in the cookie's 48-unit viewBox, scaled to its box.
  const dropCrumbs = (count, [x, y], spread) => {
    if (reducedMotion.matches) return;
    const scale = cookie.getBoundingClientRect().width / 48;
    for (let i = 0; i < count; i += 1) {
      const crumb = document.createElement('span');
      crumb.className = 'consent-crumb';
      crumb.style.left = `${x * scale}px`;
      crumb.style.top = `${y * scale}px`;
      const size = 3 + Math.random() * 3;
      crumb.style.width = crumb.style.height = `${size}px`;
      cookie.appendChild(crumb);
      const dx = (Math.random() - .5) * spread;
      const dy = 14 + Math.random() * 20;
      crumb.animate([
        { transform: 'translate(-50%, -50%) rotate(0deg)', opacity: 1 },
        { transform: `translate(calc(-50% + ${dx}px), calc(-50% + ${dy}px)) rotate(${(Math.random() - .5) * 240}deg)`, opacity: 0 }
      ], { duration: 520 + Math.random() * 260, easing: 'cubic-bezier(.3, .6, .5, 1)' }).finished.finally(() => crumb.remove());
    }
  };

  const setTitle = text => { title.textContent = text; };

  const resetCookie = () => {
    window.clearTimeout(regrowTimer);
    window.clearTimeout(idleTimer);
    biteCount = 0;
    bites.forEach(bite => bite.classList.remove('is-bitten'));
    dough.classList.remove('is-crumbled');
    cookie.disabled = false;
  };

  const crumble = () => {
    dough.classList.add('is-crumbled');
    dropCrumbs(14, [24, 24], 56);
  };

  const bite = () => {
    if (leaving || biteCount >= BITES.length) return;
    lastBiteAt = Date.now();
    const next = BITES[biteCount];
    bites[biteCount].classList.add('is-bitten');
    biteCount += 1;
    cookie.classList.remove('is-chomping');
    void cookie.offsetWidth;
    cookie.classList.add('is-chomping');
    dropCrumbs(5, next.crumbs, 26);
    setTitle(TITLE_BITES[biteCount - 1]);
    session.bites += 1;
    track('Cookie Bite', { bite: biteCount, round: session.round });
    if (biteCount < BITES.length) return;

    // Last bite: the rest goes to crumbs, then a fresh one bakes itself.
    cookie.disabled = true;
    window.setTimeout(crumble, 160);
    regrowTimer = window.setTimeout(() => {
      session.round += 1;
      resetCookie();
      setTitle(TITLE_REGROWN);
      idleTimer = window.setTimeout(() => setTitle(TITLE_IDLE), 1800);
    }, 2200);
  };

  // A few shakes invite a bite and a decision, then the cookie settles for good:
  // motion that starts on its own must stop by itself (WCAG 2.2.2).
  const NUDGE_FIRST_DELAY = 2600;
  const NUDGE_INTERVAL = 5200;
  const NUDGE_COUNT = 5;
  const nudge = () => {
    if (leaving || banner.hidden || nudgesLeft <= 0) return;
    const busy = cookie.disabled || cookie.matches(':hover, :focus-visible') || Date.now() - lastBiteAt < 3000 || document.hidden;
    if (!busy && !reducedMotion.matches) {
      nudgesLeft -= 1;
      session.shakes += 1;
      cookie.animate([
        { transform: 'translateY(0) rotate(0)' },
        { transform: 'translateY(-3px) rotate(-14deg)', offset: .14 },
        { transform: 'translateY(-1px) rotate(12deg)', offset: .3 },
        { transform: 'rotate(-9deg)', offset: .46 },
        { transform: 'rotate(6deg)', offset: .62 },
        { transform: 'rotate(-3deg)', offset: .78 },
        { transform: 'translateY(0) rotate(0)' }
      ], { duration: 760, easing: 'ease-out' });
    }
    if (nudgesLeft > 0) nudgeTimer = window.setTimeout(nudge, NUDGE_INTERVAL);
  };
  const startNudges = () => {
    window.clearTimeout(nudgeTimer);
    nudgesLeft = NUDGE_COUNT;
    nudgeTimer = window.setTimeout(nudge, NUDGE_FIRST_DELAY);
  };

  const showBanner = trigger => {
    Object.assign(session, { trigger, bites: 0, shakes: 0, round: 1 });
    track('Consent Shown', { trigger });
    returnFocusTo = null;
    window.clearTimeout(leaveTimer);
    resetCookie();
    leaving = false;
    banner.classList.remove('is-leaving');
    setTitle(TITLE_IDLE);
    banner.hidden = false;
    startNudges();
  };

  const hideBanner = onHidden => {
    banner.classList.add('is-leaving');
    // Cookie animations bubble animationend too; wait for the banner's own exit.
    // A background tab can hold animationend back, so a timer finishes the exit too.
    const fallback = window.setTimeout(() => finish({ target: banner, animationName: 'consentOut' }), 600);
    const finish = event => {
      if (event.target !== banner || event.animationName !== 'consentOut') return;
      window.clearTimeout(fallback);
      banner.removeEventListener('animationend', finish);
      if (!banner.classList.contains('is-leaving')) return;
      banner.hidden = true;
      banner.classList.remove('is-leaving');
      // Hand keyboard focus back to where it came from (e.g. the footer's
      // Cookies link) instead of letting it fall to <body> with the banner.
      if (banner.contains(document.activeElement) && returnFocusTo?.isConnected) returnFocusTo.focus();
      returnFocusTo = null;
      onHidden?.();
    };
    banner.addEventListener('animationend', finish);
  };

  cookie.addEventListener('click', bite);

  banner.addEventListener('focusin', event => {
    if (event.relatedTarget && !banner.contains(event.relatedTarget)) returnFocusTo = event.relatedTarget;
  });

  banner.addEventListener('click', event => {
    const button = event.target.closest('[data-consent]');
    if (!button || leaving) return;
    const choice = button.dataset.consent;
    const wasGranted = readChoice() === 'granted';
    saveChoice(choice);
    track('Consent Choice', { choice, trigger: session.trigger, bites: session.bites, shakes: session.shakes });

    // The choice is saved immediately; the cookie reacts, then the banner leaves.
    leaving = true;
    window.clearTimeout(nudgeTimer);
    window.clearTimeout(regrowTimer);
    window.clearTimeout(idleTimer);
    // Buttons stay enabled so the focused one keeps focus; `leaving` blocks repeats.
    cookie.disabled = true;
    setTitle(TITLE_CHOICE[choice]);
    if (choice === 'granted') {
      const nextBite = bites.findIndex(item => !item.classList.contains('is-bitten'));
      if (nextBite >= 0) {
        bites[nextBite].classList.add('is-bitten');
        dropCrumbs(5, BITES[nextBite].crumbs, 26);
      }
    } else {
      crumble();
    }

    let reload = false;
    if (choice === 'granted') {
      loadClarity();
    } else if (wasGranted || clarityLoaded) {
      clearClarityCookies();
      reload = clarityLoaded;
    }
    leaveTimer = window.setTimeout(() => hideBanner(reload ? () => location.reload() : null), 900);
  });

  document.addEventListener('click', event => {
    if (!event.target.closest?.('[data-consent-open]')) return;
    const previous = document.activeElement;
    showBanner('footer');
    if (previous && previous !== document.body && !banner.contains(previous)) returnFocusTo = previous;
    banner.querySelector('.consent-button')?.focus();
  });

  const choice = readChoice();
  if (choice === 'granted') {
    loadClarity();
  } else if (choice !== 'denied') {
    showBanner('auto');
  }
})();
