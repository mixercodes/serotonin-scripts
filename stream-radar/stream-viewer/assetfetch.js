// assetfetch.js — Node-side Roblox asset fetching: https GET with decompression, the local
// client's DPAPI session cookie, v1 resolve -> CDN follow, 429 backoff, disk-cache write.
// CommonJS and THREE-free on purpose: required by BOTH the renderer (through assetlib.js under
// Electron nodeIntegration) and the radar server's /asset proxy (Electron main process).
//
// MODULE STATE IS PER PROCESS: the renderer and the main-process server each get an independent
// instance of backoff, cookie cache, and place-id. Serialized fetch queueing and long-lived 429
// rate-limit memory are the CALLER's responsibility (the renderer persists fetch-state.json;
// a main-process server consumer has none and must handle that itself).
const fs = require('fs');
const path = require('path');
const https = require('https');
const zlib = require('zlib');

const MESH_UA = { 'User-Agent': 'Roblox/WinInet' };

// Node https GET (NOT fetch): Chromium's fetch silently drops the `Cookie` header (forbidden
// header name) and returns opaque status-0 for redirect:'manual', so authed asset resolves are
// impossible with fetch. Resolves { status, headers, body } with the body decompressed.
function httpsGet(url, headers) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, { headers }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        let body = Buffer.concat(chunks);
        const enc = (res.headers['content-encoding'] || '').toLowerCase();
        try {
          if (enc === 'gzip') body = zlib.gunzipSync(body);
          else if (enc === 'deflate') body = zlib.inflateSync(body);
          else if (enc === 'br') body = zlib.brotliDecompressSync(body);
        } catch { /* leave as-is; trailing magic check covers query-param gzip */ }
        resolve({ status: res.statusCode, headers: res.headers, body });
      });
    });
    req.on('error', reject);
    req.setTimeout(15000, () => req.destroy(new Error('asset fetch timeout')));
  });
}

// ----- 429 backoff, shared by every fetch IN THIS PROCESS (the serialized queue lives in the caller) -----
let backoff = 0;   // ms; grows on 429, decays on success
const getBackoff = () => backoff;
const decayBackoff = () => { if (backoff > 0) backoff = Math.max(0, backoff - 250); };

// Experience-restricted assets need the place context (`Roblox-Place-Id`); public assets ignore
// it. The renderer pushes the current place in once; the server proxy passes it per request.
// Without it, experience-restricted assets return 403 "User is not authorized to access Asset".
let assetPlaceId = null;
function setAssetPlaceId(id) { assetPlaceId = (id && id !== 0) ? String(id) : null; }

// Roblox session cookie for protected assets, decrypted once from the client's DPAPI cookie jar.
// The value lives ONLY in memory and is sent ONLY to assetdelivery.roblox.com.
// Async: the first call spawns a PowerShell DPAPI decrypt (~1-3 s); subsequent calls return the
// cached promise immediately. Always await — never call synchronously.
let rbxCookiePromise;   // undefined = not tried yet; set to a Promise<string|null> on first call
function getRobloxCookie() {
  if (rbxCookiePromise !== undefined) return rbxCookiePromise;
  const ps = "Add-Type -AssemblyName System.Security; " +
    "$j = Get-Content (Join-Path $env:LOCALAPPDATA 'Roblox\\LocalStorage\\RobloxCookies.dat') -Raw | ConvertFrom-Json; " +
    "$p = [System.Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($j.CookiesData), $null, 'CurrentUser'); " +
    "$t = [Text.Encoding]::UTF8.GetString($p); " +
    "if ($t -match \"\\.ROBLOSECURITY`t([^`t`r`n]+)\") { [Console]::Out.Write($Matches[1].Trim()) }";
  rbxCookiePromise = new Promise((resolve) => {
    require('child_process').execFile('powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', ps],
      { encoding: 'utf8', timeout: 10000, windowsHide: true },
      (err, stdout) => {
        if (err) { resolve(null); return; }   // no Roblox install / locked file -> anonymous fetches only
        const out = stdout.trim();
        resolve(out.length > 50 ? out : null);
      });
  });
  return rbxCookiePromise;
}

// Roblox asset resolve: v1 endpoint -> 302 CDN location -> bytes (v1, NOT v2: v2 is aggressively
// IP-rate-limited). Cookie goes ONLY to assetdelivery (redirect followed manually, so the CDN
// request carries no auth). Retries on 429 with growing backoff; writes the cache on success.
async function fetchAssetBytes(id, cacheDir, ext, placeId) {
  const ck = await getRobloxCookie();
  const metaHeaders = { ...MESH_UA };
  if (ck) metaHeaders.Cookie = '.ROBLOSECURITY=' + ck;
  const pid = placeId || assetPlaceId;
  if (pid) metaHeaders['Roblox-Place-Id'] = String(pid);   // authorize experience-restricted assets
  for (let attempt = 0; attempt < 4; attempt++) {
    const meta = await httpsGet('https://assetdelivery.roblox.com/v1/asset/?id=' + id, metaHeaders);
    if (meta.status === 429) { backoff = Math.min(8000, (backoff || 500) * 2); await new Promise((r) => setTimeout(r, backoff)); continue; }
    let buf;
    if (meta.status >= 300 && meta.status < 400) {
      const loc = meta.headers.location;                   // absolute CDN url (fts.rbxcdn.com/...)
      if (!loc) throw new Error('v1 redirect without location');
      const res = await httpsGet(loc, MESH_UA);            // no cookie to the CDN
      if (res.status === 429) { backoff = Math.min(8000, (backoff || 500) * 2); await new Promise((r) => setTimeout(r, backoff)); continue; }
      if (res.status < 200 || res.status >= 300) throw new Error('cdn http ' + res.status);
      buf = res.body;
    } else if (meta.status >= 200 && meta.status < 300) {
      buf = meta.body;                                      // v1 served the bytes inline
    } else {
      throw new Error('v1 http ' + meta.status);
    }
    if (buf[0] === 0x1f && buf[1] === 0x8b) buf = zlib.gunzipSync(buf);  // CDN gzip via ?encoding=gzip
    fs.mkdirSync(cacheDir, { recursive: true });
    fs.writeFileSync(path.join(cacheDir, id + ext), buf);
    return buf;
  }
  throw Object.assign(new Error('rate-limited'), { rateLimited: true });
}

module.exports = { MESH_UA, httpsGet, getBackoff, decayBackoff, setAssetPlaceId, getRobloxCookie, fetchAssetBytes };
