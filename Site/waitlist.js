// Launch waitlist. Posts the email to the Loops form endpoint (the form's
// action), which sends a double opt-in confirmation from vanto.slenbder.com.
// `language` is a custom Loops contact property, so the launch email can go
// out in the site language the visitor signed up in. `company` is a honeypot:
// people never see it, bots fill it, and those submissions are dropped quietly.
// The address itself is never sent to analytics.
(() => {
  const form = document.querySelector('.waitlist-form');
  if (!form || !window.vantoI18n) return;
  const { t, code } = window.vantoI18n;
  const input = form.querySelector('input[name="email"]');
  const trap = form.querySelector('input[name="company"]');
  const button = form.querySelector('button[type="submit"]');
  const status = form.querySelector('.waitlist-status');
  const change = form.querySelector('.waitlist-change');
  const where = form.dataset.location;
  const track = (name, data) => window.vantoAnalytics?.track(name, { location: where, ...data });
  let busy = false;

  const show = (state, message) => {
    form.dataset.state = state;
    status.textContent = message;
  };

  // After a signup the field locks, and focus moves to "Use a different email"
  // rather than staying on the now-disabled submit button, so keyboard users
  // keep their place and a mistyped address can still be corrected.
  const finish = () => {
    form.classList.add('done');
    input.readOnly = true;
    button.disabled = true;
    change.hidden = false;
    change.focus();
  };

  change.addEventListener('click', () => {
    form.classList.remove('done');
    input.readOnly = false;
    button.disabled = false;
    change.hidden = true;
    show('idle', '');
    input.focus();
    input.select();
    track('Waitlist Change');
  });

  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (busy || form.classList.contains('done')) return;
    const email = input.value.trim();
    if (!input.checkValidity() || !email) {
      show('error', t('waitlist.invalid'));
      input.setAttribute('aria-invalid', 'true');
      input.focus();
      track('Waitlist Error', { reason: 'invalid' });
      return;
    }
    input.removeAttribute('aria-invalid');
    track('Waitlist Submit');
    if (trap.value) {
      show('success', t('waitlist.success'));
      finish();
      return;
    }

    busy = true;
    button.disabled = true;
    show('pending', t('waitlist.sending'));
    const body = new URLSearchParams({
      email,
      userGroup: 'waitlist',
      source: 'website',
      language: code || document.documentElement.lang,
    });
    try {
      const response = await fetch(form.action, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString(),
      });
      if (response.status === 429) {
        show('error', t('waitlist.rateLimit'));
        track('Waitlist Error', { reason: 'rate-limit' });
      } else if (response.status === 409) {
        show('success', t('waitlist.already'));
        track('Waitlist Success', { already: true });
        finish();
        return;
      } else {
        const result = await response.json().catch(() => ({}));
        if (response.ok && result.success) {
          show('success', t('waitlist.success'));
          track('Waitlist Success');
          finish();
          return;
        }
        show('error', t('waitlist.error'));
        track('Waitlist Error', { reason: `http-${response.status}` });
      }
    } catch {
      show('error', t('waitlist.error'));
      track('Waitlist Error', { reason: 'network' });
    } finally {
      busy = false;
    }
    button.disabled = form.classList.contains('done');
  });

  input.addEventListener('input', () => {
    if (form.dataset.state === 'error') {
      input.removeAttribute('aria-invalid');
      show('idle', '');
    }
  });
})();
