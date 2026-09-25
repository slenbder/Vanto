(() => {
  const tilt = document.querySelector('.hero-shot-tilt');
  const hero = document.querySelector('.hero');
  if (!tilt || !hero || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  let scrollFrame = 0;
  const updateScroll = () => {
    scrollFrame = 0;
    const progress = Math.min(1, Math.max(0, window.scrollY / (hero.offsetHeight * 0.7)));
    tilt.style.setProperty('--p', progress.toFixed(3));
  };
  window.addEventListener('scroll', () => {
    if (!scrollFrame) scrollFrame = window.requestAnimationFrame(updateScroll);
  }, { passive: true });
  updateScroll();

  if (!window.matchMedia('(hover: hover) and (pointer: fine)').matches) return;

  const sheen = tilt.querySelector('#vp-sheen');
  const clamp = value => Math.max(-1, Math.min(1, value));
  const target = { x: 0, y: 0 };
  const current = { x: 0, y: 0 };
  let pointerFrame = 0;

  const step = () => {
    current.x += (target.x - current.x) * 0.09;
    current.y += (target.y - current.y) * 0.09;
    tilt.style.setProperty('--rx', `${(-current.y * 6).toFixed(2)}deg`);
    tilt.style.setProperty('--ry', `${(current.x * 8).toFixed(2)}deg`);
    if (sheen) {
      sheen.setAttribute('cx', (96 + current.x * 120).toFixed(1));
      sheen.setAttribute('cy', (60 + current.y * 110).toFixed(1));
    }
    const settled = Math.abs(target.x - current.x) < 0.001 && Math.abs(target.y - current.y) < 0.001;
    pointerFrame = settled ? 0 : window.requestAnimationFrame(step);
  };
  const run = () => {
    if (!pointerFrame) pointerFrame = window.requestAnimationFrame(step);
  };

  hero.addEventListener('pointermove', event => {
    const heroBox = hero.getBoundingClientRect();
    const shotBox = tilt.getBoundingClientRect();
    target.x = clamp((event.clientX - (shotBox.left + shotBox.width / 2)) / (heroBox.width / 2));
    target.y = clamp((event.clientY - (shotBox.top + shotBox.height / 2)) / (heroBox.height / 2));
    run();
  });
  hero.addEventListener('pointerleave', () => {
    target.x = 0;
    target.y = 0;
    run();
  });
})();
