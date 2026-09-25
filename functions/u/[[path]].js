// First-party proxy for Umami Cloud, so the tracker loads from and reports to
// vanto.slenbder.com instead of third-party domains that content blockers drop.
//   GET  /u/script.js -> cloud.umami.is/script.js
//   POST /u/api/send  -> gateway.umami.is/api/send
// Umami Cloud reads the visitor's IP and location from its x-umami-client-*
// headers; without them every visit would look like a Cloudflare data center.
// City is deliberately not forwarded: country and region are enough.

const SCRIPT_URL = 'https://cloud.umami.is/script.js';
const COLLECT_URL = 'https://gateway.umami.is/api/send';

const FORWARDED_HEADERS = [
  'content-type',
  'user-agent',
  'accept-language',
  'x-umami-website-id',
  'x-umami-hostname',
  'x-umami-cache',
];

export async function onRequest({ request, params }) {
  const path = (params.path || []).join('/');

  if (path === 'script.js' && request.method === 'GET') {
    return proxyScript();
  }
  if (path === 'api/send' && request.method === 'POST') {
    return proxyCollect(request);
  }
  return new Response('Not found', { status: 404 });
}

async function proxyScript() {
  const upstream = await fetch(SCRIPT_URL, { cf: { cacheTtl: 3600, cacheEverything: true } });
  if (!upstream.ok) {
    return new Response('', { status: 502 });
  }
  return new Response(upstream.body, {
    headers: {
      'Content-Type': 'application/javascript; charset=utf-8',
      'Cache-Control': 'public, max-age=3600',
    },
  });
}

async function proxyCollect(request) {
  const headers = new Headers();
  for (const name of FORWARDED_HEADERS) {
    const value = request.headers.get(name);
    if (value) headers.set(name, value);
  }

  const ip = request.headers.get('cf-connecting-ip');
  if (ip) headers.set('x-umami-client-ip', ip);

  const { country, regionCode } = request.cf || {};
  if (country) headers.set('x-umami-client-country', country);
  if (regionCode) headers.set('x-umami-client-region', regionCode);

  const upstream = await fetch(COLLECT_URL, {
    method: 'POST',
    headers,
    body: await request.text(),
  });

  return new Response(upstream.body, {
    status: upstream.status,
    headers: {
      'Content-Type': upstream.headers.get('content-type') || 'application/json',
      'Cache-Control': 'no-store',
    },
  });
}
