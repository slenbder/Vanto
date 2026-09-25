(() => {
  const tilt = document.querySelector('.hero-shot-tilt');
  const hero = document.querySelector('.hero');
  if (!tilt || !hero || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  let frame = 0;
  const update = () => {
    frame = 0;
    const progress = Math.min(1, Math.max(0, window.scrollY / (hero.offsetHeight * 0.7)));
    tilt.style.setProperty('--p', progress.toFixed(3));
  };

  window.addEventListener('scroll', () => {
    if (!frame) frame = window.requestAnimationFrame(update);
  }, { passive: true });
  update();
})();
