# Installing the Stream Radar

The radar is two pieces that talk over file IPC:

| Piece | Runs in | Job |
|---|---|---|
| [`stream.lua`](stream.lua) | Serotonin (Scripting tab) | Scans the live world and writes `meta.json` / `map.json` / `players.json` to `C:/Serotonin/files/stream/` |
| [`stream-viewer/`](stream-viewer/) | Electron (Node.js) | Watches that folder and renders the 3D radar; optionally serves it to browsers on your LAN |

The viewer also writes back (`config.json`) so stream rates, scan radius, and map rescan can be
tuned live from its *Stream* panel — no script editing needed.

Install order doesn't matter; each side waits for the other.

---

## 1. Requirements

- **Windows** with **Serotonin** installed (default `C:/Serotonin`) and Roblox. The viewer must run
  on the same machine as Serotonin — it reads `C:/Serotonin/files/stream/` directly. (Browsers on
  *other* devices can connect remotely once hosting is on — see [Hosting](#hosting).)
- **Node.js 18 or newer** with npm — get the LTS from [nodejs.org](https://nodejs.org). Verify:

  ```powershell
  node -v
  npm -v
  ```

- **Disk space:** `npm install` pulls Electron + three.js (a few hundred MB). The mesh/texture
  caches grow over time as maps are fetched (tens of MB per game, kept permanently so each map
  only pays the network cost once).
- **Optional — a Roblox login in the official client.** Most game meshes are access-protected;
  the viewer authenticates by decrypting the Roblox client's own session cookie
  (`RobloxCookies.dat`, DPAPI) at startup. No login on the machine → protected meshes render as
  their bounding boxes instead. The cookie stays in memory and is only ever sent to
  `assetdelivery.roblox.com`.

## 2. Get the files

Clone the repo (or download it as a zip and extract). The folder can live anywhere — nothing in
it is path-sensitive except the Serotonin `files/stream` directory, which is found automatically:

```powershell
git clone https://github.com/mixercodes/serotonin-scripts
cd serotonin-scripts/stream-radar
```

## 3. Install the viewer

```powershell
cd stream-viewer
npm install
```

This installs Electron (the desktop shell) and three.js (the renderer). One-time, per machine.

## 4. Install the Lua side

Copy [`stream.lua`](stream.lua) into your Serotonin scripts folder so it shows up in the
Scripting tab:

```powershell
Copy-Item stream.lua C:/Serotonin/scripts/
```

Or skip the copy and fetch it remotely from any script slot:

```lua
http.Get("https://raw.githubusercontent.com/mixercodes/serotonin-scripts/master/stream-radar/stream.lua", {}, function(body)
    loadstring(body)()
end)
```

## 5. First run

1. Start Roblox, inject Serotonin, join a game.
2. In Serotonin's **Scripting** tab, load `stream.lua`.
3. In `stream-viewer/`, run:

   ```powershell
   npm start
   ```

A window opens and the status line (top left) walks through the boot:

```
no signal  →  in menu / loading map…  →  live · place <id>
```

Within a few seconds you should see the map as boxes and every player as a skeleton. Steps 2 and 3
work in either order — the viewer sits at `no signal` until the stream appears.

**Re-running `stream.lua`** (after a game change, etc.) is always safe: a generation guard makes
the newest instance supersede any older one. The one exception: a copy loaded *before* the guard
existed keeps writing until Roblox restarts — if the map looks like an old format, restart Roblox
once.

## 6. Serotonin not at C:/Serotonin?

Point the viewer at your install's `files/stream` folder with the `STREAM_DIR` environment
variable:

```powershell
$env:STREAM_DIR = "D:/Serotonin/files/stream"; npm start
```

## 7. Hosting (browser / LAN) <a name="hosting"></a>

Hosting is off by default. Turn it on with launch flags:

```powershell
npm start -- --host=localhost          # http://127.0.0.1:8137 — this machine only
npm start -- --host=lan                # http://<your-LAN-ip>:8137 — any device on your network
npm start -- --host=lan --port=9000    # custom port (default 8137)
```

- The Electron window always opens; hosting is additive. The exact reachable URLs are printed to
  the console on startup. If the port can't be bound, the window title shows **hosting FAILED**
  and the console says why.
- **First `--host=lan` run:** Windows Firewall will ask — allow access on **Private** networks.
  Phones/tablets work; they need to be on the same network, and the address is `http://` (not
  `https://`).
- Browser clients get the full radar — map, meshes, textures, players, every visual setting
  (settings are per-browser). Controls that command `stream.lua` itself (stream rates, map rescan,
  radius, profiles) are host-only and hidden remotely.
- Mesh/texture fetches from browsers are proxied through the host's disk caches. **Your Roblox
  session cookie never leaves the host process** — remote clients never see it.
- Browser requirements: anything modern (import-map support — Chrome/Edge 89+, Firefox 108+,
  Safari 16.4+). If a browser is too old or an extension blocks scripts, the page's status line
  says so instead of loading.

> **Security:** plain HTTP, no authentication — anyone on the network can view. Use it on your own
> machine/LAN only, and **don't port-forward it** to the internet.

## 8. Real meshes & textures (optional)

Off by default. In the viewer: **Map view → Real meshes** (and its **Textures** sub-toggle).

- First time a map is shown, each unique mesh/texture is fetched from Roblox — throttled, with
  429 backoff — and cached forever in `stream-viewer/mesh-cache/` and `texture-cache/`. Later
  visits to the same game load instantly from disk.
- Parts whose mesh is still loading, failed, or protected (no Roblox login — see
  [Requirements](#1-requirements)) render as their bounding box.
- **Nothing loads at all?** Roblox sometimes rate-limit-blocks an IP on the asset endpoint for
  hours. The viewer remembers blocked ids in `mesh-cache/fetch-state.json` and waits instead of
  refreshing the block; delete that file to force a retry, or run once on a different network —
  the caches are permanent either way.

## 9. Updating

```powershell
git pull
cd stream-radar/stream-viewer
npm install
```

Then re-copy `stream.lua` if you installed it by copy (step 4) and re-load it in Serotonin.
Caches and saved profiles survive updates.

## 10. Uninstalling

Delete the cloned folder — caches (`mesh-cache/`, `texture-cache/`) live inside
`stream-viewer/`. Saved view profiles live next to the stream folder at
`C:/Serotonin/files/radar-profiles/`; delete that too if you want nothing left behind.

## 11. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Status stuck at `no signal` | `stream.lua` isn't running — load it in Serotonin's Scripting tab (in a game, injected). Custom install path? Set `STREAM_DIR` (step 6). |
| `offline (unloaded)` | The script was unloaded cleanly. Re-load it. |
| `stale Ns (roblox closed?)` | Heartbeat stopped >6s — Roblox was closed or froze. Rejoin and re-load the script. |
| `in menu` | Working as intended — you're not in a game world yet. |
| Map looks wrong / old format | A pre-generation-guard copy of `stream.lua` is still writing. Restart Roblox once, re-load. |
| Browser page stuck on `connecting…` | The page's boot failed before the radar could start; the status line names the reason. Usually: browser too old (needs import maps — Chrome/Edge 89+, Firefox 108+, Safari 16.4+) or a script-blocking extension. Hard-reload with Ctrl+F5 after fixing. |
| LAN device can't reach the URL | Same network? `http://` not `https://`? Windows Firewall rule allowed on Private? Right IP (it's printed in the console at startup)? |
| `hosting FAILED` in the window title | The port couldn't be bound — something else is using it, or the port needs elevation. Try `--port=<other>`; the console has the exact error. |
| Meshes stay boxes | *Real meshes* is off, the asset is protected and there's no Roblox login on the machine, or you're rate-limited (see [section 8](#8-real-meshes--textures-optional)). |
| `npm start` fails: electron not found | `npm install` didn't finish — re-run it in `stream-viewer/` and watch for errors. |
| Want more detail | Launch with `RADAR_DIAG=1` to log box/skeleton counts; `npm run mesh -- <meshId>` opens a single-asset mesh inspector. |
