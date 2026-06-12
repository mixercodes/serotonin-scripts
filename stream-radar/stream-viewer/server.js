// server.js — optional radar hosting: serves the viewer, the live stream JSON and a Roblox asset
// proxy over HTTP so browsers (localhost or LAN) can run the radar without Electron. Runs in the
// Electron MAIN process; pure Node built-ins and no Electron imports, so it tests standalone.
//
// Security model: plain HTTP, no auth — own machine / own LAN only. The Roblox session cookie
// stays in this process (assetfetch.js); clients only ever see asset bytes. config.json and
// view.json are deliberately NOT exposed: remote clients are view-only toward stream.lua.
const http = require('http');
const fs = require('fs');
const path = require('path');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
};
const STREAM_FILES = new Set(['meta.json', 'players.json', 'map.json']);
// only the files the hosted page actually needs; main.js & co stay private
// assetfetch.js omitted: the browser branch of assetlib.js skips that require entirely, so serving it
// is exposure without purpose.
const APP_FILES = new Set(['index.html', 'renderer.js', 'assetlib.js', 'source.js']);

function createRadarServer({ streamDir, appDir, host, port, fetchBytes, cacheRoot }) {
  fetchBytes = fetchBytes || require('./assetfetch.js').fetchAssetBytes;
  cacheRoot = cacheRoot || appDir;
  const sseClients = new Set();
  let rlUntil = 0;   // server-side 429 cooldown — see the route comment

  // one fs.watch feeds every SSE client; per-file debounce so a write burst -> one event
  let watcher = null;
  const debounce = new Map();
  function startWatch() {
    if (watcher) return;
    try {
      watcher = fs.watch(streamDir, (_evt, filename) => {
        // Deleted watch dir on win32 does NOT raise an error — it fires rename callbacks with a full
        // path (e.g. \\?\C:\...) at ~60 k/s forever and never recovers. A real stream-file event is
        // always a bare filename, so a path separator means the dir is gone: kill the watcher now so
        // the heartbeat's self-heal loop can pick up the recreation.
        if (!filename || filename.includes('\\') || filename.includes('/')) {
          try { watcher.close(); } catch {}
          watcher = null;
          return;
        }
        if (!STREAM_FILES.has(filename)) return;
        clearTimeout(debounce.get(filename));
        debounce.set(filename, setTimeout(() => {
          const ev = `event: ${filename.slice(0, -5)}\ndata: 1\n\n`;
          for (const res of sseClients) res.write(ev);
        }, 50));
      });
      // On some Node/Windows builds dir deletion surfaces as EPERM; catch it so the main process
      // doesn't crash.
      watcher.on('error', () => { try { watcher.close(); } catch {} watcher = null; });
    } catch { /* stream dir missing: clients fall back to their safety poll */ }
  }

  const server = http.createServer(async (req, res) => {
    try {
      const u = new URL(req.url, 'http://radar');
      const p = u.pathname;

      if (p === '/events') {
        res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive' });
        res.write('retry: 1500\n\n');
        sseClients.add(res);
        startWatch();
        req.on('close', () => sseClients.delete(res));
        return;
      }

      if (p.startsWith('/stream/')) {
        const name = p.slice(8);
        if (!STREAM_FILES.has(name)) { res.writeHead(404); res.end(); return; }
        let st;
        try { st = fs.statSync(path.join(streamDir, name)); } catch { res.writeHead(404); res.end(); return; }
        const etag = `"${st.mtimeMs}:${st.size}"`;   // same change signature the Electron viewer stat-gates on; mtimeMs
        // granularity means a same-size rewrite within the same ms can false-304 — self-heals on the next change, acceptable for a radar tick
        if (req.headers['if-none-match'] === etag) { res.writeHead(304, { ETag: etag }); res.end(); return; }
        let body;
        try { body = fs.readFileSync(path.join(streamDir, name)); } catch { res.writeHead(404); res.end(); return; }
        res.writeHead(200, { 'Content-Type': MIME['.json'], ETag: etag, 'Cache-Control': 'no-cache' });
        res.end(body);
        return;
      }

      // Roblox asset proxy: browsers can't fetch assetdelivery directly (CORS) and have no disk
      // cache. Serve from the shared cache dirs; on miss, fetch via the same Node core the
      // renderer uses (cookie stays in this process) and let it write the cache file.
      // Roblox ids are int64 (≤19-20 digits); unbounded ids just buy a pointless upstream 502.
      const asset = /^\/asset\/(mesh|tex)\/(\d{1,20})$/.exec(p);
      if (asset) {
        const kind = asset[1];
        const id = asset[2];
        const cacheDir = path.join(cacheRoot, kind === 'mesh' ? 'mesh-cache' : 'texture-cache');
        const ext = kind === 'mesh' ? '.mesh' : '.img';
        let buf = null;
        try { buf = fs.readFileSync(path.join(cacheDir, id + ext)); } catch { /* miss */ }
        // Treat an EMPTY cache file as a miss: assetfetch writes are truncate-then-write and the
        // Electron renderer writes the same cache dirs, so a concurrent read can see 0 bytes. The
        // renderer self-heals on parse-fail, but a browser would cache the empty body under
        // `immutable` for a year. Note: concurrent same-id misses (≤3 clients) just duplicate
        // identical-byte fetches — dedup is deliberately omitted (the complexity isn't worth it).
        if (!buf || buf.length === 0) {
          // Server-side rate-limit cooldown gate (ON THE MISS PATH ONLY — cache hits keep serving
          // during cooldown): assetfetch's contract makes long-lived 429 memory the caller's job;
          // client-side rl state is per-tab and wiped on refresh, so the server is the only
          // cross-client guard. Mirrors the renderer's 30-min global cooldown (fetch-state.json
          // rationale: assetdelivery IP blocks are hours-long and hammering refreshes them).
          if (Date.now() < rlUntil) {
            res.writeHead(429, { 'Cache-Control': 'no-store', 'Retry-After': '1800' });
            res.end('rate-limit cooldown');
            return;
          }
          // Sanitize the place param before forwarding (it lands in a Roblox-Place-Id request
          // header on a cookie-authed upstream call).
          const pq = u.searchParams.get('place');
          const place = /^\d{1,19}$/.test(pq || '') ? pq : null;
          try { buf = await fetchBytes(id, cacheDir, ext, place); }
          catch (err) {
            if (err && err.rateLimited) rlUntil = Date.now() + 30 * 60e3;
            res.writeHead(err && err.rateLimited ? 429 : 502, { 'Cache-Control': 'no-store' });
            res.end(String((err && err.message) || err));
            return;
          }
        }
        res.writeHead(200, { 'Content-Type': 'application/octet-stream', 'Cache-Control': 'public, max-age=31536000, immutable' });
        res.end(buf);
        return;
      }

      // static: the hosted app + three (index.html's importmap uses relative node_modules paths)
      let rel;
      try {
        rel = p === '/' ? 'index.html' : decodeURIComponent(p.slice(1));
      } catch { /* malformed percent-encoding (e.g. %c0%af) is not a server error */ res.writeHead(404); res.end(); return; }
      const file = path.normalize(path.join(appDir, rel));
      const threeRoot = path.join(appDir, 'node_modules', 'three') + path.sep;
      const isAppFile = APP_FILES.has(rel) && file === path.join(appDir, rel);
      if (!isAppFile && !file.startsWith(threeRoot)) { res.writeHead(404); res.end(); return; }
      let body;
      try { body = fs.readFileSync(file); } catch { res.writeHead(404); res.end(); return; }
      res.writeHead(200, {
        'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
        'Cache-Control': 'no-cache',
      });
      res.end(body);
    } catch (err) {
      try { res.writeHead(500); res.end(String((err && err.message) || err)); } catch { /* socket gone */ }
    }
  });

  const hb = setInterval(() => {
    // Self-heal: if the watched dir disappeared, clear the dead watcher. If clients are still
    // connected and the dir has since been recreated, re-attach so events resume automatically.
    if (watcher && !fs.existsSync(streamDir)) { try { watcher.close(); } catch {} watcher = null; }
    if (!watcher && sseClients.size) startWatch();
    for (const res of sseClients) res.write(': hb\n\n');
  }, 25000);
  hb.unref && hb.unref();
  server.listen(port, host);
  return {
    server,
    close() {
      clearInterval(hb);
      if (watcher) watcher.close();
      for (const res of sseClients) { try { res.end(); } catch {} }
      sseClients.clear();
      server.close();
    },
  };
}

module.exports = { createRadarServer };
