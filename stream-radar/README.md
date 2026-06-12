# Serotonin Stream Radar

A 3D web radar for Serotonin. [`stream.lua`](stream.lua) dumps the live Roblox world to
`files/stream/*.json` over file IPC; the [`stream-viewer/`](stream-viewer/) Electron + Three.js
app renders it — the map as oriented (rotation-correct) boxes and every player as an R6/R15
skeleton drawn through walls.

> **Installing?** [INSTALL.md](INSTALL.md) is the full walkthrough: prerequisites, install, first
> run, browser/LAN hosting, and troubleshooting.

## How it works

```
Serotonin (stream.lua)  ──writes──>  C:/Serotonin/files/stream/
    meta.json     lifecycle + heartbeat
    map.json      oriented boxes {p,u,v,w,c,t?,r?}   (re-scanned every few seconds)
    players.json  R6/R15 skeletons             (~15 Hz)
                          │
                          └── fs.watch + 150ms poll ──>  Electron renderer (Three.js)
```

- **Map** — one `InstancedMesh` of oriented boxes. `part.CFrame`/`Orientation` are unreadable in the
  sandbox, so rotation is recovered from `draw.GetPartCorners`: `center = (c1+c8)/2` and edge vectors
  `u=c2-c1, v=c3-c1, w=c5-c1` give the box's axes + dimensions. Re-scanned every `MAP_RESCAN_MS`
  within `RADIUS` studs of the local player, so in-world changes show up (both tunable live from the
  viewer's *Stream* panel). Part **transparency** carries through (glass renders see-through via
  per-instance alpha; the occlusion fade multiplies into it) and **reflectance** lightens the part
  toward white.
- **Transparency mode** (*Map view → Transparency*) — how changing opacity (glass + the occlusion
  fade) is rendered: **Blended** (default — classic smooth alpha blending, two-pass so faded parts
  never hide what's behind them), **Dithered** (ordered Bayer screen-door — stable pattern, perfect
  depth), or **Hashed** (stochastic alphaHash — order-independent but grainy).
- **Real meshes** (optional, off by default — *Map view → Real meshes*) — MeshParts stream their
  asset id; with this on, the viewer resolves each unique mesh via the Roblox asset endpoint
  (`assetdelivery v1 → CDN`, session-cookie auth when available — see below), parses the `.mesh`
  container into geometry, and renders one
  `InstancedMesh` per asset. Meshes are normalized to a unit box and placed with the same OBB matrix as
  the box path. Fetches are **throttled with 429 backoff** and cached to `mesh-cache/` on disk, so only
  the first encounter of a map pays the network cost; a part whose mesh is still loading, failed, or in
  an unsupported format renders as its bounding box.
  > **Auth:** public assets resolve anonymously, but most game meshes are **protected (401)** — the
  > viewer decrypts the Roblox client's own session cookie (`RobloxCookies.dat`, DPAPI) at startup
  > and authenticates with it. The cookie lives in memory only and is sent only to
  > `assetdelivery.roblox.com`. No Roblox login on this machine -> protected assets stay boxes.
  >
  > **If nothing loads:** Roblox sometimes rate-limit-blocks an IP on this endpoint for a long time
  > (it ignores its own `retry-after`). The viewer remembers rate-limited ids in
  > `mesh-cache/fetch-state.json` and backs off for hours instead of refreshing the block on every
  > rebuild; delete that file to force a retry, or run once on a different network — the disk caches
  > are permanent.
  - **Supported formats:** all of them — v1 (text), v2–v5 (binary), **v6** (the `COREMESH` container,
    reverse-engineered + validated against the local Roblox cache), and **v7** (`COREMESH` with a
    Draco-compressed payload, decoded async via three's WASM `DRACOLoader`; the decoder ships inside
    the three package and is fed to the loader from disk through `THREE.Cache`). Current Roblox
    builds emit mostly v6/v7.
  - **Textures** (sub-toggle of Real meshes) — each MeshPart's `TextureId` is fetched through the same
    throttled/cached pipeline (`texture-cache/`) and applied to its real mesh using the UVs from the
    .mesh file. Parts whose texture is still loading or failed render with their plain colour; the
    part colour tints the texture (Roblox behaviour). Boxes are never textured.
- **Players** — `LineSegments` skeletons, rig auto-detected (R15 if the character has `UpperTorso`).
  Drawn with `depthTest:false` so they're always visible through geometry. Coloured you/enemy/ally.
  Chams have two styles (*Players → Chams → Style*): **Part boxes** (one oriented wire box per body
  part) or **Convex hull** — not 3D wireframe: each limb's corners are projected every frame and
  drawn as a **2D silhouette overlay** (one convex outline per limb — head, torso, each arm, each
  leg — merged into a single ring around the body, with slightly curved corners; no interior face
  lines). Works for R6 and R15; chams fill becomes the union fill of the silhouette. The 2D bounding
  box has matching rounded corners.
- **State** — HUD reflects `meta.json`. Clean unload writes `status=offline`; a Roblox kill is detected
  as a stale heartbeat (>6s) and clears the scene.

## Camera

| Mode | Behaviour |
|---|---|
| **Locked** (default) | Follows the local player from behind+above; yaw tracks the character's facing from the HumanoidRootPart's rotation matrix (`GetBoneRotation`) — sway-free, since animations never rotate the HRP — with skeleton-derived and movement-delta fallbacks. Scroll = zoom, drag = tilt/orbit. Occluders between camera and player fade out. |
| **Freecam** | RMB = look, WASD = move, Q/E = down/up, scroll = dolly. Hold Shift to move faster. |

Press **F** to toggle.

## Colour & opacity model

Every visual feature (skeleton, chams, bounding box, box fill, names, health) has its own colour
picker with an **alpha** channel. For a given player, a feature's colour is resolved as:

- **RGB** comes from a priority: **your colour** (local player, always) → **team colour** (if Team
  colours is on and the player has a team) → **show-hidden colour** (if Show hidden is on and the
  player's `IsVisible` is false) → the feature's own base colour.
- **Alpha** is *always* the feature's own opacity (the alpha on that feature's picker).

So the RGB can be overridden by team/show-hidden/your colour, but the **opacity is per-feature**.
Example: chams set to 30% on a blue team renders as a *see-through blue* (blue from the team, 30%
from the chams opacity). **Outlines** (the black outline on skeleton/chams/box/name/health, including
the name's text-shadow) inherit that same per-feature opacity, so a 30% feature gets a 30% outline.

## Quick start

```bash
cd stream-viewer
npm install
npm start
```

Then load `stream.lua` from Serotonin's Scripting tab (copy it into `C:/Serotonin/scripts/` first).
Either order works — the viewer waits for the stream. Full setup details, hosting, and
troubleshooting: [INSTALL.md](INSTALL.md).

If your Serotonin install isn't at `C:/Serotonin`:

```powershell
$env:STREAM_DIR = "D:/Serotonin/files/stream"; npm start
```

> **Reloading the Lua script:** `stream.lua` uses a generation guard so re-running it supersedes the
> previous instance. A copy loaded *before* the guard existed will keep writing until you restart
> Roblox — if the map looks like the old format, restart Roblox once and reload.

## Hosting (browser / LAN)

The radar can optionally serve itself over HTTP so a browser — on this machine or any device on
your LAN — can open the same live radar:

    npm start -- --host=localhost          # http://127.0.0.1:8137 (this machine only)
    npm start -- --host=lan                # http://<your-LAN-ip>:8137 (any LAN device)
    npm start -- --host=lan --port=9000    # custom port

The Electron window always opens; hosting is additive. The reachable URLs are printed to the
console on startup. Browser clients get the full radar — map, meshes, textures, materials,
players, every visual setting (per-browser) — but controls that command `stream.lua` itself
(stream rates, map rescan, radius, profiles) are host-only and hidden remotely. Mesh/texture
fetches are proxied through the host's disk cache; your Roblox session cookie never leaves the
host process. Browser and firewall notes: [INSTALL.md](INSTALL.md#hosting).

Plain HTTP, no authentication: this is for your own machine/LAN only. Don't port-forward it.

## Diagnostics

- `RADAR_DIAG=1` before `npm start` logs box/skeleton counts to the console.
- `npm run mesh -- <meshId> [textureId] [placeId]` opens a standalone mesh inspector to debug a
  single asset (pass `0` for the texture slot to skip it).
