#!/usr/bin/env node
// Builds the static site in Site/ from the templates and dictionaries in site-src/.
// The output is committed (Cloudflare Pages deploys Site/ with no build step), and
// CI fails if it is stale, so edit site-src/ and rerun: node scripts/build-site.mjs
//
// Template syntax:
//   {{> name}}   partial from site-src/partials/<name>.html
//   {{t:key}}    dictionary value for the page language, inserted as HTML
//   {{a:key}}    the same value, escaped for an attribute
//   {{en:key}}   the English value, escaped for an attribute (stable analytics labels)
//   {{@name}}    value computed below for the page (lang, root, links, …)
// Dictionary values may contain {{@root}}, the current language's path prefix.

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..');
const SRC = join(REPO, 'site-src');
const OUT = join(REPO, 'Site');
const ORIGIN = 'https://vanto.slenbder.com';

// Menu order. `dir` is the URL prefix; English lives at the root.
export const LOCALES = [
  { code: 'en', dir: '', lang: 'en', short: 'EN', name: 'English' },
  { code: 'de', dir: 'de', lang: 'de', short: 'DE', name: 'Deutsch' },
  { code: 'es', dir: 'es', lang: 'es', short: 'ES', name: 'Español' },
  { code: 'pt-br', dir: 'pt-br', lang: 'pt-BR', short: 'PT', name: 'Português (Brasil)' },
  { code: 'ru', dir: 'ru', lang: 'ru', short: 'RU', name: 'Русский' },
  { code: 'ja', dir: 'ja', lang: 'ja', short: 'JA', name: '日本語' },
  { code: 'zh-hans', dir: 'zh-hans', lang: 'zh-Hans', short: 'ZH', name: '简体中文' },
];

// `path` is the pretty URL below the language prefix; legal pages stay English
// and point their canonical at the English original.
const PAGES = [
  { id: 'index', path: '', kind: 'home' },
  { id: 'privacy', path: 'privacy', kind: 'legal' },
  { id: 'terms', path: 'terms', kind: 'legal' },
  { id: 'refunds', path: 'refunds', kind: 'legal' },
  { id: '404', path: null, kind: 'error' },
];

const read = path => readFileSync(path, 'utf8');
const dictionaries = Object.fromEntries(
  LOCALES.map(locale => [locale.code, JSON.parse(read(join(SRC, 'i18n', `${locale.code}.json`)))])
);

const escapeAttr = value => String(value)
  .replace(/&(?![a-zA-Z]+;|#\d+;)/g, '&amp;')
  .replace(/"/g, '&quot;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;');
const escapeText = value => String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const nbsp = value => value.replace(/ /g, '&nbsp;');

const lookup = (dict, key) => key.split('.').reduce((node, part) => node?.[part], dict);

const problems = [];
const value = (locale, key) => {
  const found = lookup(dictionaries[locale.code], key);
  if (typeof found !== 'string') {
    problems.push(`${locale.code}: missing string "${key}"`);
    return `[${key}]`;
  }
  return found;
};

// Every dictionary must have exactly the English shape, including arrays and
// plural objects, so a missing translation fails the build instead of shipping.
const compareShape = (reference, other, path, code) => {
  if (Array.isArray(reference)) {
    if (!Array.isArray(other) || other.length !== reference.length) {
      problems.push(`${code}: "${path}" must be an array of ${reference.length}`);
      return;
    }
    reference.forEach((item, index) => compareShape(item, other[index], `${path}.${index}`, code));
  } else if (reference && typeof reference === 'object') {
    // Word-game labels map each language's own words, so only their type is fixed.
    if (path.endsWith('.labels')) {
      if (!other || typeof other !== 'object') problems.push(`${code}: "${path}" must be an object`);
      return;
    }
    if (!other || typeof other !== 'object' || Array.isArray(other)) {
      problems.push(`${code}: "${path}" must be an object`);
      return;
    }
    const plural = 'other' in reference;
    for (const key of Object.keys(reference)) {
      // Plural forms differ by language (Russian adds few/many; Japanese has only other).
      if (plural && key !== 'other') continue;
      compareShape(reference[key], other[key], path ? `${path}.${key}` : key, code);
    }
    if (!plural) {
      for (const key of Object.keys(other)) {
        if (!(key in reference)) problems.push(`${code}: unexpected key "${path ? `${path}.` : ''}${key}"`);
      }
    }
  } else if (typeof reference !== typeof other) {
    problems.push(`${code}: "${path}" must be a ${typeof reference}`);
  }
};
for (const locale of LOCALES.slice(1)) compareShape(dictionaries.en, dictionaries[locale.code], '', locale.code);

const prefix = locale => (locale.dir ? `/${locale.dir}/` : '/');
const pageUrl = (locale, page) => `${prefix(locale)}${page.path ?? ''}`;

const GLOBE = '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><circle cx="10" cy="10" r="7.5"/><path d="M2.5 10h15M10 2.5c2.1 2.2 3.1 4.7 3.1 7.5s-1 5.3-3.1 7.5c-2.1-2.2-3.1-4.7-3.1-7.5s1-5.3 3.1-7.5Z"/></svg>';

const languageLinks = (locale, page, className) => LOCALES.map(other => {
  const current = other.code === locale.code;
  const href = pageUrl(other, page.kind === 'error' ? PAGES[0] : page);
  const tracking = current ? ' aria-current="true"' : ` data-track="Language Switch" data-track-from="${locale.code}" data-track-to="${other.code}"`;
  return `<a${className ? ` class="${className}"` : ''} href="${href}" hreflang="${other.lang}" lang="${other.lang}" data-lang="${other.code}"${tracking}>${other.name}</a>`;
});

const languageMenu = (locale, page) => {
  const label = escapeText(value(locale, 'lang.label'));
  const items = languageLinks(locale, page).map(link => `            <li>${link}</li>`).join('\n');
  return `        <details class="lang-menu">
          <summary class="lang-toggle" title="${escapeAttr(label)}">${GLOBE}<span class="visually-hidden">${label}: </span><span class="lang-code">${locale.short}</span></summary>
          <ul class="lang-list">
${items}
          </ul>
        </details>`;
};

const footerLanguages = (locale, page) => `      <nav class="footer-langs" aria-label="${escapeAttr(value(locale, 'lang.label'))}">${languageLinks(locale, page).join('')}</nav>`;

// First visit to the English home page: follow the browser language once. An
// explicit choice from the language menu (saved in localStorage) always wins.
// Query and hash are kept so campaign tags and anchors survive the hop.
const redirectScript = () => {
  const map = Object.fromEntries(LOCALES.map(locale => [locale.code, locale.dir]));
  return `    <script>
      (() => {
        const dirs = ${JSON.stringify(map)};
        const fromBrowser = () => {
          for (const tag of navigator.languages || [navigator.language]) {
            const [base, ...rest] = String(tag).toLowerCase().split('-');
            if (base === 'zh') {
              if (rest.some(part => ['hant', 'tw', 'hk', 'mo'].includes(part))) continue;
              return 'zh-hans';
            }
            if (base === 'pt') return 'pt-br';
            if (base in dirs) return base;
          }
          return 'en';
        };
        let saved = null;
        try { saved = localStorage.getItem('vanto-lang'); } catch {}
        const target = saved in dirs ? saved : fromBrowser();
        if (target === 'en') return;
        if (!saved) try { sessionStorage.setItem('vanto-lang-redirect', 'en'); } catch {}
        location.replace('/' + dirs[target] + '/' + location.search + location.hash);
      })();
    </script>
`;
};

const headLinks = (locale, page) => {
  if (page.kind === 'error') return '';
  if (page.kind === 'legal') return `    <link rel="canonical" href="${ORIGIN}${pageUrl(LOCALES[0], page)}" />\n`;
  const lines = [`    <link rel="canonical" href="${ORIGIN}${pageUrl(locale, page)}" />`];
  for (const other of LOCALES) lines.push(`    <link rel="alternate" hreflang="${other.lang}" href="${ORIGIN}${pageUrl(other, page)}" />`);
  lines.push(`    <link rel="alternate" hreflang="x-default" href="${ORIGIN}${pageUrl(LOCALES[0], page)}" />`);
  return `${lines.join('\n')}\n`;
};

// The word game's first scenario is also the no-JS starting state of the page.
const game = locale => lookup(dictionaries[locale.code], 'js.game');
const gameTarget = (locale, blankClass) => {
  const { scenarios, blank } = game(locale);
  return scenarios[0].targetParts
    .map((part, index) => nbsp(escapeText(part)) + (index < 3 ? `<span class="${blankClass}">${blank}</span>` : ''))
    .join('');
};

// Only the home page runs the word game, so other pages skip its strings.
const scriptStrings = (locale, page) => {
  const { game, ...shared } = dictionaries[locale.code].js;
  const strings = page.kind === 'home' ? { ...shared, game } : shared;
  return JSON.stringify({ lang: locale.lang, code: locale.code, root: prefix(locale), strings }).replace(/</g, '\\u003c');
};

const computed = (locale, page) => ({
  lang: locale.lang,
  root: prefix(locale),
  home: page.kind === 'home' ? '#top' : prefix(locale),
  title: escapeText(value(locale, `meta.${page.id}.title`)),
  description: escapeAttr(value(locale, `meta.${page.id}.description`)),
  robots: page.kind === 'error' ? '    <meta name="robots" content="noindex" />\n' : '',
  redirect: page.kind === 'home' && locale.code === 'en' ? redirectScript() : '',
  links: headLinks(locale, page),
  langMenu: languageMenu(locale, page),
  footerLangs: footerLanguages(locale, page),
  i18n: scriptStrings(locale, page),
  legalNote: locale.code === 'en' ? '' : `        <p class="legal-translation" lang="${locale.lang}">${value(locale, 'lang.englishOnly')}</p>\n`,
  gameSource: game(locale).scenarios[0].source,
  gameTarget: gameTarget(locale, 'target-blank'),
  gamePreview: gameTarget(locale, 'preview-target-blank'),
  gameHint: game(locale).scenarios[0].hint,
  faqEmail: '<a class="contact-link" href="mailto:vanto@slenbder.com" data-track="Email Click" data-track-location="faq">vanto@slenbder.com</a>',
});

const render = (template, locale, page, vars) => {
  let html = template;
  for (let depth = 0; html.includes('{{>') && depth < 5; depth += 1) {
    html = html.replace(/\{\{> ([\w-]+)\}\}/g, (_, name) => read(join(SRC, 'partials', `${name}.html`)).replace(/\n$/, ''));
  }
  html = html
    .replace(/\{\{t:([\w.]+)\}\}/g, (_, key) => value(locale, key))
    .replace(/\{\{a:([\w.]+)\}\}/g, (_, key) => escapeAttr(value(locale, key)))
    .replace(/\{\{en:([\w.]+)\}\}/g, (_, key) => escapeAttr(value(LOCALES[0], key)))
    .replace(/\{\{@(\w+)\}\}/g, (match, name) => {
      if (!(name in vars)) {
        problems.push(`${page.id}: unknown variable ${match}`);
        return match;
      }
      return vars[name];
    });
  const leftover = html.match(/\{\{[^}]*\}\}/);
  if (leftover) problems.push(`${locale.code}/${page.id}: unresolved ${leftover[0]}`);
  return html;
};

const outputs = new Map();
for (const page of PAGES) {
  const template = read(join(SRC, 'pages', `${page.id}.html`));
  for (const locale of LOCALES) {
    const vars = computed(locale, page);
    const file = join(OUT, locale.dir, `${page.id}.html`);
    outputs.set(file, render(template, locale, page, vars));
  }
}

const sitemapEntry = (url, alternates) => [
  '  <url>',
  `    <loc>${ORIGIN}${url}</loc>`,
  ...alternates.map(([lang, href]) => `    <xhtml:link rel="alternate" hreflang="${lang}" href="${ORIGIN}${href}" />`),
  '  </url>',
].join('\n');
const homeAlternates = [...LOCALES.map(locale => [locale.lang, pageUrl(locale, PAGES[0])]), ['x-default', '/']];
outputs.set(join(OUT, 'sitemap.xml'), [
  '<?xml version="1.0" encoding="UTF-8"?>',
  '<!-- Generated by scripts/build-site.mjs. -->',
  '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">',
  ...LOCALES.map(locale => sitemapEntry(pageUrl(locale, PAGES[0]), homeAlternates)),
  ...PAGES.filter(page => page.kind === 'legal').map(page => sitemapEntry(pageUrl(LOCALES[0], page), [])),
  '</urlset>',
  '',
].join('\n'));

if (problems.length) {
  console.error(`Site build failed:\n  ${[...new Set(problems)].join('\n  ')}`);
  process.exit(1);
}

let changed = 0;
for (const [file, content] of outputs) {
  let previous = null;
  try { previous = read(file); } catch {}
  if (previous === content) continue;
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, content);
  changed += 1;
}
console.log(`Site built: ${outputs.size} files, ${changed} updated.`);
