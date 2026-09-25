(() => {
  const root = document.documentElement;
  const themeButton = document.querySelector('.theme-toggle');
  const themeMeta = document.querySelector('meta[name="theme-color"]');
  const systemTheme = window.matchMedia('(prefers-color-scheme: dark)');

  const readSaved = () => {
    try { return localStorage.getItem('vanto-theme'); } catch { return null; }
  };

  const applyTheme = (theme, persist = false) => {
    root.dataset.theme = theme;
    themeButton?.setAttribute('aria-label', `Switch to ${theme === 'dark' ? 'light' : 'dark'} theme`);
    themeMeta?.setAttribute('content', theme === 'dark' ? '#141517' : '#f0f1f3');
    if (persist) {
      try { localStorage.setItem('vanto-theme', theme); } catch {}
    }
  };

  applyTheme(readSaved() || (systemTheme.matches ? 'dark' : 'light'));
  themeButton?.addEventListener('click', () => applyTheme(root.dataset.theme === 'dark' ? 'light' : 'dark', true));
  systemTheme.addEventListener('change', event => {
    if (!readSaved()) applyTheme(event.matches ? 'dark' : 'light');
  });
})();
