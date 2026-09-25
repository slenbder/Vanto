(() => {
  const items = [...document.querySelectorAll('[data-reveal]')];
  if (!items.length || !('IntersectionObserver' in window) || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  items.forEach(item => {
    if (item.getBoundingClientRect().top < window.innerHeight) item.classList.add('is-revealed');
  });
  document.documentElement.classList.add('reveal-ready');

  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('is-revealed');
      observer.unobserve(entry.target);
    });
  }, { rootMargin: '0px 0px -12% 0px' });

  items.filter(item => !item.classList.contains('is-revealed')).forEach(item => observer.observe(item));
})();
