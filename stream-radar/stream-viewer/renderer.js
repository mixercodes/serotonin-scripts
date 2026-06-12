// renderer.js — Three.js scene mirroring the live Roblox world from stream.lua.
//
//   meta.json     lifecycle/heartbeat -> HUD + stale detection
//   map.json      oriented boxes {p,u,v,w,c} -> rebuilt when content changes
//   players.json  R6/R15 skeletons -> rebuilt every poll, drawn through walls
//
// Coordinate map: Roblox (left-handed) -> Three (right-handed) via (-x, y, -z). Negating two
// axes is a 180-degree rotation (determinant +1), so the world is NOT mirrored. (Negating one
// axis would be a reflection -> left/right mirrored.) Box material stays DoubleSide for safety.
//
// Camera has two modes (toggle F):
//   locked  — follows the local player, yaw from movement facing, behind+above. Occluders
//             between camera and player fade out; the skeleton always draws on top.
//   freecam — RMB look, WASD move, scroll dolly.

import * as THREE from 'three';
import { LineSegments2 } from 'three/addons/lines/LineSegments2.js';
import { LineSegmentsGeometry } from 'three/addons/lines/LineSegmentsGeometry.js';
import { LineMaterial } from 'three/addons/lines/LineMaterial.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { fetchAssetBytes, parseRobloxMesh, decodeDraco, getBackoff, decayBackoff, setAssetPlaceId, setVertLimit } from './assetlib.js';
import { IS_REMOTE, srcRead, srcSig, srcWrite, srcWatch, srcIsWatching, srcPoll, srcStreamDir } from './source.js';

const fs = IS_REMOTE ? null : require('fs');
const path = IS_REMOTE ? null : require('path');

const STREAM_DIR = srcStreamDir();   // '' in a hosted browser — only Electron-guarded code touches it

const STALE_MS = 6000;
const DIAG = !IS_REMOTE && process.env.RADAR_DIAG === '1';

// ---------- user settings (persisted) ----------
const SETTINGS_KEY = 'serotonin-radar-settings';
const settings = Object.assign({
  occlusion: true,    // fade occluders between camera and player
  occStrength: 96,    // 0..100 -> how transparent occluders get (FADE_MIN_ALPHA = 1 - this/100)
  occReach: 8,        // soft margin (studs) beyond a part's surface where the fade ramps in
  transparency: 'blended',  // how changing opacity renders on the map: blended | dithered | hashed
  teamColours: true,  // colour OTHER players by in-game team colour (overrides every base colour)
  localColor: '#ffffff',  // the ONLY factor for the local player's colour
  skeleton: true,         // draw the bone skeleton
  skeletonColor: '#9aa0aa',
  showHidden: false,      // colour occluded (IsVisible=false) other players distinctly
  showHiddenColor: '#e0b020',
  boundingBox: false,     // 2D screen-space box around each player
  boxColor: '#9aa0aa',    // box outline
  boxFill: false,
  boxFillColor: '#9aa0aa55',   // translucent by default (alpha in the colour)
  chams: false,           // wireframe box per body part, through walls (R6 + R15)
  chamsStyle: 'boxes',    // 'boxes' (one wire box per part) | 'hull' (convex hull around the whole body)
  chamsColor: '#9aa0aa',  // chams outline / wireframe
  chamsFill: false,
  chamsFillColor: '#9aa0aa55',
  outlines: { skeleton: true, chams: true, box: true, name: true, health: true },  // black outline per feature
  names: false,           // player name labels above the box
  nameColor: '#ffffff',
  nameMode: 'display',    // 'display' (DisplayName) | 'user' (username)
  localName: false,       // also label the local player
  healthBar: false,       // vertical health bar beside the box
  hpHigh: '#46d369',      // colour at full health (lerps to hpLow as it drops)
  hpLow: '#e0504e',
  followDist: 40,     // locked-camera distance
  sensitivity: 1.0,   // drag sensitivity multiplier
  invertX: false,     // invert horizontal drag (all drag interactions)
  invertY: false,     // invert vertical drag
  lockSmoothing: true,    // smooth the locked camera (position + facing) to absorb gait wobble
  lockSmoothAmount: 1,   // 0..100, higher = smoother/slower follow
  freeSpeed: 220,         // freecam WASD move speed (studs/sec-ish)
  freeDragSmooth: false,  // smooth freecam RMB look
  freeDragSmoothAmount: 50,
  heightCull: false,  // hide map parts above the player (see into indoor scenes from overhead)
  heightCullOffset: 20, // studs above the player's HRP to keep when height-culling
  meshes: false,      // render real mesh geometry — MeshParts AND classic SpecialMeshes (CDN, disk-cached)
  textures: false,    // apply each mesh's TextureId to its real mesh (needs Real meshes on)
  hideFailedMeshes: false, // drop parts whose real mesh can't be fetched instead of box placeholders
  hideUnions: false,  // drop CSG unions (irrecoverable geometry — they only ever render as boxes)
  partDecals: false,  // Decal/Texture images on plain parts' box faces (fetched like mesh textures)
  materials: false,   // real part materials: official texture tiles, neon glow, glass translucency
  renderDist: 8000,   // camera draw distance in studs; 8000 = unlimited (slider max)
  vertLimitOn: false, // cap real-mesh vertex counts (oversized meshes fall back to boxes)
  vertLimit: 200000,  // the cap when vertLimitOn
  lodOn: false,       // distance LOD: beyond lodDist parts keep shapes but drop meshes/decals/textures
  lodDist: 1500,      // LOD cutoff in studs from the camera
  // stream rates — pushed to stream.lua via config.json (it produces players and map at separate rates)
  playerHz: 15,       // player skeleton updates per second
  mapRescanS: 4,      // seconds between map re-scans (the expensive one)
  mapAuto: true,      // auto re-scan the map; off = manual reload only (saves perf on static maps)
  mapNow: 0,          // bumped to Date.now() by the "Reload map now" button to force one scan
  radius: 2000,       // studs around the player included in the map
}, (() => { try { return JSON.parse(localStorage.getItem(SETTINGS_KEY)) || {}; } catch { return {}; } })());
// normalise outlines into a per-feature object (migrates the old boolean; fills any missing keys)
settings.outlines = Object.assign({ skeleton: true, chams: true, box: true, name: true, health: true },
  (settings.outlines && typeof settings.outlines === 'object') ? settings.outlines : {});
function saveSettings() { try { localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings)); } catch {} }

// reverse IPC: push the stream rates to stream.lua via config.json (debounced; ensure dir exists)
let cfgTimer = null;
function writeStreamConfig() {
  clearTimeout(cfgTimer);
  cfgTimer = setTimeout(() => {
    srcWrite('config.json', JSON.stringify({
      player_hz: settings.playerHz, map_rescan_s: settings.mapRescanS, radius: settings.radius,
      map_auto: settings.mapAuto, map_now: settings.mapNow,
      chams: settings.chams,
      materials: settings.materials,        // stream.lua memory-reads mt only when asked
      decals: settings.partDecals,
      classic_meshes: settings.meshes,      // SpecialMesh/CylinderMesh/BlockMesh child scan
    }));
  }, 250);
}
let syncFollowDist = () => {};   // assigned by bindSettings; keeps the distance slider in sync with scroll-zoom

// ---------- theme (separate from settings; saved to its own file) ----------
const THEME_KEY = 'serotonin-radar-theme';
const THEME_DEFAULTS = {
  bg: '#14171c', panel: '#1b1f27', border: '#2c333d',
  text: '#d8dce2', 'text-dim': '#828a96', accent: '#c6ccd6',
  ok: '#cdd3dd', warn: '#9aa0aa', bad: '#6b7079',
};
const theme = Object.assign({}, THEME_DEFAULTS,
  (() => { try { return JSON.parse(localStorage.getItem(THEME_KEY)) || {}; } catch { return {}; } })());
function saveTheme() { try { localStorage.setItem(THEME_KEY, JSON.stringify(theme)); } catch {} }
function applyTheme() {
  const r = document.documentElement.style;
  for (const k in theme) r.setProperty('--' + k, theme[k]);   // CSS accepts #RRGGBBAA
  if (scene) scene.background = new THREE.Color(colorParts(theme.bg)[0]);   // THREE.Color is RGB-only
}

// ---------- profiles (manual save/load; config + theme as SEPARATE files) ----------
const PROFILES_DIR = IS_REMOTE ? '' : path.join(STREAM_DIR, '..', 'radar-profiles');
const pfSafe = (n) => String(n).replace(/[^\w.-]/g, '_');
function listProfiles() {
  if (IS_REMOTE) return [];
  try {
    return fs.readdirSync(PROFILES_DIR)
      .filter((f) => f.endsWith('.config.json'))
      .map((f) => f.slice(0, -'.config.json'.length));
  } catch { return []; }
}
function saveProfile(name) {
  if (IS_REMOTE) return;
  if (!name) return;
  const s = pfSafe(name);
  fs.mkdirSync(PROFILES_DIR, { recursive: true });
  fs.writeFileSync(path.join(PROFILES_DIR, s + '.config.json'), JSON.stringify(settings, null, 2));
  fs.writeFileSync(path.join(PROFILES_DIR, s + '.theme.json'), JSON.stringify(theme, null, 2));
}
function loadProfile(name) {
  if (IS_REMOTE) return;
  const s = pfSafe(name);
  try { Object.assign(settings, JSON.parse(fs.readFileSync(path.join(PROFILES_DIR, s + '.config.json'), 'utf8'))); } catch {}
  try { Object.assign(theme, JSON.parse(fs.readFileSync(path.join(PROFILES_DIR, s + '.theme.json'), 'utf8'))); } catch {}
  saveSettings(); saveTheme();
}
function deleteProfile(name) {
  if (IS_REMOTE) return;
  const s = pfSafe(name);
  try { fs.unlinkSync(path.join(PROFILES_DIR, s + '.config.json')); } catch {}
  try { fs.unlinkSync(path.join(PROFILES_DIR, s + '.theme.json')); } catch {}
}
const AUTOLOAD_KEY = 'serotonin-radar-autoload';
function getAutoLoad() { try { return localStorage.getItem(AUTOLOAD_KEY) || ''; } catch { return ''; } }
function setAutoLoad(n) { try { if (n) localStorage.setItem(AUTOLOAD_KEY, n); else localStorage.removeItem(AUTOLOAD_KEY); } catch {} }

// ---------- scene ----------
const canvas = document.getElementById('app');
if (IS_REMOTE) document.body.classList.add('remote');   // hides host-only sections (stream rates, profiles)
// logarithmicDepthBuffer: the 1..500000 depth range leaves a linear z-buffer ~0.25 studs of
// resolution at 2000 studs out — parts closer together than that z-fight. Log depth keeps the
// relative precision near-constant (~0.001 studs at that range).
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, logarithmicDepthBuffer: true });
renderer.setPixelRatio(window.devicePixelRatio);
renderer.setSize(window.innerWidth, window.innerHeight);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x0a0e14);

const camera = new THREE.PerspectiveCamera(60, window.innerWidth / window.innerHeight, 1, 500000);
camera.position.set(0, 200, 200);

scene.add(new THREE.AmbientLight(0xffffff, 0.9));
const sun = new THREE.DirectionalLight(0xffffff, 0.8);
sun.position.set(0.6, 1, 0.4);
scene.add(sun);

// ---------- map (oriented instanced boxes with per-instance alpha) ----------
// Three selectable renderings of changing opacity (part Transparency + the occlusion fade), each
// with a different artifact — the Transparency dropdown in Map view picks one:
//  - blended:  classic alpha blending, perfectly smooth. Two passes so it can't repeat the old
//              "void under a faded ceiling" bug: fully-opaque instances draw in a normal
//              depth-writing pass; faded ones draw in a second no-depth-write pass that blends
//              over whatever is behind them. (Stacked faded layers can blend slightly out of
//              order — invisible in practice at radar scale.)
//  - dithered: ordered Bayer screen-door — a stable regular pixel pattern instead of noise;
//              depth stays fully correct everywhere.
//  - hashed:   three's alphaHash, stochastic discard — order-independent but visibly grainy.
// two per-instance alpha channels: instAlpha is the part's STREAMED transparency (a t=1 part
// still shows its decals — see dk below); instFade is radar-driven (height cull, occlusion
// fade) and multiplies everything, decals included — a culled roof must take its decals with it.
const MAP_VERT_PATCH = (shader) => {
  shader.vertexShader =
    'attribute float instAlpha;\nvarying float vInstAlpha;\n' +
    'attribute float instFade;\nvarying float vInstFade;\n' +
    shader.vertexShader.replace('void main() {', 'void main() {\n  vInstAlpha = instAlpha;\n  vInstFade = instFade;');
};
const BAYER_GLSL =
  'float bayer2(vec2 a){ a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }\n' +
  'float bayer4(vec2 a){ return bayer2(0.5 * a) * 0.25 + bayer2(a); }\n' +
  'float bayer8(vec2 a){ return bayer4(0.5 * a) * 0.25 + bayer2(a); }\n';
// Roblox-style decal compositing: the image sits ON the part's surface — transparent texels show
// the part's own (instance) colour, opaque texels show the image as-is. The three default instead
// MULTIPLIES the map in (transparent PNG texels carry black RGB -> dark decals) and would tint
// opaque texels by the part colour. Sample at map_fragment, composite AFTER color_fragment so the
// instance colour only affects the uncovered surface. Texture alpha never touches diffuseColor.a
// (the part itself stays opaque under a see-through decal, like the engine).
// tiled modes: 'inst' reads a per-instance repeat attribute (decal Textures: the game supplies
// StudsPerTile per instance, but one face per chunk so one vec2 suffices). 'auto' derives the
// repeat PER FACE in the vertex shader from the instance matrix itself — each box face tiles by
// its own true world dimensions, so material textures never stretch on non-square parts.
const AUTO_TILE_GLSL = (studs, varName) =>
  '  {\n' +
  '  vec3 _ts = vec3(length(instanceMatrix[0].xyz), length(instanceMatrix[1].xyz), length(instanceMatrix[2].xyz));\n' +
  '  vec3 _tn = abs(normal);\n' +
  `  ${varName || 'vInstTile'} = (_tn.x > 0.5 ? _ts.zy : (_tn.y > 0.5 ? _ts.xz : _ts.xy)) / ${studs.toFixed(1)};\n` +
  '  }';
const DECAL_FRAG_PATCH = (shader, tiled, tint, under, opacity) => {
  const uv = tiled ? 'vMapUv * vInstTile' : 'vMapUv';
  // a Decal's own Transparency weakens every texel before compositing (engine semantics:
  // a 0.7-transparency decal reads as a 30%-strength overlay on the surface)
  const opMul = opacity != null && opacity < 1 ? `\n  decalColor.a *= ${opacity.toFixed(3)};` : '';
  if (tiled) {
    const attr = tiled === 'auto' ? '' : 'attribute vec2 instTile;\n';
    const fill = tiled === 'auto' ? AUTO_TILE_GLSL(MAT_STUDS_PER_TILE) : '  vInstTile = instTile;';
    shader.vertexShader = attr + 'varying vec2 vInstTile;\n' +
      shader.vertexShader.replace('void main() {', 'void main() {\n' + fill);
    shader.fragmentShader = 'varying vec2 vInstTile;\n' + shader.fragmentShader;
  }
  if (under) {
    // material ColorMap beneath the decal — its own auto-tiled varying + sampler, so the
    // decal face shows the material wherever the decal texel is transparent
    shader.vertexShader = 'varying vec2 vMatTile;\n' +
      shader.vertexShader.replace('void main() {', 'void main() {\n' + AUTO_TILE_GLSL(MAT_STUDS_PER_TILE, 'vMatTile'));
    shader.fragmentShader = 'uniform sampler2D underMap;\nvarying vec2 vMatTile;\n' + shader.fragmentShader;
  }
  // tint mode (material colormaps): MULTIPLY into the instance colour like the engine tints its
  // material textures by the part Color — three's stock map behaviour, re-done here only so the
  // tiled UV applies. Decal mode: composite OVER the instance colour by texture alpha — with an
  // under-material, tint the surface by the material texel first, then composite the decal.
  const blend = tint
    ? '  diffuseColor.rgb *= decalColor.rgb;'
    : (under
      ? '  diffuseColor.rgb *= texture2D( underMap, vMapUv * vMatTile ).rgb;\n' +
        '  diffuseColor.rgb = mix( diffuseColor.rgb, decalColor.rgb, decalColor.a );'
      : '  diffuseColor.rgb = mix( diffuseColor.rgb, decalColor.rgb, decalColor.a );');
  shader.fragmentShader = shader.fragmentShader
    .replace('#include <map_fragment>',
      `#ifdef USE_MAP\n  vec4 decalColor = texture2D( map, ${uv} );${opMul}\n#endif`)
    .replace('#include <color_fragment>',
      '#include <color_fragment>\n#ifdef USE_MAP\n' + blend + '\n#endif');
};

function makeMapMaterials(mode, tex, tiled, opts) {
  const { tint, unlit, under, opacity } = opts || {};
  // unlit (Neon): MeshBasicMaterial ignores lighting entirely — the instance colour renders at
  // full brightness from every angle, which is how neon reads at radar scale. Same shader chunks,
  // so all the instAlpha/map patches below apply unchanged.
  const Mat = unlit ? THREE.MeshBasicMaterial : THREE.MeshLambertMaterial;
  // decal chunks (textured, non-tint): decal pixels stay visible regardless of the part's own
  // alpha — the engine renders Decal/Texture children at full visibility even on an invisible
  // part (floating signs). Effective per-pixel alpha = max(part alpha, decal texel alpha).
  const dk = !!tex && !tint;
  const aMul = (dk ? 'max(diffuseColor.a * vInstAlpha, decalColor.a)' : 'diffuseColor.a * vInstAlpha') + ' * vInstFade';
  const aInst = (dk ? 'max(vInstAlpha, decalColor.a)' : 'vInstAlpha') + ' * vInstFade';
  const mats = { mode, main: null, blend: null };
  const base = tex ? { side: THREE.DoubleSide, map: tex } : { side: THREE.DoubleSide };
  if (mode === 'hashed') {
    mats.main = new Mat({ ...base, alphaHash: true });
    mats.main.onBeforeCompile = (shader) => {
      MAP_VERT_PATCH(shader);
      if (tex) DECAL_FRAG_PATCH(shader, tiled, tint, under, opacity);
      if (under) shader.uniforms.underMap = { value: under };
      // fold the per-instance alpha into diffuseColor.a BEFORE the alphahash test consumes it
      shader.fragmentShader = 'varying float vInstAlpha;\nvarying float vInstFade;\n' +shader.fragmentShader.replace(
        '#include <alphahash_fragment>',
        `  diffuseColor.a = ${aMul};\n#include <alphahash_fragment>`);
    };
  } else if (mode === 'dithered') {
    mats.main = new Mat(base);
    mats.main.onBeforeCompile = (shader) => {
      MAP_VERT_PATCH(shader);
      if (tex) DECAL_FRAG_PATCH(shader, tiled, tint, under, opacity);
      if (under) shader.uniforms.underMap = { value: under };
      shader.fragmentShader = 'varying float vInstAlpha;\nvarying float vInstFade;\n' +BAYER_GLSL + shader.fragmentShader.replace(
        '#include <alphatest_fragment>',
        `#include <alphatest_fragment>\n  if (${aMul} < bayer8(gl_FragCoord.xy)) discard;`);
    };
  } else {  // blended (default)
    mats.main = new Mat(base);
    mats.main.onBeforeCompile = (shader) => {
      MAP_VERT_PATCH(shader);
      if (tex) DECAL_FRAG_PATCH(shader, tiled, tint, under, opacity);
      if (under) shader.uniforms.underMap = { value: under };
      shader.fragmentShader = 'varying float vInstAlpha;\nvarying float vInstFade;\n' +shader.fragmentShader.replace(
        '#include <alphatest_fragment>',
        `#include <alphatest_fragment>\n  if (${aInst} < 0.999) discard;`);
    };
    mats.blend = new Mat({ ...base, transparent: true, depthWrite: false });
    mats.blend.onBeforeCompile = (shader) => {
      MAP_VERT_PATCH(shader);
      if (tex) DECAL_FRAG_PATCH(shader, tiled, tint, under, opacity);
      if (under) shader.uniforms.underMap = { value: under };
      shader.fragmentShader = 'varying float vInstAlpha;\nvarying float vInstFade;\n' +shader.fragmentShader.replace(
        '#include <alphatest_fragment>',
        `#include <alphatest_fragment>\n  if (${aInst} >= 0.999) discard;\n  diffuseColor.a = ${aMul};`);
    };
  }
  // distinct cache keys: the per-mode shaders differ but share onBeforeCompile structure (textured
  // variants get USE_MAP, so they need their own program — but one program covers all textures)
  const tk = (tex ? '-tex' : '') + (tiled ? '-tiled' + tiled : '') + (tint ? '-tint' : '') + (unlit ? '-unlit' : '') + (under ? '-under' : '')
    + (opacity != null && opacity < 1 ? '-op' + opacity.toFixed(3) : '');
  mats.main.customProgramCacheKey = () => 'map-' + mode + tk + '-main';
  if (mats.blend) mats.blend.customProgramCacheKey = () => 'map-' + mode + tk + '-blend';
  return mats;
}
let mapMats = makeMapMaterials(settings.transparency);

// per-texture material instances (same shader program, different bound texture)
const texMatCache = new Map();   // 'mode|texId[|flags]' -> mats
function texturedMapMats(texId, tex, tiled, tint, under, underId, opacity) {
  const key = settings.transparency + '|' + texId + (tiled ? '|t' + tiled : '') + (tint ? '|n' : '') + (under ? '|u' + underId : '')
    + (opacity != null && opacity < 1 ? '|o' + opacity.toFixed(3) : '');
  let m = texMatCache.get(key);
  if (!m) { m = makeMapMaterials(settings.transparency, tex, tiled, { tint, under, opacity }); texMatCache.set(key, m); }
  return m;
}
// Neon parts: one shared unlit material pair per transparency mode (cached/disposed with texMatCache)
function neonMapMats() {
  const key = settings.transparency + '|__neon';
  let m = texMatCache.get(key);
  if (!m) { m = makeMapMaterials(settings.transparency, null, false, { unlit: true }); texMatCache.set(key, m); }
  return m;
}
// tiling textures need repeat wrap; guarded because needsUpdate re-uploads the bitmap to the GPU,
// and map rebuilds are frequent (LOD rebuilds run continuously while the camera travels)
function repeatWrap(tex) {
  if (tex.wrapS !== THREE.RepeatWrapping) {
    tex.wrapS = THREE.RepeatWrapping; tex.wrapT = THREE.RepeatWrapping; tex.needsUpdate = true;
  }
}

// ---------- part materials (Enum.Material -> radar rendering) ----------
// Verified against create.roblox.com (June 2026): enum values from the Material enum reference;
// texture ids are the OFFICIAL per-material ColorMap asset ids from the materials guide (2022+
// set — what the current engine renders). The engine tints these by the part Color, which is
// exactly Lambert's stock map behaviour (tint mode above). Neon / ForceField / Plastic /
// SmoothPlastic have no ColorMap ("bundled with Studio"): Neon renders unlit (glow), ForceField
// and Glass as translucency, the plastics as the plain instance colour.
const MAT_TEX = {
  512: '9920625290',   // Wood
  528: '9920626778',   // WoodPlanks
  784: '9439430596',   // Marble
  788: '9920482056',   // Basalt
  800: '9920599782',   // Slate
  804: '9920484943',   // CrackedLava
  816: '9920484153',   // Concrete
  820: '9920561437',   // Limestone
  832: '9920550238',   // Granite
  836: '9920579943',   // Pavement
  848: '9920482813',   // Brick
  864: '9920581082',   // Pebble
  880: '9919718991',   // Cobblestone
  896: '9920587470',   // Rock
  912: '9920596120',   // Sandstone
  1040: '9920589327',  // CorrodedMetal
  1056: '10237720195', // DiamondPlate
  1072: '9466552117',  // Foil
  1088: '9920574687',  // Metal
  1280: '9920551868',  // Grass
  1284: '9920557906',  // LeafyGrass
  1296: '9920591683',  // Sand
  1312: '9920517696',  // Fabric
  1328: '9920620284',  // Snow
  1344: '9920578473',  // Mud
  1360: '9920554482',  // Ground
  1376: '9930003046',  // Asphalt
  1392: '9920590225',  // Salt
  1536: '9920555943',  // Ice
  1552: '9920518732',  // Glacier
  2304: '14108651729', // Cardboard
  2305: '14108662587', // Carpet
  2306: '17429425079', // CeramicTiles
  2307: '18147681935', // ClayRoofTiles
  2308: '119722544879522', // RoofShingles
  2309: '14108670073', // Leather
  2310: '14108671255', // Plaster
  2311: '14108673018', // Rubber
};
const MAT_NEON = 288;
// translucent materials -> alpha cap (Glass also has a ColorMap, but at radar scale its defining
// trait is see-through; refraction isn't reproducible under Lambert anyway)
const MAT_SEETHRU = { 1568: 0.45, 1584: 0.35, 2048: 0.55 };   // Glass, ForceField, Water
// material textures tile in world studs. Roblox doesn't document the built-in tile size; 10 studs
// is the Studio MaterialVariant convention and reads right at radar scale.
const MAT_STUDS_PER_TILE = 10;

// switch mode at runtime: new materials, rebuild the chunks against them, drop the old ones
function applyTransparencyMode() {
  if (mapMats && mapMats.mode === settings.transparency) return;
  const old = mapMats, oldTex = [...texMatCache.values()];
  texMatCache.clear();   // textured mats are mode-specific; rebuilt on demand in buildMap
  mapMats = makeMapMaterials(settings.transparency);
  if (lastMapData) buildMap(lastMapData);
  if (old) { old.main.dispose(); if (old.blend) old.blend.dispose(); }
  for (const m of oldTex) { m.main.dispose(); if (m.blend) m.blend.dispose(); }
}

// The map renders as chunks: chunk 0 is the InstancedMesh of plain boxes; with "Real meshes" on,
// each unique MeshPart asset gets its own InstancedMesh chunk (same matrices — mesh geometry is
// normalized to a centered unit box, so the box's OBB matrix maps it exactly into the part).
// Each chunk carries its own occlusion arrays (alpha attribute, base alpha, centers, half-extents).
let mapChunks = [];        // [{mesh, twin, fade, centers, halfExt, count, shared}]
const GROUND_BUFFER = 2.5; // never fade parts whose center is this far below the player (the ground)
const COPLANAR_EPS = 0.03; // per-axis shrink (studs) applied to every instance against z-fighting
let lastMapStr = '';
let lastMapData = null;    // parsed map.json — kept so the meshes toggle / late mesh arrivals can rebuild
let partCount = 0;

// ---------- Roblox mesh fetch + parse (the optional "Real meshes" setting) ----------
// Fetching/parsing/decoding lives in assetlib.js (shared with the standalone mesh inspector).
const MESH_CACHE_DIR = IS_REMOTE ? '' : path.join(__dirname, 'mesh-cache');
const meshGeo = new Map();       // assetId -> {state: 'loading'|'ready'|'failed', geom?}
let meshRebuildTimer = null;
let assetPlaceLocal = null;      // place id currently pushed to assetlib (for experience-restricted assets)

// a fetched mesh arrived after the map was built -> rebuild once the burst settles
function meshArrived() {
  clearTimeout(meshRebuildTimer);
  meshRebuildTimer = setTimeout(() => { if (lastMapData) buildMap(lastMapData); }, 300);
}

// Rate-limit memory: assetdelivery 429-blocks can be LONG-lived (hours+, per IP), and hammering it
// on every map rebuild only refreshes the block. Rate-limited ids are recorded on disk and not
// re-attempted for hours; one hard rate-limit also pauses all fetching for a long cooldown.
const RL_STATE_FILE = IS_REMOTE ? '' : path.join(MESH_CACHE_DIR, 'fetch-state.json');
const RL_ID_COOLDOWN = 6 * 3600e3;     // per-asset: don't re-attempt a rate-limited id for 6h
const RL_GLOBAL_COOLDOWN = 30 * 60e3;  // after a hard rate-limit, pause ALL fetching for 30 min
let rlState = {};
try { rlState = IS_REMOTE ? {} : JSON.parse(fs.readFileSync(RL_STATE_FILE, 'utf8')); } catch { /* first run */ }
let rlGlobalUntil = 0;
function rlRecord(id) {
  rlState[id] = Date.now();
  rlGlobalUntil = Date.now() + RL_GLOBAL_COOLDOWN;
  if (!IS_REMOTE) {
    try {
      fs.mkdirSync(MESH_CACHE_DIR, { recursive: true });
      fs.writeFileSync(RL_STATE_FILE, JSON.stringify(rlState));
    } catch { /* state just lives in memory this session */ }
  }
}
function rlBlocked(id) {
  return Date.now() < rlGlobalUntil || (rlState[id] && Date.now() - rlState[id] < RL_ID_COOLDOWN);
}

// Bounded-concurrency fetch queue with 429 backoff, shared by meshes AND textures. v1 + cookie is
// reliable enough to fetch several at once, so the first sight of a map fills in ~seconds instead of
// one-at-a-time; each asset lands on disk permanently, so only that first sight pays the network
// cost. A disk cache hit skips the queue entirely. The shared backoff still throttles every worker
// if the CDN does start 429-ing.
const ASSET_CONCURRENCY = 6;
const assetQueue = [];
let assetActive = 0;

// progress counters for the HUD: total ever enqueued this session vs finished (success or fail)
let assetTotal = 0;
let assetDone = 0;
const assetsRow = document.getElementById('assets');
let assetHideTimer = null;
function renderAssetProgress() {
  if (!assetsRow) return;
  if (assetTotal === 0) { assetsRow.style.display = 'none'; return; }
  assetsRow.style.display = '';
  const done = assetDone >= assetTotal;
  assetsRow.textContent = done ? `assets ready: ${assetTotal}` : `loading assets: ${assetDone}/${assetTotal}`;
  // 6-wide fetching can finish a small map in under a second; linger on the final count so the
  // indicator is actually seen, then hide and reset for the next burst.
  clearTimeout(assetHideTimer);
  if (done) assetHideTimer = setTimeout(() => {
    assetsRow.style.display = 'none';
    assetTotal = 0; assetDone = 0;
  }, 1500);
}

function enqueueAsset(job, front) {
  // front-of-queue is for player limb/accessory meshes: a first map sight enqueues hundreds of
  // map assets, and mesh-hull chams shouldn't wait behind all of them to stop drawing boxes
  if (front) assetQueue.unshift(job); else assetQueue.push(job);
  assetTotal++;
  renderAssetProgress();
  pumpAssetQueue();
}

function pumpAssetQueue() {
  while (assetActive < ASSET_CONCURRENCY && assetQueue.length) {
    const job = assetQueue.shift();
    assetActive++;
    (async () => {
      try { await job(); decayBackoff(); }
      catch { /* the job records its own failure state */ }
      const b = getBackoff();
      if (b > 0) await new Promise((r) => setTimeout(r, b));
      assetActive--;
      assetDone++;
      renderAssetProgress();
      pumpAssetQueue();
    })();
  }
}

// fetchAssetBytes guarded by the persistent rate-limit cooldown (assetlib has no rl knowledge)
function fetchAsset(id, cacheDir, ext) {
  if (Date.now() < rlGlobalUntil) return Promise.reject(Object.assign(new Error('rate-limit cooldown'), { rateLimited: true }));
  return fetchAssetBytes(id, cacheDir, ext);
}

// Route a parse result: plain geometry -> ready now (returns true); a {draco} sentinel -> async
// decode that flips the entry to ready/failed later (returns false).
function applyParsedMesh(e, id, parsed) {
  if (parsed.draco) {
    decodeDraco(parsed.draco)
      .then((geom) => {
        e.geom = geom;
        e.state = 'ready';
        if (DIAG) console.log(`DIAG mesh ${id} draco decoded: ${geom.getAttribute('position').count} verts`);
        meshArrived();
      })
      .catch((err) => {
        e.state = 'failed';
        if (settings.hideFailedMeshes) meshArrived();   // rebuild to drop the box placeholder
        if (DIAG) console.log(`DIAG mesh ${id} draco failed: ${err.message}`);
      });
    return false;
  }
  e.geom = parsed;
  e.state = 'ready';
  return true;
}

function requestMesh(id, prio) {
  let e = meshGeo.get(id);
  if (e) {
    // a rate-limited failure becomes retryable once its cooldown expires (map rebuilds re-enter here)
    if (e.state === 'failed' && e.rl && !rlBlocked(id)) { meshGeo.delete(id); e = null; }
    else return e;
  }
  e = { state: 'loading' };
  meshGeo.set(id, e);
  // disk cache hit -> no network/queue (v7 still decodes async; the entry stays 'loading' briefly)
  let buf = null;
  if (!IS_REMOTE) { try { buf = fs.readFileSync(path.join(MESH_CACHE_DIR, id + '.mesh')); } catch { /* not cached */ } }
  if (buf) {
    try {
      applyParsedMesh(e, id, parseRobloxMesh(buf));
      return e;
    } catch { /* corrupt cache -> refetch below */ }
  }
  if (rlBlocked(id)) { e.state = 'failed'; e.rl = true; return e; }
  enqueueAsset(async () => {
    try {
      if (applyParsedMesh(e, id, parseRobloxMesh(await fetchAsset(id, MESH_CACHE_DIR, '.mesh')))) meshArrived();
    } catch (err) {
      e.state = 'failed';
      if (err.rateLimited) { e.rl = true; rlRecord(id); }
      if (settings.hideFailedMeshes) meshArrived();   // rebuild to drop the box placeholder
      if (DIAG) console.log(`DIAG mesh ${id} failed: ${err.message}`);
      throw err;
    }
  }, prio);
  return e;
}

// ---------- texture fetch (the optional "Textures" sub-setting of Real meshes) ----------
const TEX_CACHE_DIR = IS_REMOTE ? '' : path.join(__dirname, 'texture-cache');
const texMap = new Map();   // assetId -> {state: 'loading'|'ready'|'failed', tex?}
function requestTexture(id) {
  let e = texMap.get(id);
  if (e) {
    if (e.state === 'failed' && e.rl && !rlBlocked(id)) { texMap.delete(id); e = null; }
    else return e;
  }
  e = { state: 'loading' };
  texMap.set(id, e);
  const file = IS_REMOTE ? '' : path.join(TEX_CACHE_DIR, id + '.img');
  // ImageBitmap content-sniffs the bytes (png/jpeg/webp) and uploads unflipped, which matches
  // Roblox's top-left UV origin — the mesh UVs are used raw (flipY=false).
  const finish = (buf) => createImageBitmap(new Blob([buf]))
    .then((bmp) => {
      const t = new THREE.Texture(bmp);
      t.colorSpace = THREE.SRGBColorSpace;
      t.flipY = false;
      t.needsUpdate = true;
      e.tex = t;
      e.state = 'ready';
      meshArrived();
    })
    .catch((err) => { e.state = 'failed'; if (DIAG) console.log(`DIAG texture ${id} decode failed: ${err.message}`); });
  if (!IS_REMOTE) {
    try { finish(fs.readFileSync(file)); return e; }   // disk hit -> decode async, no network
    catch { /* not cached */ }
  }
  if (rlBlocked(id)) { e.state = 'failed'; e.rl = true; return e; }
  enqueueAsset(async () => {
    try { await finish(await fetchAsset(id, TEX_CACHE_DIR, '.img')); }
    catch (err) {
      e.state = 'failed';
      if (err.rateLimited) { e.rl = true; rlRecord(id); }
      if (DIAG) console.log(`DIAG texture ${id} failed: ${err.message}`);
      throw err;
    }
  });
  return e;
}

// multi-decal faces: bake the stack into one canvas texture (stretch decals only — each layer
// draws full-face with its own opacity, in child order, exactly the engine's stacking). The
// bake is cached by id:tr layer list; flipY=false to match the ImageBitmap pipeline above.
const compTexCache = new Map();
function compositeDecals(ds) {
  const key = 'cmp|' + ds.map((d) => d[1] + ':' + (d[2] || 0)).join('|');
  const hit = compTexCache.get(key);
  if (hit) return { key, tex: hit };
  const layers = [];
  let w = 0, h = 0;
  for (const d of ds) {
    const te = requestTexture(d[1]);
    if (te.state === 'failed') continue;        // dead layer: bake without it
    if (te.state !== 'ready') return null;      // still loading: arrival triggers a rebuild
    const img = te.tex.image;
    layers.push({ img, a: 1 - (d.length === 3 ? d[2] : 0) });
    w = Math.max(w, img.width); h = Math.max(h, img.height);
  }
  if (!layers.length) return null;
  const cv = document.createElement('canvas');
  cv.width = w; cv.height = h;
  const ctx = cv.getContext('2d');
  for (const l of layers) {
    ctx.globalAlpha = l.a;
    ctx.drawImage(l.img, 0, 0, w, h);
  }
  const tex = new THREE.CanvasTexture(cv);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.flipY = false;
  compTexCache.set(key, tex);
  return { key, tex };
}

// ---------- perf knobs: camera draw distance + mesh vertex cap ----------
const RENDER_DIST_MAX = 8000;   // slider max doubles as "unlimited"
function applyRenderDist() {
  camera.far = (settings.renderDist > 0 && settings.renderDist < RENDER_DIST_MAX) ? settings.renderDist : 500000;
  camera.updateProjectionMatrix();
}
function applyVertLimit() {
  const lim = settings.vertLimitOn ? settings.vertLimit : 0;   // 0 -> assetlib default (1M)
  setVertLimit(lim);
  const eff = lim || 1000000;
  // drop entries the new limit re-classifies: ready geoms now oversized, and non-rate-limited
  // failures (typically 'too many verts') that may now parse — both reload from disk, no network
  for (const [k, e] of meshGeo) {
    if (e.state === 'ready' && e.geom && e.geom.getAttribute('position').count > eff) meshGeo.delete(k);
    else if (e.state === 'failed' && !e.rl) meshGeo.delete(k);
  }
  limbPtsCache.clear();   // mesh-hull samples derive from the same parses
  if (lastMapData) buildMap(lastMapData);
}

// ---------- part shapes (streamed sh codes; vertices in ROBLOX part-local coords) ----------
// The instance basis is built from the negated edge vectors, so it maps roblox-local geometry into
// the 180-degree-rotated three world consistently — same reason the symmetric box "just works".
// Winding is irrelevant (map materials are DoubleSide; three's two-sided Lambert flips normals).

// Planar UV projection for non-indexed triangle soup (wedge / corner wedge).
// Axis pick MUST mirror AUTO_TILE_GLSL: |n.x|>0.5 -> (z,y); |n.y|>0.5 -> (x,z); else (x,y).
// This ensures the per-face repeat the shader derives from the instance scale multiplies the
// SAME axes the UVs were authored against — mismatching them stretches material tiles diagonally.
// Vertices occupy the unit cube (positions in [-0.5, 0.5]), so uv = pos + 0.5 maps each face
// to [0,1] regardless of which two axes are chosen. UV direction/mirror don't affect tiling.
function addPlanarUVs(g) {
  const pos = g.getAttribute('position');
  const nrm = g.getAttribute('normal');
  const uv = new Float32Array(pos.count * 2);
  for (let i = 0; i < pos.count; i++) {
    const nx = Math.abs(nrm.getX(i)), ny = Math.abs(nrm.getY(i));
    const px = pos.getX(i), py = pos.getY(i), pz = pos.getZ(i);
    let u, v;
    if (nx > 0.5)      { u = pz + 0.5; v = py + 0.5; }   // x-dominant face -> (z, y)
    else if (ny > 0.5) { u = px + 0.5; v = pz + 0.5; }   // y-dominant face -> (x, z)
    else               { u = px + 0.5; v = py + 0.5; }   // z-dominant face -> (x, y)
    uv[i * 2] = u; uv[i * 2 + 1] = v;
  }
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
}
function wedgeGeometry() {
  // bottom at -Y, vertical back face at +Z, slope from the front-bottom edge to the top-back edge
  const A = [-0.5,-0.5,-0.5], B = [0.5,-0.5,-0.5], C = [0.5,-0.5,0.5], D = [-0.5,-0.5,0.5];
  const E = [-0.5,0.5,0.5], F = [0.5,0.5,0.5];
  const tris = [A,B,C, A,C,D,  D,C,F, D,F,E,  A,B,F, A,F,E,  A,D,E,  B,C,F];
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(tris.flat(), 3));
  g.computeVertexNormals();
  addPlanarUVs(g);
  return g;
}
function cornerWedgeGeometry() {
  // apex above the (+X,-Z) bottom corner — verified against EgoMoose's GJK vertex set
  // (CORNERWEDGE = corners {4,5,6,7,8}: four bottom corners + top vertex (+1,+1,-1)).
  // Two vertical tri faces (+X, -Z), two sloped tris, rectangular bottom.
  const A = [-0.5,-0.5,-0.5], B = [0.5,-0.5,-0.5], C = [0.5,-0.5,0.5], D = [-0.5,-0.5,0.5];
  const G = [0.5,0.5,-0.5];
  const tris = [A,B,C, A,C,D,  B,C,G,  C,D,G,  A,B,G,  A,G,D];
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(tris.flat(), 3));
  g.computeVertexNormals();
  addPlanarUVs(g);
  return g;
}
// three.js primitives author their UVs for the web convention (flipY=true textures, v=1 at the
// image top). Our textures upload UNFLIPPED (Roblox top-left origin, v=0 = top — required for
// mesh UVs), so any three-authored geometry that binds a texture needs its V flipped once.
function flipUVy(geom) {
  const uv = geom.getAttribute('uv');
  if (uv) {
    for (let i = 0; i < uv.count; i++) uv.setY(i, 1 - uv.getY(i));
    uv.needsUpdate = true;
  }
  return geom;
}
// TrussPart lattice: built per quantized SIZE (cached) with uniform strut thickness in stud
// space, then normalized to the unit box so the standard size-scaled instance matrix fits it.
const TRUSS_GEOS = new Map();   // 'WxHxD' -> BufferGeometry
function trussGeometry(dx, dy, dz) {
  const key = dx + 'x' + dy + 'x' + dz;
  let g = TRUSS_GEOS.get(key);
  if (g) return g;
  const pos = [];
  const box = (ax, ay, az, bx, by, bz) => {
    const v = [[ax,ay,az],[bx,ay,az],[bx,by,az],[ax,by,az],[ax,ay,bz],[bx,ay,bz],[bx,by,bz],[ax,by,bz]];
    const Q = [[0,1,2,3],[5,4,7,6],[4,0,3,7],[1,5,6,2],[3,2,6,7],[4,5,1,0]];
    for (const [a,b,c,d] of Q) pos.push(...v[a],...v[b],...v[c],...v[a],...v[c],...v[d]);
  };
  const T = 0.18;   // strut half-thickness in studs
  const bar = (x0,y0,z0,x1,y1,z1) => box(
    Math.min(x0,x1) - (x0 === x1 ? T : 0), Math.min(y0,y1) - (y0 === y1 ? T : 0), Math.min(z0,z1) - (z0 === z1 ? T : 0),
    Math.max(x0,x1) + (x0 === x1 ? T : 0), Math.max(y0,y1) + (y0 === y1 ? T : 0), Math.max(z0,z1) + (z0 === z1 ? T : 0));
  const hx = dx / 2, hy = dy / 2, hz = dz / 2;
  const dims = [dx, dy, dz];
  const L = dims.indexOf(Math.max(...dims));      // long axis: rails run along it
  const h = [hx, hy, hz];
  const [c1, c2] = [0, 1, 2].filter((a) => a !== L);   // cross-section axes
  const pt3 = (l, a, b) => { const p = [0,0,0]; p[L] = l; p[c1] = a; p[c2] = b; return p; };
  for (const sa of [-1, 1]) for (const sb of [-1, 1]) {
    bar(...pt3(-h[L], sa * h[c1], sb * h[c2]), ...pt3(h[L], sa * h[c1], sb * h[c2]));   // 4 corner rails
  }
  const step = 2, n = Math.max(1, Math.round(dims[L] / step));
  for (let i = 0; i <= n; i++) {
    const l = -h[L] + (i * dims[L]) / n;   // rung ring at each 2-stud station
    bar(...pt3(l, -h[c1], -h[c2]), ...pt3(l, h[c1], -h[c2]));
    bar(...pt3(l, -h[c1],  h[c2]), ...pt3(l, h[c1],  h[c2]));
    bar(...pt3(l, -h[c1], -h[c2]), ...pt3(l, -h[c1], h[c2]));
    bar(...pt3(l,  h[c1], -h[c2]), ...pt3(l,  h[c1], h[c2]));
  }
  for (let i = 0; i < pos.length; i += 3) { pos[i] /= dx; pos[i + 1] /= dy; pos[i + 2] /= dz; }
  g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.computeVertexNormals();
  TRUSS_GEOS.set(key, g);
  return g;
}
const lodBuildPos = new THREE.Vector3();   // camera position at the last map build (LOD rebuild trigger)
const SHAPE_GEOS = {};   // sh code -> template geometry (cloned per chunk for its own instAlpha)
function shapeGeo(code) {
  let g = SHAPE_GEOS[code];
  if (g) return g;
  if (code === 0) g = new THREE.SphereGeometry(0.5, 16, 12);
  else if (code === 2) { g = new THREE.CylinderGeometry(0.5, 0.5, 1, 16); g.rotateZ(Math.PI / 2); }  // Part cylinder axis = X
  else if (code === 3) g = wedgeGeometry();
  else if (code === 4) g = cornerWedgeGeometry();
  else if (code === 5) g = new THREE.CylinderGeometry(0.5, 0.5, 1, 16);                              // classic CylinderMesh axis = Y
  else if (code === 6) g = new THREE.SphereGeometry(0.5, 16, 12);                                    // ellipsoid (SpecialMesh Sphere/Head): stretches freely
  else g = new THREE.BoxGeometry(1, 1, 1);
  SHAPE_GEOS[code] = g;
  return g;
}

// Roblox NormalId -> three BoxGeometry group index ([+x,-x,+y,-y,+z,-z]). Geometry coordinates
// ARE part-local coordinates (the x/z negation lives in the instance BASIS, which rotates the
// whole world 180° consistently) — so the face mapping is identity: Right(+X)->group0, etc.
// Verified: a turning player's corner basis tracks continuously and is right-handed for every
// part, with u,v,w = +X,+Y,+Z (HRP body-axes test), so no per-face sign flip exists.
const FACE_TO_GROUP = { 0: 0, 1: 2, 2: 4, 3: 1, 4: 3, 5: 5 };   // Right,Top,Back,Left,Bottom,Front

const _m = new THREE.Matrix4();
const _u = new THREE.Vector3();
const _v = new THREE.Vector3();
const _w = new THREE.Vector3();
const _pos = new THREE.Vector3();
const _col = new THREE.Color();
const _white = new THREE.Color(1, 1, 1);

function buildMap(map) {
  lastMapData = map;
  // Push the place context to the asset fetcher before any requestMesh/requestTexture: experience-
  // restricted assets 403 without it. On a place change, drop failed (non-rl) entries so assets that
  // 403'd under the old/absent place context are retried with the new one.
  if (map.place_id && map.place_id !== assetPlaceLocal) {
    assetPlaceLocal = map.place_id;
    setAssetPlaceId(map.place_id);
    // full offload: a new place shares nothing — dispose every cached parse, GPU texture and
    // per-texture material so hours of place-hopping don't accumulate VRAM/heap
    for (const [, e] of meshGeo) if (e.geom) e.geom.dispose();
    meshGeo.clear();
    for (const [, e] of texMap) if (e.tex) e.tex.dispose();
    texMap.clear();
    for (const m of texMatCache.values()) { m.main.dispose(); if (m.blend) m.blend.dispose(); }
    texMatCache.clear();
    limbPtsCache.clear();
  }
  for (const ch of mapChunks) {
    scene.remove(ch.mesh);
    if (ch.twin) { scene.remove(ch.twin); ch.twin.dispose(); }
    if (!ch.shared) ch.mesh.geometry.dispose();   // mesh-chunk geometry is the cached parse — keep it
    ch.mesh.dispose();                            // frees the instance matrix/colour buffers
  }
  mapChunks = [];
  const parts = map.parts || [];
  partCount = parts.length;
  if (parts.length === 0) return;

  // Pre-warm: kick off every unique mesh AND texture fetch up front (request* dedupe internally) so
  // they download in one parallel burst. Otherwise textures only start after their mesh is ready and
  // the group below requests them — a second serial wave that doubles the time to a fully dressed map.
  if (settings.meshes || settings.partDecals || settings.materials) {
    for (const pt of parts) {
      if (settings.meshes && pt.m) requestMesh(pt.m);
      if (settings.meshes && settings.textures && pt.tx) requestTexture(pt.tx);
      if (settings.partDecals && pt.dc) for (const d of pt.dc) requestTexture(d[1]);
      if (settings.materials && pt.mt && MAT_TEX[pt.mt]) requestTexture(MAT_TEX[pt.mt]);
    }
  }

  // group parts: '' = plain boxes; 'M<id>' = a READY real mesh (loading/failed render as boxes;
  // arrival rebuilds via meshArrived), optionally split per texture id or material ('|M<matTex>'
  // = ColorMap auto-tiled through the mesh's own UVs, tinted by part colour); 'S<code>[|tex]' =
  // streamed shape (ball/cylinder/wedge/corner wedge/CylinderMesh/ellipsoid), optionally wrapped
  // in the part's texture; 'D<face:id,...>' = box with decal faces; 'T<tex>' = textured box (a
  // part whose mesh isn't available but whose surface texture is known — without this the texture
  // vanishes).
  const groups = new Map();
  // LOD: beyond the cutoff a part keeps its cheap shape but drops meshes/decals/textures
  const lodCap = settings.lodOn ? settings.lodDist * settings.lodDist : Infinity;
  lodBuildPos.copy(camera.position);
  let hiddenFailed = 0, hiddenUnions = 0;
  for (const pt of parts) {
    let key = '';
    let far = false;
    // a part whose real mesh failed to fetch (403'd game asset, bad parse) would render as a box
    // placeholder — optionally drop it entirely. Near AND far, so LOD doesn't pop it back in.
    if (settings.hideFailedMeshes && settings.meshes && pt.m && requestMesh(pt.m).state === 'failed') { hiddenFailed++; continue; }
    // CSG unions only ever render as bounding boxes (their geometry isn't fetchable) — an arch
    // becomes a slab that fills its own opening. Optionally drop them.
    if (settings.hideUnions && pt.un) { hiddenUnions++; continue; }
    if (lodCap < Infinity) {
      const dx = -pt.p[0] - camera.position.x, dy = pt.p[1] - camera.position.y, dz = -pt.p[2] - camera.position.z;
      far = dx * dx + dy * dy + dz * dz > lodCap;
    }
    const mt = settings.materials ? (pt.mt || 0) : 0;
    if (pt.sh === 7) {
      // trusses get per-size lattice geometry (a stretched unit lattice would distort the
      // strut thickness) — quantize so same-sized trusses share one chunk
      const q = (v) => Math.max(0.5, Math.round(Math.hypot(v[0], v[1], v[2]) * 2) / 2);
      key = 'S7|' + q(pt.u) + 'x' + q(pt.v) + 'x' + q(pt.w);
    } else if (mt === MAT_NEON) {
      // neon hides textures/decals in-engine and ignores lighting — unlit chunk, near AND far
      // (a glowing beacon should glow at distance; it costs no texture work). Neon MeshParts
      // keep their real mesh but render unlit.
      if (!far && settings.meshes && pt.m && requestMesh(pt.m).state === 'ready') key = 'M' + pt.m + '|N';
      else key = pt.sh != null ? 'NS' + pt.sh : 'N';
    } else if (!far && settings.meshes && pt.m && requestMesh(pt.m).state === 'ready') {
      key = 'M' + pt.m;
      if (settings.textures && pt.tx) key += '|' + pt.tx;
      else if (MAT_TEX[mt]) key += '|M' + MAT_TEX[mt];
    } else if (!far) {
      // surface-texture fallback: the part's own texture, else its first decal
      const tex = (settings.meshes && settings.textures && pt.tx) ? pt.tx
        : (settings.partDecals && pt.dc && pt.dc.length ? pt.dc[0][1] : null);
      if (pt.sh != null) key = 'S' + pt.sh + (tex ? '|' + tex : (MAT_TEX[mt] ? '|M' + MAT_TEX[mt] : ''));
      else if (settings.partDecals && pt.dc) key = 'D' + pt.dc.map((d) => d.join(':')).sort().join(',') + (MAT_TEX[mt] ? '|X' + mt : '');
      else if (tex) key = 'T' + tex;
      else if (MAT_TEX[mt]) key = 'X' + mt;   // plain box wearing its official material texture, tiled
    } else if (pt.sh != null) {
      key = 'S' + pt.sh;   // far: bare shape, no texture work (material textures drop with LOD too)
    }
    const g = groups.get(key);
    if (g) g.push(pt); else groups.set(key, [pt]);
  }

  const usedGeoms = new Set();
  for (const [key, list] of groups) {
    const kind = key.charAt(0);
    let shared = false;
    let geom;
    let mats = mapMats;
    let matArr = null, blendArr = null;   // decal chunks: per-face (BoxGeometry group) materials
    let native = null;                    // mesh chunks: pre-normalization extents for SpecialMesh scaling
    let center = null;                    // mesh chunks: pre-normalization bbox centre (FileMesh origin offset)
    let shCode = null;                    // shape chunks: streamed sh code (Roblox sizing semantics below)
    let tiled = false;                    // decal chunks: any Texture-tiled face (per-instance repeat attribute)
    if (kind === 'M') {
      const sep = key.indexOf('|');
      const mid = sep > 0 ? key.slice(1, sep) : key.slice(1);
      const tx = sep > 0 ? key.slice(sep + 1) : null;
      geom = meshGeo.get(mid).geom;
      native = geom.userData.size;
      center = geom.userData.center;
      shared = true;
      // same base mesh split across texture groups: the 2nd+ chunk clones the geometry so each
      // keeps its own instAlpha attribute (clones are disposed on rebuild, the cached parse isn't)
      if (usedGeoms.has(mid)) { geom = geom.clone(); shared = false; }
      else usedGeoms.add(mid);
      // textured chunks get their own material with the map bound; until the texture arrives (or if
      // it fails) the chunk renders untextured, and arrival rebuilds via meshArrived. Meshes with no
      // uv attribute stay untextured — binding a map to them samples garbage ("texture never applies").
      // 'M'-prefixed tx = material ColorMap auto-tiled by world studs through the mesh's own UVs,
      // tinted by part colour. Do NOT flipUVy mesh geometry — parses are Roblox-convention and shared.
      if (tx === 'N') mats = neonMapMats();   // neon MeshPart: real mesh, unlit, no texture
      else if (tx) {
        const matTint = tx.charCodeAt(0) === 77;   // 'M'
        const texId = matTint ? tx.slice(1) : tx;
        const te = requestTexture(texId);
        if (te.state === 'ready' && geom.getAttribute('uv')) {
          if (matTint) {
            repeatWrap(te.tex);
            mats = texturedMapMats(texId, te.tex, 'auto', true);
          } else {
            mats = texturedMapMats(texId, te.tex);
          }
        }
      }
    } else if (kind === 'N') {
      // neon box / shape ('N' or 'NS<code>'): plain geometry under the shared unlit material pair
      if (key.length > 1) { shCode = +key.slice(2); geom = shapeGeo(shCode).clone(); }
      else geom = new THREE.BoxGeometry(1, 1, 1);
      mats = neonMapMats();
    } else if (kind === 'X') {
      // plain box wearing its official material ColorMap, TINTED by the part colour (multiply —
      // the engine's material-texture behaviour). 'auto' tiling: the shader derives each face's
      // repeat from the instance matrix, so every face tiles by its own true world dimensions.
      geom = flipUVy(new THREE.BoxGeometry(1, 1, 1));
      const mtTex = MAT_TEX[+key.slice(1)];
      const te = requestTexture(mtTex);
      if (te.state === 'ready') {
        repeatWrap(te.tex);
        mats = texturedMapMats(mtTex, te.tex, 'auto', true);
      }
    } else if (kind === 'S') {
      const sep = key.indexOf('|');
      shCode = +(sep > 0 ? key.slice(1, sep) : key.slice(1));
      if (shCode === 7) {
        // truss: per-size lattice (key carries the quantized dims), uniform strut thickness
        const [tdx, tdy, tdz] = key.slice(sep + 1).split('x').map(Number);
        geom = trussGeometry(tdx, tdy, tdz).clone();
      } else {
        geom = shapeGeo(shCode).clone();   // clone: each chunk owns its instAlpha attribute
        if (sep > 0) {
          // wrap the part's texture around the shape (a striped pole's Texture child would
          // otherwise vanish — shapes can't carry per-face decal materials like boxes do).
          // 'M'-prefixed ids are material ColorMaps: auto-tiled by world studs like the box
          // path ('X'), tinted by the part colour. Non-material textures stretch once (engine
          // semantics: SpecialMesh TextureId and Decals are not tiled).
          let tx = key.slice(sep + 1);
          const matTint = tx.charCodeAt(0) === 77;   // 'M'
          if (matTint) tx = tx.slice(1);
          const te = requestTexture(tx);
          if (te.state === 'ready' && geom.getAttribute('uv')) {
            flipUVy(geom);   // the clone's UVs only — the cached template stays untouched
            if (matTint) repeatWrap(te.tex);
            mats = texturedMapMats(tx, te.tex, matTint ? 'auto' : false, matTint);
          }
        }
      }
    } else if (kind === 'T') {
      geom = flipUVy(new THREE.BoxGeometry(1, 1, 1));
      const tx = key.slice(1);
      const te = requestTexture(tx);
      if (te.state === 'ready') mats = texturedMapMats(tx, te.tex);
    } else if (kind === 'D') {
      geom = flipUVy(new THREE.BoxGeometry(1, 1, 1));
      // Texture children tile at StudsPerTile (4-element dc entries); Decals stretch once.
      // Tiled chunks use a shader variant reading a per-instance repeat (face size / tile size).
      tiled = list[0].dc.some((d) => d.length >= 4);
      // decal over material: the non-decal faces wear the part's material ColorMap (tinted,
      // auto-tiled) so a decal'd brick wall stays brick on its other five faces. On the decal
      // face itself transparent decal texels show the plain part colour — a one-texture
      // approximation of the engine's decal-over-material compositing.
      let dBase = mapMats, underTex = null, underId = null;
      const dmt = settings.materials ? (list[0].mt || 0) : 0;
      if (MAT_TEX[dmt]) {
        const dte = requestTexture(MAT_TEX[dmt]);
        if (dte.state === 'ready') {
          repeatWrap(dte.tex);
          dBase = texturedMapMats(MAT_TEX[dmt], dte.tex, 'auto', true);
          underTex = dte.tex; underId = MAT_TEX[dmt];
        }
      }
      matArr = new Array(6).fill(dBase.main);
      blendArr = dBase.blend ? new Array(6).fill(dBase.blend) : null;
      // group by face: a face can carry SEVERAL decals (later children stack on top in-engine,
      // e.g. a poster plus a glass-frame overlay) but a per-face material binds one map — multi-
      // decal faces are baked into a composited texture. All parts in the group share the same
      // face:id:tile set, so the bake is shared too.
      const byFace = new Map();
      for (const d of list[0].dc) {
        const gi = FACE_TO_GROUP[d[0]];
        if (gi == null) continue;
        if (!byFace.has(gi)) byFace.set(gi, []);
        byFace.get(gi).push(d);
      }
      for (const [gi, ds] of byFace) {
        const dTiled = ds.find((d) => d.length >= 4);
        const one = ds.length === 1 ? ds[0] : dTiled;   // single decal, or the tiled one wins its face
        if (one) {
          const te = requestTexture(one[1]);
          if (te.state !== 'ready') continue;
          // tiling is PER FACE: a part can carry a tiling Texture on one face and a stretch-once
          // Decal on another — the chunk-level flag only says "this chunk has an instTile
          // attribute", each face's material tiles only if ITS entry carries StudsPerTile
          const faceTiled = one.length >= 4;
          if (faceTiled) repeatWrap(te.tex);
          // the decal's own Transparency rides the entry tail: Decal [f,id,tr], Texture [f,id,u,v,tr]
          const dtr = one.length === 3 ? one[2] : (one.length >= 5 ? one[4] : 0);
          const tm = texturedMapMats(one[1], te.tex, faceTiled, false, underTex, underId, dtr ? 1 - dtr : 1);
          matArr[gi] = tm.main;
          if (blendArr) blendArr[gi] = tm.blend;
        } else {
          const cmp = compositeDecals(ds);
          if (!cmp) continue;   // a layer still loading — its arrival rebuilds the map
          const tm = texturedMapMats(cmp.key, cmp.tex, false, false, underTex, underId, 1);
          matArr[gi] = tm.main;
          if (blendArr) blendArr[gi] = tm.blend;
        }
      }
    } else {
      geom = new THREE.BoxGeometry(1, 1, 1);
    }
    const alpha = new THREE.InstancedBufferAttribute(new Float32Array(list.length).fill(1), 1);
    geom.setAttribute('instAlpha', alpha);   // replaces the previous build's attribute on shared geometry
    const fade = new THREE.InstancedBufferAttribute(new Float32Array(list.length).fill(1), 1);
    geom.setAttribute('instFade', fade);     // radar-driven cull/fade channel (updateOcclusion writes it)
    let tileAttr = null;
    if (tiled) {
      tileAttr = new THREE.InstancedBufferAttribute(new Float32Array(list.length * 2).fill(1), 2);
      geom.setAttribute('instTile', tileAttr);
    }

    const mesh = new THREE.InstancedMesh(geom, matArr || mats.main, list.length);
    mesh.frustumCulled = false;
    const centers = new Float32Array(list.length * 3);
    const halfExt = new Float32Array(list.length * 9);

    for (let i = 0; i < list.length; i++) {
      const pt = list[i];
      // edge vectors -> basis (normalized) + scale (lengths); x,z negated to three-space
      _u.set(-pt.u[0], pt.u[1], -pt.u[2]);
      _v.set(-pt.v[0], pt.v[1], -pt.v[2]);
      _w.set(-pt.w[0], pt.w[1], -pt.w[2]);
      const lu = _u.length() || 0.01, lv = _v.length() || 0.01, lw = _w.length() || 0.01;
      // render size: part size by default; a SpecialMesh (pt.e) renders at native mesh size x Scale
      // (Roblox FileMesh semantics — NOT scaled to the part); CylinderMesh/BlockMesh Scale (pt.ms
      // without pt.e) multiplies the part size.
      let su = lu, sv = lv, sw = lw;
      // mesh scales may be NEGATIVE (the classic mirror trick) — preserve the sign so wedges
      // and file meshes render mirrored exactly like the engine; only the magnitude is floored
      if (pt.e && native) {
        const msc = pt.ms || [1, 1, 1];
        su = (msc[0] < 0 ? -1 : 1) * Math.max(Math.abs(native[0] * msc[0]), 0.01);
        sv = (msc[1] < 0 ? -1 : 1) * Math.max(Math.abs(native[1] * msc[1]), 0.01);
        sw = (msc[2] < 0 ? -1 : 1) * Math.max(Math.abs(native[2] * msc[2]), 0.01);
      } else if (pt.ms) {
        su *= pt.ms[0]; sv *= pt.ms[1]; sw *= pt.ms[2];
      }
      // sanity: a modifier that blows the part past radar scale (e.g. a ±600 skydome sphere)
      // reverts to the part's own extents instead of swallowing the whole map
      if (Math.abs(su) > 3000 || Math.abs(sv) > 3000 || Math.abs(sw) > 3000) { su = lu; sv = lv; sw = lw; }
      // Roblox shape sizing: a Ball renders as a sphere of diameter min(size); a Part Cylinder
      // keeps X as its height but the cross-section is circular at diameter min(Y,Z)
      if (shCode === 0) { const d = Math.min(su, sv, sw); su = d; sv = d; sw = d; }
      else if (shCode === 2) { const d = Math.min(sv, sw); sv = d; sw = d; }
      // store half-edge vectors (before normalizing) for anisotropic occlusion
      const b = i * 9;
      halfExt[b] = _u.x * 0.5; halfExt[b + 1] = _u.y * 0.5; halfExt[b + 2] = _u.z * 0.5;
      halfExt[b + 3] = _v.x * 0.5; halfExt[b + 4] = _v.y * 0.5; halfExt[b + 5] = _v.z * 0.5;
      halfExt[b + 6] = _w.x * 0.5; halfExt[b + 7] = _w.y * 0.5; halfExt[b + 8] = _w.z * 0.5;
      _u.divideScalar(lu); _v.divideScalar(lv); _w.divideScalar(lw);
      _pos.set(-pt.p[0], pt.p[1], -pt.p[2]);
      // part-local displacements ride the basis: DataModelMesh.Offset (pt.mo, studs), plus a
      // FileMesh's authored-origin shift — Roblox places a SpecialMesh by its ORIGIN at the part
      // centre, but the cached parse is bbox-centred, so add back bbox-centre x Scale
      {
        let ox = 0, oy = 0, oz = 0;
        if (pt.mo) { ox = pt.mo[0]; oy = pt.mo[1]; oz = pt.mo[2]; }
        if (pt.e && center) {
          const msc = pt.ms || [1, 1, 1];
          ox += center[0] * msc[0]; oy += center[1] * msc[1]; oz += center[2] * msc[2];
        }
        if (ox || oy || oz) _pos.addScaledVector(_u, ox).addScaledVector(_v, oy).addScaledVector(_w, oz);
      }
      // shrink each instance a hair so flush part faces don't share the exact same plane
      // (coplanar faces z-fight at any depth precision); jitter the amount per instance so
      // two touching faces never separate by exactly zero. Clamped so thin sheets survive.
      // Jitter hashes the part's POSITION (not its index) so a part keeps the same exact
      // size across rebuilds instead of subtly changing on every rescan.
      const jt = Math.abs(Math.sin(pt.p[0] * 12.9898 + pt.p[1] * 78.233 + pt.p[2] * 37.719));
      const eps = COPLANAR_EPS * (0.6 + 0.8 * jt);
      _m.makeBasis(_u, _v, _w);
      _m.scale(new THREE.Vector3(
        Math.max(su - eps, su * 0.7), Math.max(sv - eps, sv * 0.7), Math.max(sw - eps, sw * 0.7)));
      _m.setPosition(_pos);
      mesh.setMatrixAt(i, _m);
      _col.setRGB(pt.c[0] / 255, pt.c[1] / 255, pt.c[2] / 255, THREE.SRGBColorSpace);
      // reflectance -> lighten toward white (Lambert has no per-instance specular; a brightness
      // lift is how a shiny part reads at radar scale)
      if (pt.r) _col.lerp(_white, Math.min(1, pt.r) * 0.6);
      mesh.setColorAt(i, _col);
      // part transparency -> base alpha; alphaHash renders it see-through with correct depth.
      // Translucent materials (Glass/ForceField) cap the alpha — their defining engine trait.
      let a = pt.t ? Math.max(0, 1 - pt.t) : 1;
      if (settings.materials && pt.mt && MAT_SEETHRU[pt.mt]) a = Math.min(a, MAT_SEETHRU[pt.mt]);
      alpha.array[i] = a;
      // tiled decal chunks: per-instance repeat = face size in studs / StudsPerTile.
      // Face axes: ±X faces span (Z,Y), ±Y span (X,Z), ±Z span (X,Y).
      if (tileAttr) {
        const d4 = pt.dc.find((d) => d.length >= 4);
        if (d4) {
          const f = d4[0] % 3;
          const du = f === 0 ? lw : lu;
          const dv = f === 1 ? lw : lv;
          tileAttr.array[i * 2] = Math.max(du / d4[2], 0.01);
          tileAttr.array[i * 2 + 1] = Math.max(dv / d4[3], 0.01);
        }
      }
      centers[i * 3] = _pos.x; centers[i * 3 + 1] = _pos.y; centers[i * 3 + 2] = _pos.z;
    }
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    scene.add(mesh);
    // blended mode pass 2: same instances under the blend-only material, sharing the instance
    // buffers (matrices/colours) and the geometry's instAlpha — occlusion writes update both passes
    let twin = null;
    if (mats.blend) {
      twin = new THREE.InstancedMesh(geom, blendArr || mats.blend, list.length);
      twin.frustumCulled = false;
      twin.instanceMatrix = mesh.instanceMatrix;
      twin.instanceColor = mesh.instanceColor;
      scene.add(twin);
    }
    mapChunks.push({ mesh, twin, fade, centers, halfExt, count: list.length, shared });
  }
  occSig = '';   // force the occlusion pass to re-run against the fresh alpha arrays
  if (DIAG) console.log(`DIAG map: ${parts.length} parts in ${mapChunks.length} chunk(s)`
    + (hiddenFailed ? ` (${hiddenFailed} failed-mesh parts hidden)` : '')
    + (hiddenUnions ? ` (${hiddenUnions} unions hidden)` : ''));
}

// ---------- players (skeletons, drawn through walls) ----------
const PAIRS_R15 = [
  ['Head', 'UpperTorso'], ['UpperTorso', 'LowerTorso'],
  ['UpperTorso', 'LeftUpperArm'], ['LeftUpperArm', 'LeftLowerArm'], ['LeftLowerArm', 'LeftHand'],
  ['UpperTorso', 'RightUpperArm'], ['RightUpperArm', 'RightLowerArm'], ['RightLowerArm', 'RightHand'],
  ['LowerTorso', 'LeftUpperLeg'], ['LeftUpperLeg', 'LeftLowerLeg'], ['LeftLowerLeg', 'LeftFoot'],
  ['LowerTorso', 'RightUpperLeg'], ['RightUpperLeg', 'RightLowerLeg'], ['RightLowerLeg', 'RightFoot'],
];
// Accurate R6 skeleton from streamed part boxes (chams pb). Each limb is traced along the part's LOCAL
// Y axis (v = c3-c1 = sizeY): vertical for the torso, the length for arms/legs, and it follows animation.
// Using the "longest" edge instead would pick the torso's WIDTH (it's 2x2), drawing the spine sideways.
// Which end of each axis is the JOINT is fixed anatomy, not a guess: GetPartCorners orders corners
// deterministically from the part's CFrame, so v always points to the part's local +Y end — and in R6
// that end IS the joint (torso top = neck, arm/leg top = shoulder/hip) in every pose, because
// animations rotate the whole part. (Runtime-verified: c3-c1 ⋅ part up = +1.000 across players;
// the old nearest-end proximity pick flipped to the hand when an arm swung up toward the neck.)
// box = [px,py,pz, u..., v..., w...] in roblox coords -> three (-x, y, -z).
function boxEnds(box) {
  const c = [-box[0], box[1], -box[2]];
  const v = [-box[6], box[7], -box[8]];
  return {
    c,
    a: [c[0] + v[0] / 2, c[1] + v[1] / 2, c[2] + v[2] / 2],   // local +Y end = the joint
    b: [c[0] - v[0] / 2, c[1] - v[1] / 2, c[2] - v[2] / 2],   // local -Y end (hand/foot/pelvis)
  };
}
function r6SkeletonFromPb(pb) {
  const out = [];
  const seg = (A, C) => out.push(A[0], A[1], A[2], C[0], C[1], C[2]);
  const ends = {};
  for (const n of ['Head', 'Torso', 'Left Arm', 'Right Arm', 'Left Leg', 'Right Leg']) if (pb[n]) ends[n] = boxEnds(pb[n]);
  const T = ends['Torso']; if (!T) return out;
  const neck = T.a, hip = T.b;
  seg(neck, hip);                                       // torso spine
  if (ends['Head']) seg(ends['Head'].c, neck);          // head -> neck
  for (const n of ['Left Arm', 'Right Arm']) if (ends[n]) { const L = ends[n]; seg(neck, L.a); seg(L.a, L.b); }   // shoulder->hand
  for (const n of ['Left Leg', 'Right Leg']) if (ends[n]) { const L = ends[n]; seg(hip, L.a); seg(L.a, L.b); }    // hip->foot
  return out;
}

const playerGroup = new THREE.Group();
scene.add(playerGroup);
let playerCount = 0;
const localTarget = new THREE.Vector3();   // local player position (three-space)
let haveLocal = false;
let localFace = null;                      // [fx, fz] roblox-space
let espPlayers = [];                       // per-player {pl, min, max, color} for the HTML overlay (names/health)
let hullPlayers = [];                      // per-player {pl, limbs} for the 2D hull-chams canvas overlay

// shared fat-line material for skeleton outlines (WebGL 1px lines can't be widened any other way)
const outlineMat = new LineMaterial({ color: 0x000000, linewidth: 3.5, depthTest: false, transparent: true });
outlineMat.resolution.set(window.innerWidth, window.innerHeight);
// per-opacity black outline materials (so an outline matches its feature's opacity); pooled, resolution-synced
const outlineMatCache = new Map();
function outlineMaterial(alpha) {
  const key = Math.round(alpha * 100);
  let m = outlineMatCache.get(key);
  if (!m) { m = new LineMaterial({ color: 0x000000, linewidth: 3.5, depthTest: false, transparent: true, opacity: alpha }); m.resolution.set(window.innerWidth, window.innerHeight); m.userData.pooled = true; outlineMatCache.set(key, m); }
  return m;
}

// split "#RRGGBB" / "#RRGGBBAA" into [hex6, alpha 0..1]
function colorParts(s) {
  s = s || '#ffffff';
  if (s.length >= 9) return [s.slice(0, 7), (parseInt(s.slice(7, 9), 16) || 0) / 255];
  return [s.slice(0, 7), 1];
}

// pooled materials keyed by rgba string — avoids allocating/disposing materials per frame; honours alpha
const lineMatCache = new Map(), meshMatCache = new Map();
function lineMat(rgba) {
  let m = lineMatCache.get(rgba);
  if (!m) { const [hex, a] = colorParts(rgba); m = new THREE.LineBasicMaterial({ color: hex, depthTest: false, transparent: true, opacity: a }); m.userData.pooled = true; lineMatCache.set(rgba, m); }
  return m;
}
function meshMat(rgba) {
  let m = meshMatCache.get(rgba);
  if (!m) { const [hex, a] = colorParts(rgba); m = new THREE.MeshBasicMaterial({ color: hex, depthTest: false, transparent: true, opacity: a }); m.userData.pooled = true; meshMatCache.set(rgba, m); }
  return m;
}

// chams: a wireframe box per actual body PART, using its real oriented corners (from
// draw.GetPartCorners, streamed as centre p + edge vectors u,v,w). No orientation guessing -> no spin.
const CHAMS_UNITBOX = new THREE.BoxGeometry(1, 1, 1);
const _cm = new THREE.Matrix4();
const _cpu = new THREE.Vector3(), _cpv = new THREE.Vector3(), _cpw = new THREE.Vector3(), _cpp = new THREE.Vector3(), _csz = new THREE.Vector3();
const _BOXC = [[-1,-1,-1],[1,-1,-1],[1,-1,1],[-1,-1,1],[-1,1,-1],[1,1,-1],[1,1,1],[-1,1,1]];
const _BOXE = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]];
// box = [px,py,pz, ux,uy,uz, vx,vy,vz, wx,wy,wz] in Roblox coords -> three (-x, y, -z)
function pushPartBoxEdges(out, box) {
  const px = -box[0], py = box[1], pz = -box[2];
  const hux = -box[3] / 2, huy = box[4] / 2, huz = -box[5] / 2;
  const hvx = -box[6] / 2, hvy = box[7] / 2, hvz = -box[8] / 2;
  const hwx = -box[9] / 2, hwy = box[10] / 2, hwz = -box[11] / 2;
  const c = [];
  for (const [sx, sy, sz] of _BOXC) c.push(px + sx*hux + sy*hvx + sz*hwx, py + sx*huy + sy*hvy + sz*hwy, pz + sx*huz + sy*hvz + sz*hwz);
  for (const [i, j] of _BOXE) out.push(c[i*3], c[i*3+1], c[i*3+2], c[j*3], c[j*3+1], c[j*3+2]);
}
function partBoxGeo(box) {
  _cpu.set(-box[3], box[4], -box[5]); _cpv.set(-box[6], box[7], -box[8]); _cpw.set(-box[9], box[10], -box[11]);
  const su = _cpu.length() || 0.01, sv = _cpv.length() || 0.01, sw = _cpw.length() || 0.01;
  _cpu.divideScalar(su); _cpv.divideScalar(sv); _cpw.divideScalar(sw);
  _cpp.set(-box[0], box[1], -box[2]);
  _cm.makeBasis(_cpu, _cpv, _cpw); _cm.scale(_csz.set(su, sv, sw)); _cm.setPosition(_cpp);
  return CHAMS_UNITBOX.clone().applyMatrix4(_cm);
}

// convex-hull chams: one hull PER LIMB (head / torso / each arm / each leg), so the drawing traces
// the actual figure instead of blobbing the whole body into a single hull. R15 limb chains (upper +
// lower + hand/foot) fuse into one limb each; R6 parts are literally boxes, so its hulls match the
// body exactly. pb parts not in any group (future rigs/accessories) get their own hull. The hulls
// are NOT 3D geometry: per frame the limb's corners are projected and a 2D convex outline is drawn
// on the overlay canvas (see drawHullChams).
function pushPartBoxCorners(out, box) {
  const px = -box[0], py = box[1], pz = -box[2];
  const hux = -box[3] / 2, huy = box[4] / 2, huz = -box[5] / 2;
  const hvx = -box[6] / 2, hvy = box[7] / 2, hvz = -box[8] / 2;
  const hwx = -box[9] / 2, hwy = box[10] / 2, hwz = -box[11] / 2;
  for (const [sx, sy, sz] of _BOXC) {
    out.push(px + sx*hux + sy*hvx + sz*hwx, py + sx*huy + sy*hvy + sz*hwy, pz + sx*huz + sy*hvz + sz*hwz);
  }
}
const HULL_GROUPS = {
  R15: [
    ['Head'],
    ['UpperTorso', 'LowerTorso'],
    ['LeftUpperArm', 'LeftLowerArm', 'LeftHand'],
    ['RightUpperArm', 'RightLowerArm', 'RightHand'],
    ['LeftUpperLeg', 'LeftLowerLeg', 'LeftFoot'],
    ['RightUpperLeg', 'RightLowerLeg', 'RightFoot'],
  ],
  R6: [['Head'], ['Torso'], ['Left Arm'], ['Right Arm'], ['Left Leg'], ['Right Leg']],
};
// Mesh-hull chams: per-limb point clouds from the limb's REAL mesh (pb's 13th element is the mesh
// asset id — R15 MeshPart limbs, R6 CharacterMesh package limbs, and accessory handles). The cached
// parse keeps userData.size/center (pre-normalization extents) so pushPartMeshPoints can place it
// either bbox-fit or at native scale; parts without a mesh (or whose mesh is still loading) keep
// their box corners.
// Sampling: a convex hull only needs vertices that are extreme along SOME direction, so instead
// of every-Nth-vertex (which misses extremes and shrinks the silhouette) take the exact argmax
// vertex along each of 64 fibonacci-sphere directions — every kept point is a true extreme.
const limbPtsCache = new Map();   // meshId -> {pts: flat xyz (unit-box coords), native: [x,y,z]} (successes only)
const HULL_DIRS = (() => {
  const dirs = [], N = 64, ga = Math.PI * (3 - Math.sqrt(5));
  for (let i = 0; i < N; i++) {
    const y = 1 - (2 * i + 1) / N, r = Math.sqrt(1 - y * y), t = ga * i;
    dirs.push(Math.cos(t) * r, y, Math.sin(t) * r);
  }
  return dirs;
})();
function meshHullPts(id) {
  let p = limbPtsCache.get(id);
  if (p !== undefined) return p;
  const e = requestMesh(id, true);   // front-of-queue: don't wait behind a map-mesh burst
  // NEVER cache a miss. 'loading' resolves on a later build tick, and a 'failed' entry must keep
  // re-entering requestMesh, which retries rate-limited ids once their cooldown lapses (one 429
  // during a map burst insta-fails every mesh requested for the next 30 min). Caching null here
  // froze those players on the box-corner fallback for the whole session.
  if (e.state !== 'ready') return null;
  const pos = e.geom.getAttribute('position');
  const n = pos.count;
  const picked = new Set();
  for (let d = 0; d < HULL_DIRS.length; d += 3) {
    const dx = HULL_DIRS[d], dy = HULL_DIRS[d + 1], dz = HULL_DIRS[d + 2];
    let best = -Infinity, bi = 0;
    for (let i = 0; i < n; i++) {
      const dot = pos.getX(i) * dx + pos.getY(i) * dy + pos.getZ(i) * dz;
      if (dot > best) { best = dot; bi = i; }
    }
    picked.add(bi);
  }
  const pts = new Float32Array(picked.size * 3);
  let o = 0;
  for (const i of picked) { pts[o++] = pos.getX(i); pts[o++] = pos.getY(i); pts[o++] = pos.getZ(i); }
  p = { pts, native: e.geom.userData.size || null, center: e.geom.userData.center || null };
  limbPtsCache.set(id, p);
  return p;
}
const _hv = new THREE.Vector3();
// Two mesh-placement modes, chosen by pb entry length:
//  - 13 elements (id only): BBOX-FIT — the engine fits the mesh's bounding box to the part Size
//    (R15 MeshPart limbs, modern MeshPart accessory handles). Points map strictly inside the box.
//  - 16 elements (id + scale): NATIVE-SCALE — the mesh renders at its authored extents x Scale,
//    placed by its authored origin (classic Part+SpecialMesh accessory handles).
//    Native meshes that balloon past the part box (mis-authored gear) fall back to the box corners
//    so one accessory can never write over the whole body.
// R6: packaged limbs (CharacterMesh) and FileMesh heads stream as 16-element native-scale
// entries; default blocky limbs stay plain 12-element boxes — the box IS that silhouette.
function pushPartMeshPoints(out, box) {
  const id = box.length >= 13 ? box[12] : null;
  const mh = (typeof id === 'string') ? meshHullPts(id) : null;
  if (!mh) { pushPartBoxCorners(out, box); return; }
  _cpu.set(-box[3], box[4], -box[5]); _cpv.set(-box[6], box[7], -box[8]); _cpw.set(-box[9], box[10], -box[11]);
  const su0 = _cpu.length() || 0.01, sv0 = _cpv.length() || 0.01, sw0 = _cpw.length() || 0.01;
  _cpu.divideScalar(su0); _cpv.divideScalar(sv0); _cpw.divideScalar(sw0);
  const pcx = -box[0], pcy = box[1], pcz = -box[2];   // part centre (three-space)
  _cpp.set(pcx, pcy, pcz);
  let su = su0, sv = sv0, sw = sw0, native = false;
  if (box.length >= 16 && mh.native) {
    native = true;
    su = Math.max(mh.native[0] * box[13], 0.001);
    sv = Math.max(mh.native[1] * box[14], 0.001);
    sw = Math.max(mh.native[2] * box[15], 0.001);
    // authored origin: the parse is bbox-centred, so shift the placement by centre x Scale
    if (mh.center) _cpp.addScaledVector(_cpu, mh.center[0] * box[13]).addScaledVector(_cpv, mh.center[1] * box[14]).addScaledVector(_cpw, mh.center[2] * box[15]);
  }
  _cm.makeBasis(_cpu, _cpv, _cpw); _cm.scale(_csz.set(su, sv, sw)); _cm.setPosition(_cpp);
  // native meshes are unbounded by construction; reject any limb whose points escape ~2.5x the part
  // box half-diagonal (a ballooned accessory) and fall back to the box silhouette
  const bound = 2.5 * 0.5 * Math.hypot(su0, sv0, sw0);
  const mp = mh.pts, base = out.length;
  for (let i = 0; i < mp.length; i += 3) {
    _hv.set(mp[i], mp[i + 1], mp[i + 2]).applyMatrix4(_cm);
    if (!Number.isFinite(_hv.x) || (native && Math.hypot(_hv.x - pcx, _hv.y - pcy, _hv.z - pcz) > bound)) {
      out.length = base; pushPartBoxCorners(out, box); return;
    }
    out.push(_hv.x, _hv.y, _hv.z);
  }
}
// Group a player's pb into limb point clouds (flat xyz, three-space) for the 2D hull overlay.
// Accessories (@n entries) are mesh-hull only: the box styles (convex hull, part boxes) stay
// body-only, drawing each part's plain streamed box.
function limbClouds(pb, rig, useMesh) {
  const push = useMesh ? pushPartMeshPoints : pushPartBoxCorners;
  const limbs = [], used = new Set();
  for (const group of HULL_GROUPS[rig === 'R15' ? 'R15' : 'R6']) {
    const pts = [];
    for (const n of group) if (pb[n]) { push(pts, pb[n]); used.add(n); }
    if (pts.length) limbs.push(pts);
  }
  for (const n in pb) {
    if (used.has(n) || (!useMesh && n.charCodeAt(0) === 64)) continue;
    const pts = []; push(pts, pb[n]); limbs.push(pts);
  }
  return limbs;
}

function clearGroup(g) {
  for (let i = g.children.length - 1; i >= 0; i--) {
    const o = g.children[i];
    g.remove(o);
    if (o.geometry) o.geometry.dispose();
    if (o.material && o.material !== outlineMat && !o.material.userData.pooled) o.material.dispose();   // keep shared/pooled materials
  }
}

// Unified colour priority for a player's ESP. The local player is ALWAYS its own colour; for others:
// team colour > show-hidden (when occluded) > the supplied base colour.
function withAlpha(hex6, a) { return a >= 0.999 ? hex6 : hex6 + Math.round(a * 255).toString(16).padStart(2, '0'); }
// Resolves a feature's colour for a player. The ALPHA is always the feature's own opacity (from baseHex);
// the RGB comes from the override priority: local (your colour) > team > show-hidden > the feature base.
// So e.g. a low-opacity chams on a blue team renders as see-through blue.
function playerColor(pl, baseHex) {
  const a = colorParts(baseHex)[1];   // the feature's own opacity
  let rgb;
  if (pl.kind === 'local') rgb = colorParts(settings.localColor)[0];          // you = your colour, always
  else if (settings.teamColours && pl.tc) { const v = (1 << 24) | (pl.tc[0] << 16) | (pl.tc[1] << 8) | pl.tc[2]; rgb = '#' + v.toString(16).slice(1); }
  else if (settings.showHidden && pl.vis === false) rgb = colorParts(settings.showHiddenColor)[0];
  else rgb = colorParts(baseHex)[0];
  return withAlpha(rgb, a);
}


// Full player-visual clear: 3D geometry AND the HTML ESP overlay state. clearGroup alone leaves
// espPlayers populated, so name/health/box rows would keep drawing at the last known positions.
// Full map offload (stream stale/offline): chunks, cached parses, GPU textures, materials.
// lastMapStr resets so an identical map.json rebuilds when the stream comes back.
function clearMap() {
  if (!mapChunks.length && !lastMapData) return;
  for (const ch of mapChunks) {
    scene.remove(ch.mesh);
    if (ch.twin) { scene.remove(ch.twin); ch.twin.dispose(); }
    if (!ch.shared) ch.mesh.geometry.dispose();
    ch.mesh.dispose();
  }
  mapChunks = [];
  for (const [, e] of meshGeo) if (e.geom) e.geom.dispose();
  meshGeo.clear();
  for (const [, e] of texMap) if (e.tex) e.tex.dispose();
  texMap.clear();
  for (const m of texMatCache.values()) { m.main.dispose(); if (m.blend) m.blend.dispose(); }
  texMatCache.clear();
  limbPtsCache.clear();
  lastMapData = null;
  lastMapStr = '';
  partCount = 0;
}

function clearPlayers() {
  clearGroup(playerGroup);
  espPlayers = [];
  hullPlayers = [];
  haveLocal = false;
  localFace = null;
  playerCount = 0;
}

function buildPlayers(data) {
  clearGroup(playerGroup);
  haveLocal = false;
  espPlayers = [];
  hullPlayers = [];
  let segs = 0;
  const players = data.players || [];
  for (const pl of players) {
    const b = pl.bones || {};
    // skeleton (drawn through walls). R15 has per-segment bones; R6 traces the limbs from part centres.
    let verts;
    if (pl.rig === 'R15') {
      verts = [];
      for (const [a, c] of PAIRS_R15) { const A = b[a], C = b[c]; if (A && C) verts.push(-A[0], A[1], -A[2], -C[0], C[1], -C[2]); }
    } else {
      // R6: always derived from the real part boxes (streamed for every R6 player)
      verts = (pl.pb && pl.pb['Torso']) ? r6SkeletonFromPb(pl.pb) : [];
    }
    segs += verts.length / 6;
    if (settings.skeleton && verts.length) {
      // black outline behind (fat line) then the coloured skeleton on top
      if (settings.outlines.skeleton) {
        const og = new LineSegmentsGeometry();
        og.setPositions(verts);
        const ol = new LineSegments2(og, outlineMaterial(colorParts(playerColor(pl, settings.skeletonColor))[1]));
        ol.renderOrder = 998;
        playerGroup.add(ol);
      }
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(verts, 3));
      const line = new THREE.LineSegments(geo, lineMat(playerColor(pl, settings.skeletonColor)));
      line.renderOrder = 999;
      playerGroup.add(line);
    }

    // chams: wireframe box per real body part (oriented corners streamed in pl.pb, keyed by part), optional fill.
    // 'hull'/'mesh' styles are not 3D geometry — they queue per-limb point clouds for the 2D overlay
    // canvas ('mesh' samples the limb's real MeshPart geometry instead of its box corners).
    if (settings.chams && pl.pb && (settings.chamsStyle === 'hull' || settings.chamsStyle === 'mesh')) {
      // Mesh sampling covers both rigs: R15 MeshPart limbs and R6 CharacterMesh package limbs /
      // FileMesh heads (16-element pb entries). Parts without a mesh keep their box corners,
      // so default blocky R6 limbs render exactly as before.
      const useMesh = settings.chamsStyle === 'mesh';
      const limbs = limbClouds(pl.pb, pl.rig, useMesh);
      if (limbs.length) hullPlayers.push({ pl, limbs });
    } else if (settings.chams && pl.pb) {
      // body parts only — accessories (@n) are mesh-hull's concern, not the box styles
      const boxes = [];
      for (const n in pl.pb) if (n.charCodeAt(0) !== 64) boxes.push(pl.pb[n]);
      const ev = [];
      for (const box of boxes) pushPartBoxEdges(ev, box);
      if (settings.outlines.chams) {
        const og = new LineSegmentsGeometry();
        og.setPositions(ev);
        const ol = new LineSegments2(og, outlineMaterial(colorParts(playerColor(pl, settings.chamsColor))[1]));
        ol.renderOrder = 995;
        playerGroup.add(ol);
      }
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute(ev, 3));
      const wire = new THREE.LineSegments(g, lineMat(playerColor(pl, settings.chamsColor)));
      wire.renderOrder = 997; playerGroup.add(wire);
      if (settings.chamsFill) {
        const geos = boxes.map(partBoxGeo);
        if (geos.length) {
          const merged = mergeGeometries(geos, false); for (const x of geos) x.dispose();
          const fmesh = new THREE.Mesh(merged, meshMat(playerColor(pl, settings.chamsFillColor)));
          fmesh.renderOrder = 996; playerGroup.add(fmesh);
        }
      }
    }

    // bounding box (also anchors the name/health overlay). pb part corners give the exact body
    // extents (pb never includes the invisible HumanoidRootPart); without pb fall back to bone
    // CENTRES — skip the HRP there too, and pad since centres sit half a part inside the body.
    let mnx = Infinity, mny = Infinity, mnz = Infinity, mxx = -Infinity, mxy = -Infinity, mxz = -Infinity, has = false;
    let pad = 0.1, down = 0, up = 0;   // exact corners -> just a hair of breathing room
    if (pl.pb) {
      const pts = [];
      for (const n in pl.pb) if (n.charCodeAt(0) !== 64) pushPartBoxCorners(pts, pl.pb[n]);   // '@' = accessory: chams-only, keep the ESP box body-sized
      for (let i = 0; i < pts.length; i += 3) {
        const X = pts[i], Y = pts[i+1], Z = pts[i+2];
        if (X < mnx) mnx = X; if (Y < mny) mny = Y; if (Z < mnz) mnz = Z;
        if (X > mxx) mxx = X; if (Y > mxy) mxy = Y; if (Z > mxz) mxz = Z; has = true;
      }
    }
    if (!has) {
      for (const k in b) {
        if (k === 'HumanoidRootPart') continue;
        const p = b[k], X = -p[0], Y = p[1], Z = -p[2];
        if (X < mnx) mnx = X; if (Y < mny) mny = Y; if (Z < mnz) mnz = Z;
        if (X > mxx) mxx = X; if (Y > mxy) mxy = Y; if (Z > mxz) mxz = Z; has = true;
      }
      pad = 0.4; down = pl.rig === 'R15' ? 0.5 : 1.0; up = 0.3;
    }
    if (has) {
      const mn = { x: mnx - pad, y: mny - pad - down, z: mnz - pad };
      const mx = { x: mxx + pad, y: mxy + pad + up, z: mxz + pad };
      espPlayers.push({ pl, mn, mx });   // 2D box/name/health are drawn as an HTML overlay
    }

    if (pl.kind === 'local') {
      const root = b['HumanoidRootPart'] || b['Torso'] || b['LowerTorso'] || b['Head'];
      if (root) {
        localTarget.set(-root[0], root[1], -root[2]);
        haveLocal = true;
        localFace = pl.face || localFace;
      }
    }
  }
  if (DIAG) console.log(`DIAG players: ${players.length} players, ${segs} skeleton segments, haveLocal=${haveLocal}`);
  return players.length;
}

// ---------- camera controller (lock + freecam) ----------
const cam = {
  mode: 'lock',
  // lock
  lockDist: settings.followDist, lockPitch: 0.55, lockYaw: 0,   // lockYaw = drag offset around player
  // free
  freePos: new THREE.Vector3(0, 200, 200),
  freeYaw: 0, freePitch: -0.35,
  freeYawT: 0, freePitchT: -0.35,   // look targets (smoothing eases freeYaw/Pitch toward these)
};
const keys = {};
let dragBtn = -1;
let faceX = 0, faceZ = 1;   // smoothed local-player facing (three-space)

function freeForward(out) {
  return out.set(
    Math.cos(cam.freePitch) * Math.sin(cam.freeYaw),
    Math.sin(cam.freePitch),
    Math.cos(cam.freePitch) * Math.cos(cam.freeYaw)
  );
}

const _fwd = new THREE.Vector3();
const _right = new THREE.Vector3();
const _up = new THREE.Vector3(0, 1, 0);
const _dir = new THREE.Vector3();
const _desired = new THREE.Vector3();        // desired locked-camera position before smoothing
const smoothTarget = new THREE.Vector3();    // low-pass of the player position (kills gait shake)
let smoothInit = false;

function updateCamera(dt) {
  if (cam.mode === 'lock' && haveLocal) {
    // target facing in three-space (z flipped). fallback: look from +Z.
    let tx = 0, tz = 1;
    if (localFace) { tx = -localFace[0]; tz = -localFace[1]; }
    const tl = Math.hypot(tx, tz) || 1; tx /= tl; tz /= tl;
    // one smoothing factor for facing + position. Higher "amount" = slower follow (more damping).
    const a = settings.lockSmoothing
      ? Math.min(1, dt * (1.5 + (1 - settings.lockSmoothAmount / 100) * 12))
      : 1;
    faceX += (tx - faceX) * a; faceZ += (tz - faceZ) * a;
    const fl = Math.hypot(faceX, faceZ) || 1;
    let dx = faceX / fl, dz = faceZ / fl;
    // apply drag yaw offset around the player
    const cy = Math.cos(cam.lockYaw), sy = Math.sin(cam.lockYaw);
    const fx = dx * cy - dz * sy, fz = dx * sy + dz * cy;
    const horiz = cam.lockDist * Math.cos(cam.lockPitch);
    const vert = cam.lockDist * Math.sin(cam.lockPitch);
    // low-pass the look target + camera position so the per-step bob doesn't shake the view
    if (!smoothInit) { smoothTarget.copy(localTarget); smoothInit = true; }
    const pa = a;
    smoothTarget.lerp(localTarget, pa);
    _desired.set(
      smoothTarget.x - fx * horiz,
      smoothTarget.y + vert,
      smoothTarget.z - fz * horiz
    );
    camera.position.lerp(_desired, pa);
    camera.lookAt(smoothTarget);
  } else if (cam.mode === 'free' || (cam.mode === 'lock' && !haveLocal)) {
    // ease look toward the drag target (or snap if smoothing off)
    if (settings.freeDragSmooth) {
      const r = Math.min(1, dt * (2 + (1 - settings.freeDragSmoothAmount / 100) * 16));
      cam.freeYaw += (cam.freeYawT - cam.freeYaw) * r;
      cam.freePitch += (cam.freePitchT - cam.freePitch) * r;
    } else { cam.freeYaw = cam.freeYawT; cam.freePitch = cam.freePitchT; }
    // WASD / dolly
    freeForward(_fwd);
    _right.crossVectors(_fwd, _up).normalize();
    const speed = settings.freeSpeed * dt * (keys['shift'] ? 3 : 1);
    if (keys['w']) cam.freePos.addScaledVector(_fwd, speed);
    if (keys['s']) cam.freePos.addScaledVector(_fwd, -speed);
    if (keys['d']) cam.freePos.addScaledVector(_right, speed);
    if (keys['a']) cam.freePos.addScaledVector(_right, -speed);
    if (keys['e'] || keys[' ']) cam.freePos.y += speed;
    if (keys['q'] || keys['control']) cam.freePos.y -= speed;
    camera.position.copy(cam.freePos);
    camera.lookAt(_dir.copy(cam.freePos).add(_fwd));
  }
}

// pointer + key handlers — pointer lock pins the cursor in place for the duration of any drag
canvas.addEventListener('contextmenu', (e) => e.preventDefault());
canvas.addEventListener('mousedown', (e) => {
  dragBtn = e.button;
  if (e.button === 2) canvas.requestPointerLock();   // only RMB drives the camera
});
window.addEventListener('mouseup', () => {
  dragBtn = -1;
  if (document.pointerLockElement) document.exitPointerLock();   // restore cursor where it started
});
document.addEventListener('pointerlockchange', () => {
  if (!document.pointerLockElement) dragBtn = -1;   // lock released (e.g. Esc) -> end the drag
});
window.addEventListener('mousemove', (e) => {
  if (dragBtn !== 2) return;   // RMB only: orbit (locked) / look (freecam).
  const s = settings.sensitivity;
  const dx = (e.movementX || 0) * s * (settings.invertX ? -1 : 1);
  const dy = (e.movementY || 0) * s * (settings.invertY ? -1 : 1);
  if (cam.mode === 'lock' && haveLocal) {
    cam.lockYaw += dx * 0.005;   // drag right -> orbit right
    cam.lockPitch = THREE.MathUtils.clamp(cam.lockPitch + dy * 0.005, -0.2, 1.4);
  } else {
    cam.freeYawT -= dx * 0.0035;
    cam.freePitchT = THREE.MathUtils.clamp(cam.freePitchT - dy * 0.0035, -1.5, 1.5);
  }
});
canvas.addEventListener('wheel', (e) => {
  e.preventDefault();
  if (cam.mode === 'lock' && haveLocal) {
    cam.lockDist = THREE.MathUtils.clamp(cam.lockDist + e.deltaY * 0.05, 8, 4000);
    syncFollowDist();
  } else {
    freeForward(_fwd);
    cam.freePos.addScaledVector(_fwd, -e.deltaY * (settings.freeSpeed * 0.006));
  }
}, { passive: false });

window.addEventListener('keydown', (e) => {
  const k = e.key.toLowerCase();
  keys[k] = true;
  if (k === 'f' && !e.repeat) toggleMode(); // ignore OS key-repeat so a held F doesn't flicker
  if (k === 'c' && !e.repeat) snapBehind(); // re-centre the locked view behind the player
});
window.addEventListener('keyup', (e) => { keys[e.key.toLowerCase()] = false; });

// snap back to the default locked position: behind + above the player, default tilt/distance
function snapBehind() {
  cam.mode = 'lock';
  cam.lockYaw = 0;
  cam.lockPitch = 0.55;
  cam.lockDist = settings.followDist;
  smoothInit = false;   // re-seed the smoothed target so it snaps cleanly instead of easing across the map
  updateModeHud();
  syncFollowDist();
}

function toggleMode() {
  if (cam.mode === 'lock') {
    // seed freecam from current camera so the switch is seamless
    cam.freePos.copy(camera.position);
    freeForward(_fwd);
    camera.getWorldDirection(_dir);
    cam.freeYaw = cam.freeYawT = Math.atan2(_dir.x, _dir.z);
    cam.freePitch = cam.freePitchT = Math.asin(THREE.MathUtils.clamp(_dir.y, -1, 1));
    cam.mode = 'free';
  } else {
    cam.mode = 'lock';
  }
  updateModeHud();
}

// ---------- per-instance map alpha: occlusion fade + height cull ----------
const _ab = new THREE.Vector3();
let lastFade = 0;
let occSig = '';
function updateOcclusion(now) {
  if (!mapChunks.length) return;
  if (now - lastFade < 50) return;
  lastFade = now;
  const doOcc = settings.occlusion && cam.mode === 'lock' && haveLocal;
  const doCull = settings.heightCull && haveLocal;
  // dirty-check: skip the O(N) pass unless the camera/player moved or a relevant setting changed
  const sig = (doOcc || doCull)
    ? `${(camera.position.x*4|0)},${(camera.position.y*4|0)},${(camera.position.z*4|0)},${(localTarget.x*4|0)},${(localTarget.y*4|0)},${(localTarget.z*4|0)},${doOcc},${doCull},${settings.occStrength},${settings.occReach},${settings.heightCullOffset}`
    : 'off';
  if (sig === occSig) return;
  occSig = sig;
  const cullY = localTarget.y + settings.heightCullOffset;   // hide parts above this (see indoors)
  const fadeMin = 1 - settings.occStrength / 100;
  const fadeRadius = settings.occReach;
  const C = camera.position, P = localTarget;
  _ab.subVectors(P, C);
  const segLen = Math.sqrt(_ab.lengthSq() || 1);
  const adx = _ab.x / segLen, ady = _ab.y / segLen, adz = _ab.z / segLen; // unit camera->player dir
  const groundY = P.y - GROUND_BUFFER;   // the floor under the player is never an occluder

  for (const ch of mapChunks) {
    // pure fade factors (1 = untouched) — the shader multiplies them into the streamed alpha
    // AND any decal-keep alpha, so culled/faded parts take their decals with them
    const arr = ch.fade.array;
    if (!doOcc && !doCull) {
      let changed = false;
      for (let i = 0; i < arr.length; i++) { if (arr[i] !== 1) { arr[i] = 1; changed = true; } }
      if (changed) ch.fade.needsUpdate = true;
      continue;
    }
    const centers = ch.centers, he = ch.halfExt;
    for (let i = 0; i < arr.length; i++) {
      const y = centers[i * 3 + 1];
      if (doCull && y > cullY) { arr[i] = 0; continue; }   // above the player -> hidden
      if (!doOcc) { arr[i] = 1; continue; }
      if (y < groundY) { arr[i] = 1; continue; }   // at/below the player's feet -> ground, never fades
      const apx = centers[i * 3] - C.x, apy = y - C.y, apz = centers[i * 3 + 2] - C.z;
      const along = apx * adx + apy * ady + apz * adz;   // depth along the sightline
      const b = i * 9;
      // box half-extent projected onto the sightline direction
      const extAlong = Math.abs(he[b] * adx + he[b + 1] * ady + he[b + 2] * adz)
                     + Math.abs(he[b + 3] * adx + he[b + 4] * ady + he[b + 5] * adz)
                     + Math.abs(he[b + 6] * adx + he[b + 7] * ady + he[b + 8] * adz);
      // skip unless the part's body overlaps the camera->player segment in depth
      if (along + extAlong <= 0 || along - extAlong >= segLen) { arr[i] = 1; continue; }
      // perpendicular offset from the sightline to the part center
      const ox = apx - along * adx, oy = apy - along * ady, oz = apz - along * adz;
      const perp = Math.sqrt(ox * ox + oy * oy + oz * oz);
      let extPerp = 0;
      if (perp > 1e-4) {
        const dxp = ox / perp, dyp = oy / perp, dzp = oz / perp;
        // box half-extent toward the sightline (anisotropic: a wall edge-on contributes little)
        extPerp = Math.abs(he[b] * dxp + he[b + 1] * dyp + he[b + 2] * dzp)
                + Math.abs(he[b + 3] * dxp + he[b + 4] * dyp + he[b + 5] * dzp)
                + Math.abs(he[b + 6] * dxp + he[b + 7] * dyp + he[b + 8] * dzp);
      }
      const eff = Math.max(0, perp - extPerp);   // distance from the part's actual surface to the line
      const f = eff >= fadeRadius ? 1 : Math.pow(eff / fadeRadius, 1.6);
      arr[i] = fadeMin + (1 - fadeMin) * f;
    }
    ch.fade.needsUpdate = true;
  }
}

// ---------- file IO ----------
function readJSON(name) {
  const raw = srcRead(name);
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return null; }
}

const statusDot = document.getElementById('status-dot');
const statusText = document.getElementById('status-text');
const infoEl = document.getElementById('info');
const modeEl = document.getElementById('mode');
const helpLock = document.getElementById('help-lock');
const helpFree = document.getElementById('help-free');

function updateModeHud() {
  modeEl.innerHTML = cam.mode === 'lock'
    ? 'view: <b style="color:var(--accent)">locked</b> · <span class="key">F</span> freecam'
    : 'view: <b style="color:var(--warn)">freecam</b> · <span class="key">F</span> lock';
  helpLock.style.display = cam.mode === 'lock' ? '' : 'none';
  helpFree.style.display = cam.mode === 'free' ? '' : 'none';
}

let lastMapStat = '';
function refreshMap() {
  // sig gate: map.json can be multi-MB, and this runs from both the change signal and the safety
  // poll — don't read (let alone compare/parse) the whole payload unless it actually moved
  const sig = srcSig('map.json');
  if (!sig || sig === lastMapStat) return;
  lastMapStat = sig;
  const raw = srcRead('map.json');
  if (!raw) return;
  if (raw === lastMapStr) return;
  const map = (() => { try { return JSON.parse(raw); } catch { return null; } })();
  if (!map) return;
  lastMapStr = raw;
  buildMap(map);
}

let lastPlayersStr = '';
function refreshPlayers() {
  const raw = srcRead('players.json');
  if (!raw) return;
  if (raw === lastPlayersStr) return;   // unchanged since last build (the 150ms poll duplicates fs.watch)
  lastPlayersStr = raw;
  const data = (() => { try { return JSON.parse(raw); } catch { return null; } })();
  if (!data) return;
  playerCount = buildPlayers(data);
}

function setStatus(cls, text) {
  statusDot.className = 'dot ' + (cls === 'on' ? 'on' : cls === 'load' ? 'load' : 'off');
  statusText.textContent = text;
}

let lastPlaceId = null;
function refreshMeta() {
  const meta = readJSON('meta.json');
  if (!meta) { setStatus('off', 'no signal'); return; }
  // joining a new place -> snap back to the locked-on-local view (re-centered behind the player)
  if (meta.place_id && meta.place_id !== 0 && meta.place_id !== lastPlaceId) {
    if (lastPlaceId !== null) {
      cam.mode = 'lock';
      cam.lockYaw = 0;
      updateModeHud();
    }
    lastPlaceId = meta.place_id;
  }
  const ageMs = Date.now() - (meta.t || 0) * 1000;
  if (meta.status === 'offline') {
    setStatus('off', 'offline (unloaded)'); clearPlayers(); clearMap();
  } else if (ageMs > STALE_MS) {
    setStatus('off', `stale ${(ageMs / 1000) | 0}s (roblox closed?)`); clearPlayers(); clearMap();
  } else if (meta.status === 'menu' || meta.place_id === 0) {
    setStatus('load', 'in menu'); clearPlayers();
  } else if (meta.status === 'loading' || !meta.map_ready) {
    setStatus('load', 'loading map…');
  } else {
    setStatus('on', `live · place ${meta.place_id}`);
  }
  infoEl.textContent = `parts: ${partCount} · players: ${playerCount}`;
}

srcWatch((filename) => {
  if (filename === 'map.json') refreshMap();
  else if (filename === 'players.json') refreshPlayers();
  else if (filename === 'meta.json') refreshMeta();
});

// ---------- custom animated dropdown ----------
// Menus live in <body> (NOT inside the panel) because the panel has a transform, which would make a
// position:fixed child positioned relative to the panel, not the viewport. Position them at the trigger.
function ddPosition(cur, menu) {
  const r = cur.getBoundingClientRect();
  menu.style.left = r.left + 'px';
  menu.style.width = r.width + 'px';
  if (window.innerHeight - r.bottom < 190) {
    menu.style.top = 'auto'; menu.style.bottom = (window.innerHeight - r.top + 4) + 'px'; menu.style.transformOrigin = 'bottom';
  } else {
    menu.style.bottom = 'auto'; menu.style.top = (r.bottom + 4) + 'px'; menu.style.transformOrigin = 'top';
  }
}
function ddCloseAll() {
  document.querySelectorAll('.dd-menu.open,.dd.open,.cp-pop.open').forEach((e) => e.classList.remove('open'));
}
function ddBase(mount) {
  const dd = document.createElement('div'); dd.className = 'dd';
  const cur = document.createElement('div'); cur.className = 'dd-cur';
  const lbl = document.createElement('span'); cur.appendChild(lbl);
  dd.appendChild(cur); mount.appendChild(dd);
  const menu = document.createElement('div'); menu.className = 'dd-menu'; document.body.appendChild(menu);
  menu.addEventListener('click', (e) => e.stopPropagation());
  cur.addEventListener('click', (e) => {
    e.stopPropagation();
    const wasOpen = menu.classList.contains('open');
    ddCloseAll();
    if (!wasOpen) { ddPosition(cur, menu); menu.classList.add('open'); dd.classList.add('open'); }
  });
  return { dd, cur, lbl, menu };
}
function makeDropdown(mount, opts, value, onChange) {
  const { dd, lbl, menu } = ddBase(mount);
  let options = opts.slice(), val = value;
  function paint() {
    menu.innerHTML = '';
    for (const o of options) {
      const el = document.createElement('div');
      el.className = 'dd-opt' + (o.value === val ? ' sel' : '');
      el.textContent = o.label;
      el.addEventListener('click', (e) => { e.stopPropagation(); val = o.value; menu.classList.remove('open'); dd.classList.remove('open'); paint(); onChange && onChange(val); });
      menu.appendChild(el);
    }
    const f = options.find((o) => o.value === val);
    lbl.textContent = f ? f.label : (options[0] ? options[0].label : '—');
  }
  paint();
  return {
    setOptions(o) { options = o.slice(); if (!options.find((x) => x.value === val)) val = options[0] ? options[0].value : ''; paint(); },
    setValue(v) { val = v; paint(); },
    getValue() { return val; },
  };
}
// multi-select dropdown: each option toggles a checkbox; the menu stays open while toggling
function makeMultiDropdown(mount, opts, isOn, toggle, summary) {
  const { lbl, menu } = ddBase(mount);
  function paint() {
    menu.innerHTML = '';
    for (const o of opts) {
      const el = document.createElement('div');
      el.className = 'dd-opt dd-multi' + (isOn(o.value) ? ' on' : '');
      el.innerHTML = '<span class="dd-check"></span><span>' + o.label + '</span>';
      el.addEventListener('click', (e) => { e.stopPropagation(); toggle(o.value); paint(); });
      menu.appendChild(el);
    }
    lbl.textContent = summary();
  }
  paint();
  return { refresh: paint };
}
document.addEventListener('click', ddCloseAll);

// ---------- custom theme-matched colour picker (HSV) ----------
function cpHexToRgb(hex) { const n = parseInt((hex || '#000000').replace('#', ''), 16) || 0; return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 }; }
function cpRgbToHex(r, g, b) { const h = (x) => Math.max(0, Math.min(255, Math.round(x))).toString(16).padStart(2, '0'); return '#' + h(r) + h(g) + h(b); }
function cpRgbToHsv(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn;
  let h = 0;
  if (d) { if (mx === r) h = ((g - b) / d + 6) % 6; else if (mx === g) h = (b - r) / d + 2; else h = (r - g) / d + 4; h *= 60; }
  return { h, s: mx ? d / mx : 0, v: mx };
}
function cpHsvToRgb(h, s, v) {
  const c = v * s, x = c * (1 - Math.abs((h / 60) % 2 - 1)), m = v - c;
  let R = 0, G = 0, B = 0;
  if (h < 60) { R = c; G = x; } else if (h < 120) { R = x; G = c; } else if (h < 180) { G = c; B = x; }
  else if (h < 240) { G = x; B = c; } else if (h < 300) { R = x; B = c; } else { R = c; B = x; }
  return { r: (R + m) * 255, g: (G + m) * 255, b: (B + m) * 255 };
}

function makeColorPicker(mount, value, onChange) {
  const swatch = document.createElement('div'); swatch.className = 'cp-swatch';
  mount.appendChild(swatch);
  let hex = value || '#000000';
  const init = colorParts(hex); let alpha = init[1];
  let hsv = (() => { const { r, g, b } = cpHexToRgb(init[0]); return cpRgbToHsv(r, g, b); })();
  let h = hsv.h, s = hsv.s, v = hsv.v;

  const pop = document.createElement('div'); pop.className = 'cp-pop';
  pop.innerHTML = '<div class="cp-sv"><div class="cp-sv-inner"></div><div class="cp-handle"></div></div>'
    + '<div class="cp-hue"><div class="cp-hue-handle"></div></div>'
    + '<div class="cp-alpha"><div class="cp-alpha-grad"></div><div class="cp-alpha-handle"></div></div>'
    + '<div class="cp-hexrow"><input class="cp-hex" type="text" spellcheck="false"></div>';
  document.body.appendChild(pop);
  const sv = pop.querySelector('.cp-sv'), svHandle = pop.querySelector('.cp-handle');
  const hue = pop.querySelector('.cp-hue'), hueHandle = pop.querySelector('.cp-hue-handle');
  const alphaBar = pop.querySelector('.cp-alpha'), alphaGrad = pop.querySelector('.cp-alpha-grad'), alphaHandle = pop.querySelector('.cp-alpha-handle');
  const hexInput = pop.querySelector('.cp-hex');

  function compose(hex6) { return alpha >= 0.999 ? hex6 : hex6 + Math.round(alpha * 255).toString(16).padStart(2, '0'); }
  function render(updateHex = true) {
    sv.style.background = `hsl(${h},100%,50%)`;
    svHandle.style.left = (s * 100) + '%'; svHandle.style.top = ((1 - v) * 100) + '%';
    const { r, g, b } = cpHsvToRgb(h, s, v); const hex6 = cpRgbToHex(r, g, b);
    hex = compose(hex6);
    swatch.style.boxShadow = `inset 0 0 0 100px rgba(${r | 0},${g | 0},${b | 0},${alpha})`;   // colour over checker
    hueHandle.style.left = (h / 360 * 100) + '%';
    alphaGrad.style.background = `linear-gradient(to right, transparent, ${hex6})`;
    alphaHandle.style.left = (alpha * 100) + '%';
    if (updateHex) hexInput.value = hex.toUpperCase();
  }
  const emit = () => onChange && onChange(hex);
  function drag(elem, pick) {
    elem.addEventListener('pointerdown', (e) => {
      e.preventDefault(); pick(e);
      const mv = (ev) => pick(ev);
      const up = () => { window.removeEventListener('pointermove', mv); window.removeEventListener('pointerup', up); };
      window.addEventListener('pointermove', mv); window.addEventListener('pointerup', up);
    });
  }
  drag(sv, (e) => { const r = sv.getBoundingClientRect(); s = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)); v = 1 - Math.max(0, Math.min(1, (e.clientY - r.top) / r.height)); render(); emit(); });
  drag(hue, (e) => { const r = hue.getBoundingClientRect(); h = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)) * 360; render(); emit(); });
  drag(alphaBar, (e) => { const r = alphaBar.getBoundingClientRect(); alpha = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)); render(); emit(); });
  hexInput.addEventListener('input', () => {
    let val = hexInput.value.trim(); if (!val.startsWith('#')) val = '#' + val;
    if (/^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(val)) {
      const p = colorParts(val); alpha = p[1];
      const c = cpHexToRgb(p[0]), n = cpRgbToHsv(c.r, c.g, c.b); h = n.h; s = n.s; v = n.v; render(false); emit();
    }
  });
  function open() {
    ddCloseAll();
    const r = swatch.getBoundingClientRect();
    pop.style.left = Math.max(8, Math.min(window.innerWidth - 196, r.right - 180)) + 'px';
    pop.style.top = (r.bottom + 230 > window.innerHeight ? r.top - 236 : r.bottom + 6) + 'px';
    pop.classList.add('open');
  }
  swatch.addEventListener('click', (e) => { e.stopPropagation(); pop.classList.contains('open') ? pop.classList.remove('open') : open(); });
  pop.addEventListener('click', (e) => e.stopPropagation());
  render();
  return {
    swatch,
    setValue(nv) { if (!nv || nv === hex) return; const p = colorParts(nv); alpha = p[1]; const c = cpHexToRgb(p[0]), n = cpRgbToHsv(c.r, c.g, c.b); h = n.h; s = n.s; v = n.v; render(); },
    getValue() { return hex; },
  };
}
document.addEventListener('click', () => document.querySelectorAll('.cp-pop.open').forEach((p) => p.classList.remove('open')));

// upgrade every native colour input into the custom picker (keep the native input hidden as the model)
const colorPickers = [];
function upgradeColorInputs() {
  document.querySelectorAll('input[type=color]').forEach((inp) => {
    const init = inp.value;
    inp.type = 'hidden';   // hidden inputs can hold #RRGGBBAA (type=color truncates to #RRGGBB)
    const pk = makeColorPicker(inp.parentElement, init, (rgba) => { inp.value = rgba; inp.dispatchEvent(new Event('input', { bubbles: true })); });
    inp.insertAdjacentElement('afterend', pk.swatch);   // keep visual order (swatch where the input was)
    colorPickers.push({ inp, pk });
  });
}
function refreshColorPickers() { for (const { inp, pk } of colorPickers) pk.setValue(inp.value); }

// ---------- settings panel ----------
function bindSettings() {
  const $ = (id) => document.getElementById(id);
  const gear = $('gear'), panel = $('settings');
  gear.addEventListener('click', () => {
    const open = panel.classList.toggle('open');
    gear.classList.toggle('open', open);
  });
  upgradeColorInputs();   // swap native colour inputs for the custom picker

  const occ = $('set-occ'), occSub = $('occ-sub');
  const occStr = $('set-occ-str'), occReach = $('set-occ-reach');
  const OUTLINE_OPTS = [
    { value: 'skeleton', label: 'Skeleton' }, { value: 'chams', label: 'Chams' },
    { value: 'box', label: 'Bounding box' }, { value: 'name', label: 'Names' }, { value: 'health', label: 'Health bar' },
  ];
  const outlineDD = makeMultiDropdown($('set-outlines-dd'), OUTLINE_OPTS,
    (v) => settings.outlines[v], (v) => { settings.outlines[v] = !settings.outlines[v]; saveSettings(); },
    () => { const n = OUTLINE_OPTS.filter((o) => settings.outlines[o.value]).length; return n === OUTLINE_OPTS.length ? 'All' : n === 0 ? 'None' : n + ' / ' + OUTLINE_OPTS.length; });
  const team = $('set-team'), localcol = $('set-localcol');
  const skel = $('set-skel'), skelcol = $('set-skelcol');
  const hidden = $('set-hidden'), hidcol = $('set-hidcol');
  const box = $('set-box'), boxcol = $('set-boxcol'), boxSub = $('box-sub'), boxfill = $('set-boxfill'), boxfillcol = $('set-boxfillcol');
  const chams = $('set-chams'), chamscol = $('set-chamscol'), chamsSub = $('chams-sub'), chamsfill = $('set-chamsfill'), chamsfillcol = $('set-chamsfillcol');
  const chamStyleDD = makeDropdown($('set-chamstyle-dd'), [
    { value: 'boxes', label: 'Part boxes' }, { value: 'hull', label: 'Convex hull' },
    { value: 'mesh', label: 'Mesh hull' },
  ], settings.chamsStyle, (v) => { settings.chamsStyle = v; saveSettings(); });
  const names = $('set-names'), namecol = $('set-namecol'), localname = $('set-localname'), namesSub = $('names-sub');
  const hp = $('set-hp'), hphigh = $('set-hphigh'), hplow = $('set-hplow');
  const namemodeDD = makeDropdown($('set-namemode-dd'),
    [{ value: 'display', label: 'Display name' }, { value: 'user', label: 'Username' }],
    settings.nameMode, (v) => { settings.nameMode = v; saveSettings(); });
  const dist = $('set-dist'), sens = $('set-sens');
  const invx = $('set-invx'), invy = $('set-invy');
  const smooth = $('set-smooth'), smoothSub = $('smooth-sub'), smoothamt = $('set-smoothamt'), vSmoothamt = $('v-smoothamt');
  const fspeed = $('set-fspeed'), vFspeed = $('v-fspeed'), fdrag = $('set-fdrag'), fdragSub = $('fdrag-sub'), fdragamt = $('set-fdragamt'), vFdragamt = $('v-fdragamt');
  const hcull = $('set-hcull'), hcullSub = $('hcull-sub'), hoff = $('set-hoff'), vHoff = $('v-hoff');
  const meshesCb = $('set-meshes'), texturesCb = $('set-textures'), meshesSub = $('meshes-sub');
  const hideFailCb = $('set-hidefail'), matsCb = $('set-mats'), hideUnionsCb = $('set-hideunions');
  const decalsCb = $('set-decals');
  const rdist = $('set-rdist'), vRdist = $('v-rdist');
  const lodCb = $('set-lod'), lodSub = $('lod-sub'), lodd = $('set-lodd'), vLodd = $('v-lodd');
  const vlim = $('set-vlim'), vlimSub = $('vlim-sub'), vlimv = $('set-vlimv'), vVlimv = $('v-vlimv');
  const transpDD = makeDropdown($('set-transp-dd'), [
    { value: 'blended', label: 'Blended' }, { value: 'dithered', label: 'Dithered' }, { value: 'hashed', label: 'Hashed' },
  ], settings.transparency, (v) => { settings.transparency = v; saveSettings(); applyTransparencyMode(); });
  const vStr = $('v-occ-str'), vReach = $('v-occ-reach'), vDist = $('v-dist'), vSens = $('v-sens');
  const phz = $('set-phz'), mrs = $('set-mrs'), rad = $('set-rad');
  const mauto = $('set-mauto'), mautoSub = $('mauto-sub'), mapnow = $('set-mapnow');
  const vPhz = $('v-phz'), vMrs = $('v-mrs'), vRad = $('v-rad');
  const themeIds = ['bg', 'panel', 'border', 'text', 'text-dim', 'accent', 'ok', 'warn', 'bad'];
  const pfName = $('pf-name'), pfDD = makeDropdown($('pf-list-dd'), [], '', null);

  // push the current settings + theme objects into every control (on load + after a profile load)
  function initControls() {
    occ.checked = settings.occlusion;
    occSub.classList.toggle('collapsed', !settings.occlusion);
    occStr.value = settings.occStrength; vStr.textContent = settings.occStrength;
    occReach.value = settings.occReach; vReach.textContent = settings.occReach;
    outlineDD.refresh();
    team.checked = settings.teamColours;
    localcol.value = settings.localColor;
    skel.checked = settings.skeleton; skelcol.value = settings.skeletonColor;
    hidden.checked = settings.showHidden; hidcol.value = settings.showHiddenColor;
    box.checked = settings.boundingBox; boxcol.value = settings.boxColor;
    boxSub.classList.toggle('collapsed', !settings.boundingBox);
    boxfill.checked = settings.boxFill; boxfillcol.value = settings.boxFillColor;
    chams.checked = settings.chams; chamscol.value = settings.chamsColor; chamsSub.classList.toggle('collapsed', !settings.chams);
    chamStyleDD.setValue(settings.chamsStyle);
    chamsfill.checked = settings.chamsFill; chamsfillcol.value = settings.chamsFillColor;
    names.checked = settings.names; namecol.value = settings.nameColor; namemodeDD.setValue(settings.nameMode);
    localname.checked = settings.localName; namesSub.classList.toggle('collapsed', !settings.names);
    hp.checked = settings.healthBar; hphigh.value = settings.hpHigh; hplow.value = settings.hpLow;
    dist.value = settings.followDist; vDist.textContent = settings.followDist; cam.lockDist = settings.followDist;
    sens.value = Math.round(settings.sensitivity * 100); vSens.textContent = settings.sensitivity.toFixed(1);
    invx.checked = settings.invertX; invy.checked = settings.invertY;
    smooth.checked = settings.lockSmoothing; smoothSub.classList.toggle('collapsed', !settings.lockSmoothing);
    smoothamt.value = settings.lockSmoothAmount; vSmoothamt.textContent = settings.lockSmoothAmount;
    fspeed.value = settings.freeSpeed; vFspeed.textContent = settings.freeSpeed;
    fdrag.checked = settings.freeDragSmooth; fdragSub.classList.toggle('collapsed', !settings.freeDragSmooth);
    fdragamt.value = settings.freeDragSmoothAmount; vFdragamt.textContent = settings.freeDragSmoothAmount;
    hcull.checked = settings.heightCull; hcullSub.classList.toggle('collapsed', !settings.heightCull);
    hoff.value = settings.heightCullOffset; vHoff.textContent = settings.heightCullOffset;
    meshesCb.checked = settings.meshes; meshesSub.classList.toggle('collapsed', !settings.meshes);
    texturesCb.checked = settings.textures;
    hideFailCb.checked = settings.hideFailedMeshes;
    matsCb.checked = settings.materials;
    hideUnionsCb.checked = settings.hideUnions;
    decalsCb.checked = settings.partDecals;
    rdist.value = settings.renderDist; vRdist.textContent = settings.renderDist >= RENDER_DIST_MAX ? '∞' : settings.renderDist;
    vlim.checked = settings.vertLimitOn; vlimSub.classList.toggle('collapsed', !settings.vertLimitOn);
    vlimv.value = settings.vertLimit; vVlimv.textContent = Math.round(settings.vertLimit / 1000) + 'k';
    lodCb.checked = settings.lodOn; lodSub.classList.toggle('collapsed', !settings.lodOn);
    lodd.value = settings.lodDist; vLodd.textContent = settings.lodDist;
    transpDD.setValue(settings.transparency);
    phz.value = settings.playerHz; vPhz.textContent = settings.playerHz;
    mrs.value = settings.mapRescanS; vMrs.textContent = settings.mapRescanS;
    mauto.checked = settings.mapAuto; mautoSub.classList.toggle('collapsed', !settings.mapAuto);
    rad.value = settings.radius; vRad.textContent = settings.radius;
    for (const k of themeIds) $('th-' + k).value = theme[k];
    refreshColorPickers();
  }

  occ.addEventListener('change', () => { settings.occlusion = occ.checked; occSub.classList.toggle('collapsed', !occ.checked); saveSettings(); });
  occStr.addEventListener('input', () => { settings.occStrength = +occStr.value; vStr.textContent = occStr.value; saveSettings(); });
  occReach.addEventListener('input', () => { settings.occReach = +occReach.value; vReach.textContent = occReach.value; saveSettings(); });
  team.addEventListener('change', () => { settings.teamColours = team.checked; saveSettings(); });
  localcol.addEventListener('input', () => { settings.localColor = localcol.value; saveSettings(); });
  skel.addEventListener('change', () => { settings.skeleton = skel.checked; saveSettings(); });
  skelcol.addEventListener('input', () => { settings.skeletonColor = skelcol.value; saveSettings(); });
  hidden.addEventListener('change', () => { settings.showHidden = hidden.checked; saveSettings(); });
  hidcol.addEventListener('input', () => { settings.showHiddenColor = hidcol.value; saveSettings(); });
  box.addEventListener('change', () => { settings.boundingBox = box.checked; boxSub.classList.toggle('collapsed', !box.checked); saveSettings(); });
  boxcol.addEventListener('input', () => { settings.boxColor = boxcol.value; saveSettings(); });
  boxfill.addEventListener('change', () => { settings.boxFill = boxfill.checked; saveSettings(); });
  boxfillcol.addEventListener('input', () => { settings.boxFillColor = boxfillcol.value; saveSettings(); });
  chams.addEventListener('change', () => { settings.chams = chams.checked; chamsSub.classList.toggle('collapsed', !chams.checked); saveSettings(); writeStreamConfig(); });
  chamscol.addEventListener('input', () => { settings.chamsColor = chamscol.value; saveSettings(); });
  chamsfill.addEventListener('change', () => { settings.chamsFill = chamsfill.checked; saveSettings(); });
  chamsfillcol.addEventListener('input', () => { settings.chamsFillColor = chamsfillcol.value; saveSettings(); });
  names.addEventListener('change', () => { settings.names = names.checked; namesSub.classList.toggle('collapsed', !names.checked); saveSettings(); });
  namecol.addEventListener('input', () => { settings.nameColor = namecol.value; saveSettings(); });
  localname.addEventListener('change', () => { settings.localName = localname.checked; saveSettings(); });
  hp.addEventListener('change', () => { settings.healthBar = hp.checked; saveSettings(); });
  hphigh.addEventListener('input', () => { settings.hpHigh = hphigh.value; saveSettings(); });
  hplow.addEventListener('input', () => { settings.hpLow = hplow.value; saveSettings(); });
  dist.addEventListener('input', () => { settings.followDist = +dist.value; cam.lockDist = +dist.value; vDist.textContent = dist.value; saveSettings(); });
  sens.addEventListener('input', () => { settings.sensitivity = +sens.value / 100; vSens.textContent = settings.sensitivity.toFixed(1); saveSettings(); });
  invx.addEventListener('change', () => { settings.invertX = invx.checked; saveSettings(); });
  invy.addEventListener('change', () => { settings.invertY = invy.checked; saveSettings(); });
  smooth.addEventListener('change', () => { settings.lockSmoothing = smooth.checked; smoothSub.classList.toggle('collapsed', !smooth.checked); saveSettings(); });
  smoothamt.addEventListener('input', () => { settings.lockSmoothAmount = +smoothamt.value; vSmoothamt.textContent = smoothamt.value; saveSettings(); });
  fspeed.addEventListener('input', () => { settings.freeSpeed = +fspeed.value; vFspeed.textContent = fspeed.value; saveSettings(); });
  fdrag.addEventListener('change', () => { settings.freeDragSmooth = fdrag.checked; fdragSub.classList.toggle('collapsed', !fdrag.checked); saveSettings(); });
  fdragamt.addEventListener('input', () => { settings.freeDragSmoothAmount = +fdragamt.value; vFdragamt.textContent = fdragamt.value; saveSettings(); });
  hcull.addEventListener('change', () => { settings.heightCull = hcull.checked; hcullSub.classList.toggle('collapsed', !hcull.checked); saveSettings(); });
  meshesCb.addEventListener('change', () => { settings.meshes = meshesCb.checked; meshesSub.classList.toggle('collapsed', !meshesCb.checked); saveSettings(); writeStreamConfig(); if (lastMapData) buildMap(lastMapData); });
  texturesCb.addEventListener('change', () => { settings.textures = texturesCb.checked; saveSettings(); if (lastMapData) buildMap(lastMapData); });
  hideFailCb.addEventListener('change', () => { settings.hideFailedMeshes = hideFailCb.checked; saveSettings(); if (lastMapData) buildMap(lastMapData); });
  matsCb.addEventListener('change', () => { settings.materials = matsCb.checked; saveSettings(); writeStreamConfig(); if (lastMapData) buildMap(lastMapData); });
  hideUnionsCb.addEventListener('change', () => { settings.hideUnions = hideUnionsCb.checked; saveSettings(); if (lastMapData) buildMap(lastMapData); });
  decalsCb.addEventListener('change', () => { settings.partDecals = decalsCb.checked; saveSettings(); writeStreamConfig(); if (lastMapData) buildMap(lastMapData); });
  rdist.addEventListener('input', () => { settings.renderDist = +rdist.value; vRdist.textContent = settings.renderDist >= RENDER_DIST_MAX ? '∞' : rdist.value; saveSettings(); applyRenderDist(); });
  vlim.addEventListener('change', () => { settings.vertLimitOn = vlim.checked; vlimSub.classList.toggle('collapsed', !vlim.checked); saveSettings(); applyVertLimit(); });
  vlimv.addEventListener('input', () => { settings.vertLimit = +vlimv.value; vVlimv.textContent = Math.round(settings.vertLimit / 1000) + 'k'; saveSettings(); });
  vlimv.addEventListener('change', () => applyVertLimit());   // the rebuild is heavy — only on release
  lodCb.addEventListener('change', () => { settings.lodOn = lodCb.checked; lodSub.classList.toggle('collapsed', !lodCb.checked); saveSettings(); if (lastMapData) buildMap(lastMapData); });
  lodd.addEventListener('input', () => { settings.lodDist = +lodd.value; vLodd.textContent = lodd.value; saveSettings(); });
  lodd.addEventListener('change', () => { if (settings.lodOn && lastMapData) buildMap(lastMapData); });
  hoff.addEventListener('input', () => { settings.heightCullOffset = +hoff.value; vHoff.textContent = hoff.value; saveSettings(); });
  phz.addEventListener('input', () => { settings.playerHz = +phz.value; vPhz.textContent = phz.value; saveSettings(); writeStreamConfig(); });
  mrs.addEventListener('input', () => { settings.mapRescanS = +mrs.value; vMrs.textContent = mrs.value; saveSettings(); writeStreamConfig(); });
  mauto.addEventListener('change', () => { settings.mapAuto = mauto.checked; mautoSub.classList.toggle('collapsed', !mauto.checked); saveSettings(); writeStreamConfig(); });
  mapnow.addEventListener('click', () => { settings.mapNow = Date.now(); saveSettings(); writeStreamConfig(); });
  rad.addEventListener('input', () => { settings.radius = +rad.value; vRad.textContent = rad.value; saveSettings(); writeStreamConfig(); });

  // theme editor
  for (const k of themeIds) {
    $('th-' + k).addEventListener('input', (e) => { theme[k] = e.target.value; applyTheme(); saveTheme(); });
  }
  $('th-reset').addEventListener('click', () => {
    Object.assign(theme, THEME_DEFAULTS); applyTheme(); saveTheme();
    for (const k of themeIds) $('th-' + k).value = theme[k];
    refreshColorPickers();
  });

  // profiles (manual save/load; config + theme written as separate files)
  const pfAuto = $('pf-auto');
  function refreshProfileList() {
    const names = listProfiles();
    pfDD.setOptions(names.length ? names.map((n) => ({ value: n, label: n })) : [{ value: '', label: '(none)' }]);
  }
  function refreshAuto() { pfAuto.textContent = 'auto-load: ' + (getAutoLoad() || 'none'); }
  refreshProfileList(); refreshAuto();
  // Save into the name box if given, else overwrite the selected profile
  $('pf-save').addEventListener('click', () => {
    const n = pfName.value.trim() || pfDD.getValue();
    if (!n) return;
    saveProfile(n); pfName.value = ''; refreshProfileList(); pfDD.setValue(n);
  });
  $('pf-load').addEventListener('click', () => { const n = pfDD.getValue(); if (!n) return; loadProfile(n); initControls(); applyTheme(); applyTransparencyMode(); applyRenderDist(); applyVertLimit(); writeStreamConfig(); });
  $('pf-del').addEventListener('click', () => {
    const n = pfDD.getValue(); if (!n) return;
    deleteProfile(n);
    if (getAutoLoad() === n) { setAutoLoad(''); refreshAuto(); }
    refreshProfileList();
  });
  $('pf-setauto').addEventListener('click', () => { const n = pfDD.getValue(); if (!n) return; setAutoLoad(n); refreshAuto(); });
  $('pf-clrauto').addEventListener('click', () => { setAutoLoad(''); refreshAuto(); });

  syncFollowDist = () => { const d = Math.round(cam.lockDist); dist.value = d; vDist.textContent = d; settings.followDist = d; };

  initControls();
  applyRenderDist();
  applyVertLimit();
  writeStreamConfig();   // push persisted rates to stream.lua on startup
}

// Change signal (fs.watch / SSE) is primary. The 150ms fast poll is the Electron fallback when
// the watch never attached. The 1s tick re-runs the sig-gated refreshes while watching, and in
// remote mode re-pulls everything only while the SSE connection is down.
setInterval(() => { refreshMeta(); if (!srcIsWatching() && !IS_REMOTE) { refreshPlayers(); refreshMap(); } }, 150);
setInterval(() => { if (srcIsWatching()) { refreshPlayers(); refreshMap(); } else if (IS_REMOTE) srcPoll(); }, 1000);

// tell stream.lua where the camera is, so it centres the map scan on what we're looking at
// (better than the player in freecam). Convert three-space back to Roblox: rbx=-x, rbz=-z.
function writeView() {
  srcWrite('view.json', JSON.stringify({
    cx: -camera.position.x, cy: camera.position.y, cz: -camera.position.z,
    t: Math.floor(Date.now() / 1000),
  }));
}
setInterval(writeView, 500);

// auto-load a profile on startup (before the UI binds, so controls reflect it)
(() => { const al = getAutoLoad(); if (al && listProfiles().includes(al)) { loadProfile(al); applyTransparencyMode(); } })();

refreshMap(); refreshPlayers(); refreshMeta(); updateModeHud(); applyTheme(); bindSettings();

// ---------- 2D ESP overlay (box / name / health) ----------
const espContainer = document.getElementById('esp');
const espRows = [];
const _ev = new THREE.Vector3();
const _hpA = new THREE.Color(), _hpB = new THREE.Color(), _hpC = new THREE.Color();
function getEspRow(i) {
  if (!espRows[i]) {
    const box = document.createElement('div'); box.className = 'esp-box';
    const name = document.createElement('div'); name.className = 'esp-name';
    const health = document.createElement('div'); health.className = 'esp-health';
    const fill = document.createElement('i'); health.appendChild(fill);
    espContainer.append(box, name, health);
    espRows[i] = { box, name, health, fill };
  }
  return espRows[i];
}
function hideRow(r) { r.box.style.opacity = '0'; r.name.style.opacity = '0'; r.health.style.opacity = '0'; }
// outline shadow strings, alpha-matched to the feature
const olBox = (a) => `0 0 0 1px rgba(0,0,0,${a}), inset 0 0 0 1px rgba(0,0,0,${a})`;
const olShadow = (a) => `0 0 0 1px rgba(0,0,0,${a})`;
// text shadow that holds the name's own opacity: the readability drop-shadow scales with the name
// alpha too (not a fixed 0.9), so a translucent name has an equally translucent shadow.
function olName(a, outline) {
  const base = `0 1px 2px rgba(0,0,0,${(0.9 * a).toFixed(3)})`;
  return outline ? `-1px -1px 0 rgba(0,0,0,${a}),1px -1px 0 rgba(0,0,0,${a}),-1px 1px 0 rgba(0,0,0,${a}),1px 1px 0 rgba(0,0,0,${a}),${base}` : base;
}

// ---------- 2D hull-chams overlay ----------
// Per frame: project each limb's corners, take the 2D convex hull, and draw all limbs of a player
// as ONE rounded path. A single nonzero fill covers the union (no seams where limbs overlap); the
// outline is built by stroking+filling an expanded blob and punching the interior back out
// (destination-out), so only the silhouette ring remains — no interior lines, curved corners.
const hullCanvas = document.getElementById('hullcanvas');
const hullCtx = hullCanvas.getContext('2d');
const hullScratch = document.createElement('canvas');   // per-player ring compositing (opaque -> alpha)
const hullSctx = hullScratch.getContext('2d');
function sizeHullCanvas() {
  hullCanvas.width = window.innerWidth; hullCanvas.height = window.innerHeight;
  hullScratch.width = window.innerWidth; hullScratch.height = window.innerHeight;
}
sizeHullCanvas();
const HULL_LW = 2.5;        // outline stroke width (px)
const HULL_OL = 1.5;        // black outline width beyond it (px)
const HULL_CORNER_PX = 3;   // corner rounding radius (px, capped at 1/3 of the edge)
// 2D convex hull, Andrew monotone chain -> CCW vertex list
function hull2d(pts) {
  pts.sort((a, b) => a.x - b.x || a.y - b.y);
  const cross = (o, a, b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  const lo = [], up = [];
  for (const p of pts) { while (lo.length >= 2 && cross(lo[lo.length-2], lo[lo.length-1], p) <= 0) lo.pop(); lo.push(p); }
  for (let i = pts.length - 1; i >= 0; i--) { const p = pts[i]; while (up.length >= 2 && cross(up[up.length-2], up[up.length-1], p) <= 0) up.pop(); up.push(p); }
  lo.pop(); up.pop();
  return lo.concat(up);
}
// polygon -> path with corners rounded by a quadratic curve through each vertex
function roundedPoly(path, pts, r) {
  const n = pts.length;
  if (n < 3) return;
  for (let i = 0; i < n; i++) {
    const p = pts[(i + n - 1) % n], v = pts[i], q = pts[(i + 1) % n];
    const d1x = v.x - p.x, d1y = v.y - p.y, l1 = Math.hypot(d1x, d1y) || 1;
    const d2x = q.x - v.x, d2y = q.y - v.y, l2 = Math.hypot(d2x, d2y) || 1;
    const r1 = Math.min(r, l1 / 3), r2 = Math.min(r, l2 / 3);
    const ax = v.x - d1x / l1 * r1, ay = v.y - d1y / l1 * r1;
    const bx = v.x + d2x / l2 * r2, by = v.y + d2y / l2 * r2;
    if (i === 0) path.moveTo(ax, ay); else path.lineTo(ax, ay);
    path.quadraticCurveTo(v.x, v.y, bx, by);
  }
  path.closePath();
}
function drawHullChams() {
  const w = hullCanvas.width, h = hullCanvas.height;
  hullCtx.clearRect(0, 0, w, h);
  for (const e of hullPlayers) {
    const path = new Path2D();
    let minx = Infinity, miny = Infinity, maxx = -Infinity, maxy = -Infinity, any = false;
    for (const limb of e.limbs) {
      const pts = [];
      let behind = false;
      for (let i = 0; i < limb.length && !behind; i += 3) {
        _ev.set(limb[i], limb[i+1], limb[i+2]).project(camera);
        if (_ev.z >= 1) { behind = true; break; }   // any corner behind the camera -> skip the limb
        pts.push({ x: (_ev.x * 0.5 + 0.5) * w, y: (-_ev.y * 0.5 + 0.5) * h });
      }
      if (behind || pts.length < 3) continue;
      const hull = hull2d(pts);
      if (hull.length < 3) continue;
      roundedPoly(path, hull, HULL_CORNER_PX);
      for (const p of hull) {
        if (p.x < minx) minx = p.x; if (p.y < miny) miny = p.y;
        if (p.x > maxx) maxx = p.x; if (p.y > maxy) maxy = p.y;
      }
      any = true;
    }
    if (!any || maxx < 0 || maxy < 0 || minx > w || miny > h) continue;
    // union fill first (a single fill op -> overlapping limbs don't double-darken)
    if (settings.chamsFill) { hullCtx.fillStyle = playerColor(e.pl, settings.chamsFillColor); hullCtx.fill(path); }
    // silhouette ring on the scratch canvas, opaque, then composited with the colour's own alpha
    const [hex, a] = colorParts(playerColor(e.pl, settings.chamsColor));
    const pad = HULL_LW + HULL_OL + 2;
    const bx = Math.max(0, Math.floor(minx - pad)), by = Math.max(0, Math.floor(miny - pad));
    const bw = Math.min(w, Math.ceil(maxx + pad)) - bx, bh = Math.min(h, Math.ceil(maxy + pad)) - by;
    if (bw <= 0 || bh <= 0) continue;
    hullSctx.clearRect(bx, by, bw, bh);
    hullSctx.lineJoin = 'round'; hullSctx.lineCap = 'round';
    if (settings.outlines.chams) {
      hullSctx.lineWidth = HULL_LW + HULL_OL * 2;
      hullSctx.strokeStyle = '#000'; hullSctx.fillStyle = '#000';
      hullSctx.stroke(path); hullSctx.fill(path);
    }
    hullSctx.lineWidth = HULL_LW;
    hullSctx.strokeStyle = hex; hullSctx.fillStyle = hex;
    hullSctx.stroke(path); hullSctx.fill(path);
    hullSctx.globalCompositeOperation = 'destination-out';
    hullSctx.fill(path);   // punch the interior -> only the outline band survives
    hullSctx.globalCompositeOperation = 'source-over';
    hullCtx.globalAlpha = a;
    hullCtx.drawImage(hullScratch, bx, by, bw, bh, bx, by, bw, bh);
    hullCtx.globalAlpha = 1;
  }
}

let espIdle = false;
function updateESP() {
  // nothing enabled -> hide the rows once and skip the per-frame projection work entirely
  if (!settings.boundingBox && !settings.names && !settings.healthBar) {
    if (!espIdle) { for (const r of espRows) hideRow(r); espIdle = true; }
    return;
  }
  espIdle = false;
  const w = window.innerWidth, h = window.innerHeight;
  let used = 0;
  for (let i = 0; i < espPlayers.length; i++) {
    const e = espPlayers[i], pl = e.pl, mn = e.mn, mx = e.mx;
    // project the 8 AABB corners; the 2D box is their screen-space bounds
    let minx = Infinity, miny = Infinity, maxx = -Infinity, maxy = -Infinity, front = false;
    for (let cx = 0; cx < 2; cx++) for (let cy = 0; cy < 2; cy++) for (let cz = 0; cz < 2; cz++) {
      _ev.set(cx ? mx.x : mn.x, cy ? mx.y : mn.y, cz ? mx.z : mn.z).project(camera);
      if (_ev.z >= 1) continue;   // corner behind the camera -> ignore (avoids mirrored garbage)
      front = true;
      const sx = (_ev.x * 0.5 + 0.5) * w, sy = (-_ev.y * 0.5 + 0.5) * h;
      if (sx < minx) minx = sx; if (sy < miny) miny = sy;
      if (sx > maxx) maxx = sx; if (sy > maxy) maxy = sy;
    }
    const row = getEspRow(used++);
    if (!front) { hideRow(row); continue; }
    const bh = Math.max(0, maxy - miny), isLocal = pl.kind === 'local';

    // box (+ optional fill)
    row.box.style.left = minx + 'px'; row.box.style.top = miny + 'px';
    row.box.style.width = Math.max(0, maxx - minx) + 'px'; row.box.style.height = bh + 'px';
    row.box.style.borderColor = playerColor(pl, settings.boxColor);
    row.box.style.background = (settings.boundingBox && settings.boxFill)
      ? playerColor(pl, settings.boxFillColor) : 'transparent';
    row.box.style.boxShadow = settings.outlines.box ? olBox(colorParts(playerColor(pl, settings.boxColor))[1]) : 'none';
    row.box.style.opacity = settings.boundingBox ? '1' : '0';

    // name (above box, centred). local name optional.
    if (settings.names && (!isLocal || settings.localName)) {
      row.name.textContent = (settings.nameMode === 'user' ? pl.name : (pl.dn || pl.name)) || '';
      row.name.style.left = (minx + maxx) / 2 + 'px';
      row.name.style.top = miny + 'px';
      row.name.style.color = playerColor(pl, settings.nameColor);
      row.name.style.textShadow = olName(colorParts(playerColor(pl, settings.nameColor))[1], settings.outlines.name);
      row.name.style.opacity = '1';
    } else row.name.style.opacity = '0';

    // vertical health bar on the left; fill height + colour lerp low->high (smooth via CSS)
    if (settings.healthBar && pl.mhp) {
      const frac = Math.max(0, Math.min(1, (pl.hp == null ? pl.mhp : pl.hp) / pl.mhp));
      row.health.style.left = (minx - 6) + 'px'; row.health.style.top = miny + 'px'; row.health.style.height = bh + 'px';
      _hpA.set(colorParts(settings.hpLow)[0]); _hpB.set(colorParts(settings.hpHigh)[0]); _hpC.lerpColors(_hpA, _hpB, frac);
      row.fill.style.height = (frac * 100) + '%';
      row.fill.style.backgroundColor = '#' + _hpC.getHexString();
      row.health.style.boxShadow = settings.outlines.health ? olShadow(colorParts(settings.hpHigh)[1]) : 'none';
      row.health.style.opacity = '1';
    } else row.health.style.opacity = '0';
  }
  for (let i = used; i < espRows.length; i++) hideRow(espRows[i]);
}

// ---------- render loop ----------
window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
  sizeHullCanvas();
  outlineMat.resolution.set(window.innerWidth, window.innerHeight);
  outlineMatCache.forEach((m) => m.resolution.set(window.innerWidth, window.innerHeight));
});

let prev = performance.now();
let lodCheckT = 0;
function animate() {
  requestAnimationFrame(animate);
  const now = performance.now();
  const dt = Math.min((now - prev) / 1000, 0.1);
  prev = now;
  // LOD follows the camera: rebuild once it strays far from where the map was last grouped
  if (settings.lodOn && lastMapData && now - lodCheckT > 500) {
    lodCheckT = now;
    const thr = Math.max(150, settings.lodDist * 0.25);
    if (camera.position.distanceToSquared(lodBuildPos) > thr * thr) buildMap(lastMapData);
  }
  updateCamera(dt);
  updateOcclusion(now);
  renderer.render(scene, camera);
  drawHullChams();
  updateESP();
}
animate();

// diag-only hook so CDP automation can drive the camera and inspect state
if (DIAG) {
  window.__radar = { cam, camera, settings, scene };
  // inspect(rx, ry, rz, opts): park the freecam on a map part by its ROBLOX coords (as printed
  // in map.json) and clip away everything between the camera and the target, so occluding
  // walls never block the shot. opts: dist (studs from target), dir (approach direction,
  // Roblox space), margin (studs kept unclipped in front of the target — must exceed the
  // part's half-depth toward the camera or the part clips its own front face). inspect() restores.
  window.__radar.inspect = (rx, ry, rz, opts) => {
    if (rx === undefined) { renderer.clippingPlanes = []; return 'clip off'; }
    const { dist = 60, dir = [1, 0.4, 1], margin = 20 } = opts || {};
    const t = new THREE.Vector3(-rx, ry, -rz);                    // roblox -> three (x,z negated)
    const d = new THREE.Vector3(-dir[0], dir[1], -dir[2]).normalize();
    cam.mode = 'free';
    cam.freePos.copy(t).addScaledVector(d, dist);
    const look = t.clone().sub(cam.freePos).normalize();          // freecam yaw/pitch toward target
    cam.freeYaw = cam.freeYawT = Math.atan2(look.x, look.z);
    cam.freePitch = cam.freePitchT = Math.asin(look.y);
    // keep only geometry on the far side of a plane just in front of the target
    const pp = t.clone().addScaledVector(look, -margin);
    renderer.clippingPlanes = [new THREE.Plane(look.clone(), -look.dot(pp))];
    return 'cam at ' + cam.freePos.toArray().map((v) => v.toFixed(1)).join(',') + ', clip on';
  };
}




