// source.js — the radar's transport seam. Electron reads the stream files straight off disk
// (exactly the pre-seam behaviour); a hosted browser client (server.js) reads the same payloads
// over HTTP + SSE through a latest-copy store, so renderer.js keeps its synchronous read flow
// and stays transport-blind. config.json / view.json writes are host-only: srcWrite no-ops
// remotely, which is what makes remote clients view-only toward stream.lua.
export const IS_REMOTE = (typeof require !== 'function');

let fs = null, path = null, streamDir = '';
if (!IS_REMOTE) {
  fs = require('fs');
  path = require('path');
  const dirArg = process.argv.find((a) => a.startsWith('--stream-dir='));
  streamDir = dirArg ? dirArg.split('=')[1] : 'C:/Serotonin/files/stream';
}

const store = new Map();      // remote: name -> { body: string, sig: string }
const inflight = new Map();   // name -> true | 'again'
let watching = false;         // change-notification channel attached (fs.watch / SSE open)
let notify = () => {};

export function srcStreamDir() { return streamDir; }
export const srcIsWatching = () => watching;

// raw text of a stream file (meta.json / players.json / map.json), null if unavailable
export function srcRead(name) {
  if (!IS_REMOTE) {
    try { return fs.readFileSync(path.join(streamDir, name), 'utf8'); } catch { return null; }
  }
  const e = store.get(name);
  return e ? e.body : null;
}

// cheap change signature (map.json is multi-MB; gate before reading): disk mtime:size,
// remote the server's ETag — the same mtime:size, computed host-side
export function srcSig(name) {
  if (!IS_REMOTE) {
    try { const st = fs.statSync(path.join(streamDir, name)); return st.mtimeMs + ':' + st.size; } catch { return null; }
  }
  const e = store.get(name);
  return e ? e.sig : null;
}

// host-only reverse IPC (config.json, view.json)
export function srcWrite(name, text) {
  if (IS_REMOTE) return;
  try {
    fs.mkdirSync(streamDir, { recursive: true });
    fs.writeFileSync(path.join(streamDir, name), text);
  } catch { /* stream dir on a dead drive etc — same silence as before the seam */ }
}

// Single-flight pull: one response in flight per name means responses can never store out of
// order, and the trailing re-pull converges on the newest write. Also coalesces the duplicate
// reconnect fetch (onopen catch-up + first SSE event) into one transfer plus a cheap 304.
async function pull(name) {
  if (inflight.has(name)) { inflight.set(name, 'again'); return; }
  inflight.set(name, true);
  try {
    const res = await fetch('/stream/' + name, { cache: 'no-cache' });
    if (!res.ok) return;
    const sig = res.headers.get('etag') || String(Date.now());
    const prev = store.get(name);
    if (prev && prev.sig === sig) return;
    store.set(name, { body: await res.text(), sig });
    notify(name);
  } catch { /* host unreachable: SSE auto-retry + the safety poll keep trying */ }
  finally {
    const again = inflight.get(name) === 'again';
    inflight.delete(name);
    if (again) pull(name);
  }
}

// remote safety poll (SSE down): refresh everything; ETags make unchanged pulls cheap
export function srcPoll() {
  if (!IS_REMOTE) return;
  pull('meta.json'); pull('players.json'); pull('map.json');
}

// cb(filename) fires when fresh content is readable via srcRead. Electron: fs.watch (sync
// attach). Remote: SSE — `watching` flips with the connection so the caller's safety poll
// takes over during outages; every (re)connect pulls all three to catch up on missed writes.
// Call once at startup — not idempotent (a second call would stack another EventSource/fs.watch).
export function srcWatch(cb) {
  notify = cb;
  if (!IS_REMOTE) {
    try {
      fs.watch(streamDir, (_evt, filename) => {
        if (filename === 'map.json' || filename === 'players.json' || filename === 'meta.json') cb(filename);
      });
      watching = true;
    } catch (e) { console.warn('fs.watch failed, relying on poll:', e.message); }
    return watching;
  }
  const es = new EventSource('/events');
  es.onopen = () => { watching = true; srcPoll(); };
  es.onerror = () => { watching = false; };   // EventSource reconnects on its own
  es.addEventListener('meta', () => pull('meta.json'));
  es.addEventListener('players', () => pull('players.json'));
  es.addEventListener('map', () => pull('map.json'));
  return watching;
}
