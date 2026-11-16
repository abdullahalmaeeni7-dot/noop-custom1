import { createServer } from 'node:http';
import { createHash, timingSafeEqual } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { createNutritionAPI, nutritionConfigurationReady, NutritionRouteError } from '../lib/nutrition/routes.ts';

const routes = new Set(['analyze-meal', 'parse-food', 'estimate-exercise', 'day-review'].map(name => '/api/nutrition/' + name));
const digest = value => createHash('sha256').update(value).digest();

/** A private nutrition service. Its access code is separate from the provider key. */
export function createNutritionService({ accessToken, config, transport = globalThis.fetch, now = Date.now }) {
  if (typeof accessToken !== 'string' || !/^[\x21-\x7e]{32,256}$/.test(accessToken)) throw new Error('Configure a private NUTRITION_ACCESS_TOKEN of 32–256 non-whitespace characters.');
  const expected = digest(accessToken), api = createNutritionAPI(config, transport), buckets = new Map();
  const json = (res, status, body) => { res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(body)); };
  function authorized(req) {
    const token = /^Bearer ([\x21-\x7e]{32,256})$/.exec(req.headers.authorization ?? '')?.[1];
    return token !== undefined && timingSafeEqual(digest(token), expected);
  }
  function rateLimit(req) {
    const time = now();
    for (const [key, bucket] of buckets) if (bucket.expires <= time) buckets.delete(key);
    // Do not trust forwarded addresses provided by an arbitrary client.
    const key = req.socket.remoteAddress ?? 'unknown';
    let bucket = buckets.get(key);
    if (!bucket) {
      if (buckets.size >= 2048) throw new NutritionRouteError(429, 'rate_limited', 'Try again in a minute.');
      bucket = { count: 0, expires: time + 60_000 }; buckets.set(key, bucket);
    }
    if (++bucket.count > 8) throw new NutritionRouteError(429, 'rate_limited', 'Try again in a minute.');
  }
  async function read(req, limit) {
    if (!/^application\/json(?:\s*;|$)/i.test(req.headers['content-type'] ?? '')) throw new NutritionRouteError(400, 'invalid_request', 'Use JSON input.');
    if (Number(req.headers['content-length']) > limit) throw new NutritionRouteError(413, 'request_too_large', 'Choose a smaller photo.');
    const chunks = []; let size = 0;
    for await (const chunk of req) {
      size += chunk.length;
      if (size > limit) throw new NutritionRouteError(413, 'request_too_large', 'Choose a smaller photo.');
      chunks.push(chunk);
    }
    try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
    catch { throw new NutritionRouteError(400, 'invalid_request', 'Use valid JSON input.'); }
  }
  return async (req, res) => {
    res.setHeader('Cache-Control', 'no-store'); res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer'); res.setHeader('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none'");
    try {
      if ((req.url?.length ?? 0) > 4096) return json(res, 400, { error: 'invalid_request' });
      const url = new URL(req.url, 'http://nutrition.invalid');
      if (req.method === 'GET' && url.pathname === '/health') return json(res, 200, { service: 'nutrition-ai', version: 1, configured: nutritionConfigurationReady(config) });
      if (url.pathname !== '/session' && !routes.has(url.pathname)) return json(res, 404, { error: 'not_found' });
      if (!authorized(req)) return json(res, 401, { error: 'unauthorized' });
      if (req.method === 'GET' && url.pathname === '/session') return json(res, 200, { connected: true, configured: nutritionConfigurationReady(config) });
      if (req.method !== 'POST' || !routes.has(url.pathname)) return json(res, 405, { error: 'method_not_allowed' });
      rateLimit(req);
      const body = await read(req, url.pathname.endsWith('analyze-meal') ? 1_500_000 : 32_768);
      const output = await api(url.pathname, body, AbortSignal.timeout(45_000));
      return json(res, 200, output);
    } catch (error) {
      if (error instanceof NutritionRouteError) return json(res, error.status, { error: error.code, message: error.message });
      return json(res, 503, { error: 'ai_unavailable', message: 'The nutrition service could not finish this request.' });
    }
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const config = { provider: process.env.AI_PROVIDER || 'gemini', apiKey: process.env.AI_API_KEY, apiURL: process.env.AI_API_URL, model: process.env.AI_MODEL };
    const port = Number(process.env.PORT || 8787);
    if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid port');
    const handler = createNutritionService({ accessToken: process.env.NUTRITION_ACCESS_TOKEN, config });
    const server = createServer({ requestTimeout: 15_000, headersTimeout: 10_000, maxHeaderSize: 16_384 }, handler);
    server.keepAliveTimeout = 5000; server.maxRequestsPerSocket = 100;
    server.listen(port, process.env.HOST || '127.0.0.1', () => console.info('Private nutrition service listening. Provider secrets are never logged.'));
    const stop = () => { server.close(); server.closeIdleConnections(); };
    process.on('SIGTERM', stop); process.on('SIGINT', stop);
    server.on('error', () => { console.error('Nutrition listener failed. Check server configuration.'); process.exitCode = 1; });
  } catch { console.error('Nutrition startup failed. Configure the server access code and provider settings.'); process.exitCode = 1; }
}
