// server.test.js — framework-free checks for server.js: `node server.test.js`, exit 0/1.
// Uses a temp stream dir + injected asset fetcher; never touches the network or real caches.
const fs = require('fs');
const path = require('path');
const os = require('os');
const http = require('http');
const { createRadarServer } = require('./server.js');

function get(port, p, headers) {
  return new Promise((resolve, reject) => {
    http.get({ host: '127.0.0.1', port, path: p, headers }, (res) => {
      const c = [];
      res.on('data', (d) => c.push(d));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(c) }));
    }).on('error', reject);
  });
}
// open /events, collect everything seen for `ms`, then disconnect
function sseProbe(port, ms) {
  return new Promise((resolve, reject) => {
    const req = http.get({ host: '127.0.0.1', port, path: '/events' }, (res) => {
      let buf = '';
      res.on('data', (d) => { buf += d; });
      setTimeout(() => { req.destroy(); resolve(buf); }, ms);
    });
    req.on('error', reject);
  });
}

let failed = 0;
const t = (name, cond) => { if (cond) console.log('ok  ' + name); else { console.error('FAIL ' + name); failed = 1; } };

(async () => {
  const streamDir = fs.mkdtempSync(path.join(os.tmpdir(), 'radar-stream-'));
  const cacheRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'radar-cache-'));
  fs.writeFileSync(path.join(streamDir, 'meta.json'), '{"status":"ok","place_id":1,"t":1,"map_ready":true}');
  const fakeBytes = Buffer.from('FAKEASSETBYTES');
  const calls = [];
  const srv = createRadarServer({
    streamDir, appDir: __dirname, host: '127.0.0.1', port: 0, cacheRoot,
    fetchBytes: async (id, cacheDir, ext, placeId) => {
      calls.push({ id, place: placeId });
      if (id === '40340340') { throw new Error('v1 http 403'); }
      if (id === '42942942') { throw Object.assign(new Error('rate-limited'), { rateLimited: true }); }
      return fakeBytes;
    },
  });
  await new Promise((r) => srv.server.on('listening', r));
  const port = srv.server.address().port;

  // ---- static ----
  let r = await get(port, '/');
  t('GET / -> 200 text/html', r.status === 200 && /text\/html/.test(r.headers['content-type']));
  r = await get(port, '/renderer.js');
  t('GET /renderer.js -> 200 js', r.status === 200 && /javascript/.test(r.headers['content-type']));
  r = await get(port, '/node_modules/three/build/three.module.js');
  t('three module served', r.status === 200 && /javascript/.test(r.headers['content-type']));
  r = await get(port, '/node_modules/three/examples/jsm/libs/draco/draco_decoder.wasm');
  t('draco wasm served with wasm mime', r.status === 200 && r.headers['content-type'] === 'application/wasm');
  r = await get(port, '/%2e%2e/CLAUDE.md');
  t('path traversal blocked', r.status === 404);
  // Windows-separator traversal: URL parser leaves %5c as-is in the path, so it reaches the
  // decodeURIComponent + path.normalize handler where it must still resolve to outside appDir.
  r = await get(port, '/node_modules/three/..%5c..%5cmain.js');
  t('win32-separator traversal blocked', r.status === 404);
  r = await get(port, '/main.js');
  t('non-allowlisted app file blocked', r.status === 404);
  r = await get(port, '/node_modules/electron/package.json');
  t('non-three node_modules blocked', r.status === 404);

  // ---- stream json ----
  r = await get(port, '/stream/meta.json');
  t('stream meta 200 + etag', r.status === 200 && !!r.headers.etag && r.body.toString().includes('"status"'));
  const oldEtag = r.headers.etag;
  const r304 = await get(port, '/stream/meta.json', { 'If-None-Match': oldEtag });
  t('etag revalidation -> 304', r304.status === 304);
  // ETag fresh side: rewrite with different content+size; old etag must now yield 200 + new etag.
  fs.writeFileSync(path.join(streamDir, 'meta.json'), '{"status":"ok","place_id":1,"t":2,"map_ready":true,"extra":1}');
  const rFresh = await get(port, '/stream/meta.json', { 'If-None-Match': oldEtag });
  t('etag fresh after rewrite -> 200 new etag', rFresh.status === 200 && rFresh.headers.etag !== oldEtag);
  r = await get(port, '/stream/config.json');
  t('config.json NOT served', r.status === 404);
  r = await get(port, '/stream/players.json');
  t('absent stream file -> 404', r.status === 404);

  // ---- SSE ----
  const ssePromise = sseProbe(port, 1200);
  await new Promise((r2) => setTimeout(r2, 250));   // let the subscription + fs.watch attach
  // Write config.json first — it is NOT in STREAM_FILES, so it must be filtered and produce no SSE event.
  fs.writeFileSync(path.join(streamDir, 'config.json'), '{"secret":true}');
  await new Promise((r2) => setTimeout(r2, 150));   // let any spurious event propagate before players write
  fs.writeFileSync(path.join(streamDir, 'players.json'), '{"players":[]}');
  const sse = await ssePromise;
  t('SSE retry hint sent', /retry:/.test(sse));
  t('SSE players event on write', /event: players/.test(sse));
  t('SSE config event NOT emitted', !/event: config/.test(sse));
  // Survivor: after the probe disconnects, verify the server still handles plain GET requests
  // (guards against broadcast-after-death or watcher teardown breaking the server).
  await new Promise((r2) => setTimeout(r2, 100));
  fs.writeFileSync(path.join(streamDir, 'meta.json'), '{"status":"ok","place_id":1,"t":3,"map_ready":true}');
  const rSurv = await get(port, '/stream/meta.json');
  t('GET after SSE disconnect still 200', rSurv.status === 200);

  // ---- asset proxy ----
  r = await get(port, '/asset/mesh/123456');
  t('asset miss -> fetched bytes', r.status === 200 && r.body.equals(fakeBytes));
  t('asset immutable cache header', /immutable/.test(r.headers['cache-control'] || ''));
  // cache hit: pre-write a file and confirm it's served without the fetcher
  fs.mkdirSync(path.join(cacheRoot, 'texture-cache'), { recursive: true });
  fs.writeFileSync(path.join(cacheRoot, 'texture-cache', '777.img'), 'CACHEDTEX');
  r = await get(port, '/asset/tex/777');
  t('asset cache hit served from disk', r.status === 200 && r.body.toString() === 'CACHEDTEX');
  // empty cache file (torn-write window) must be treated as a miss, not served immutable
  fs.mkdirSync(path.join(cacheRoot, 'mesh-cache'), { recursive: true });
  fs.writeFileSync(path.join(cacheRoot, 'mesh-cache', '888.mesh'), '');
  r = await get(port, '/asset/mesh/888');
  t('empty cache file refetched', r.status === 200 && r.body.equals(fakeBytes));
  // place param: digits forwarded, junk dropped
  await get(port, '/asset/mesh/999001?place=123456');
  t('place digits forwarded', calls.some((c) => c.id === '999001' && c.place === '123456'));
  await get(port, '/asset/mesh/999002?place=junk%0d%0aX');
  t('place junk dropped', calls.some((c) => c.id === '999002' && c.place === null));
  r = await get(port, '/asset/mesh/40340340');
  t('fetch failure -> 502', r.status === 502);
  r = await get(port, '/asset/mesh/42942942');
  t('rate-limited -> 429', r.status === 429);
  // the 429 above armed the server cooldown: misses now 429 WITHOUT hitting the fetcher...
  const callsBefore = calls.length;
  r = await get(port, '/asset/mesh/424242');
  t('cooldown blocks fetches', r.status === 429 && calls.length === callsBefore);
  // ...but cache hits keep serving
  r = await get(port, '/asset/tex/777');
  t('cache hits serve during cooldown', r.status === 200 && r.body.toString() === 'CACHEDTEX');
  r = await get(port, '/asset/mesh/notanid');
  t('non-numeric id -> 404', r.status === 404);

  srv.close();
  process.exitCode = failed;
  console.log(failed ? 'FAILED' : 'ALL OK');
})().catch((e) => { console.error(e); process.exit(1); });
