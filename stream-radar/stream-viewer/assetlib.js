// assetlib.js — Roblox asset fetching + .mesh parsing/decoding, shared by the radar renderer and
// the standalone mesh inspector (mesh-viewer.html). Fetches authenticate with the local Roblox
// client's session cookie (DPAPI) when available; callers supply the on-disk cache directory.
import * as THREE from 'three';
import { DRACOLoader } from 'three/addons/loaders/DRACOLoader.js';

// Electron: the Node fetch core (https + DPAPI cookie + disk cache) lives in assetfetch.js so the
// radar server's /asset proxy (main process) can share it. Hosted browser: no require at all —
// fetches will route through the host's proxy instead (fetchAssetBytes below, remote branch).
const IS_REMOTE = (typeof require !== 'function');
const fs = IS_REMOTE ? null : require('fs');
const path = IS_REMOTE ? null : require('path');
const AF = IS_REMOTE ? null : require('./assetfetch.js');

export const MESH_UA = { 'User-Agent': 'Roblox/WinInet' };
export const MESH_VERT_LIMIT = 1000000;  // default cap; the part falls back to its box beyond it
let vertLimit = MESH_VERT_LIMIT;         // runtime-adjustable via setVertLimit (viewer perf slider)
export function setVertLimit(n) { vertLimit = (n && n > 0) ? n : MESH_VERT_LIMIT; }

let rBackoff = 0;   // remote-mode 429 backoff (Electron's lives in assetfetch.js)
export const getBackoff = () => (IS_REMOTE ? rBackoff : AF.getBackoff());
export const decayBackoff = () => {
  if (IS_REMOTE) { if (rBackoff > 0) rBackoff = Math.max(0, rBackoff - 250); }
  else AF.decayBackoff();
};

let assetPlaceId = null;   // remote keeps its own copy for the proxy query param
export function setAssetPlaceId(id) {
  assetPlaceId = (id && id !== 0) ? String(id) : null;
  if (AF) AF.setAssetPlaceId(id);
}
export const getRobloxCookie = IS_REMOTE ? async () => null : () => AF.getRobloxCookie();

// Browser stand-in for the few Node Buffer members the mesh parser uses (readUInt8/16/32LE,
// readFloatLE, toString(ascii|utf8, start, end), subarray, [i], .length, .buffer/.byteOffset/
// .byteLength). A Uint8Array subclass, so Blob/THREE/typed-array consumers take it as-is and
// subarray() yields RBuf views over the same memory.
class RBuf extends Uint8Array {
  dv() {
    if (!this._dv) this._dv = new DataView(this.buffer, this.byteOffset, this.byteLength);
    return this._dv;
  }
  readUInt8(o) { return this[o]; }
  readUInt16LE(o) { return this.dv().getUint16(o, true); }
  readUInt32LE(o) { return this.dv().getUint32(o, true); }
  readFloatLE(o) { return this.dv().getFloat32(o, true); }
  toString(enc, start = 0, end = this.length) {
    return new TextDecoder(enc === 'utf8' ? 'utf-8' : 'latin1').decode(this.subarray(start, end));
  }
}

// Electron: the Node core (cookie, CDN follow, disk cache). Browser: the host's /asset proxy —
// same bytes, already decompressed and cache-written host-side; the place id rides the query so
// experience-restricted assets resolve with the HOST's session, which never leaves the host.
export async function fetchAssetBytes(id, cacheDir, ext) {
  if (!IS_REMOTE) return AF.fetchAssetBytes(id, cacheDir, ext);
  const kind = ext === '.mesh' ? 'mesh' : 'tex';
  const res = await fetch(`/asset/${kind}/${id}` + (assetPlaceId ? `?place=${assetPlaceId}` : ''));
  if (res.status === 429) {
    rBackoff = Math.min(8000, (rBackoff || 500) * 2);
    throw Object.assign(new Error('rate-limited'), { rateLimited: true });
  }
  if (!res.ok) throw new Error('proxy http ' + res.status);
  return new RBuf(await res.arrayBuffer());
}

// ---------- v7 DRACO decode (WASM worker via three's DRACOLoader) ----------
// The decoder ships inside the three package. DRACOLoader fetches it with FileLoader, which checks
// THREE.Cache first — so the wrapper JS + wasm are read with fs and planted in the cache under a
// fake URL scheme (fetch(file://) is blocked in Chromium, a real path would fail).
let dracoLoader = null;
export function getDracoLoader() {
  if (dracoLoader) return dracoLoader;
  if (IS_REMOTE) {
    // hosted page: the decoder files are just static URLs (server.js serves node_modules/three)
    dracoLoader = new DRACOLoader();
    dracoLoader.setDecoderPath('./node_modules/three/examples/jsm/libs/draco/');
    dracoLoader.preload();
    return dracoLoader;
  }
  const dir = path.join(__dirname, 'node_modules', 'three', 'examples', 'jsm', 'libs', 'draco');
  const wasm = fs.readFileSync(path.join(dir, 'draco_decoder.wasm'));
  THREE.Cache.enabled = true;   // FileLoader is only used here, so global caching is inert elsewhere
  THREE.Cache.add('three-draco://draco_wasm_wrapper.js', fs.readFileSync(path.join(dir, 'draco_wasm_wrapper.js'), 'utf8'));
  THREE.Cache.add('three-draco://draco_decoder.wasm', wasm.buffer.slice(wasm.byteOffset, wasm.byteOffset + wasm.byteLength));
  dracoLoader = new DRACOLoader();
  dracoLoader.setDecoderPath('three-draco://');
  dracoLoader.preload();
  return dracoLoader;
}
// raw DRACO bitstream (Buffer) -> Promise<BufferGeometry>, normalized like the sync parser output
export function decodeDraco(blob) {
  const ab = blob.buffer.slice(blob.byteOffset, blob.byteOffset + blob.byteLength);
  return new Promise((resolve, reject) => {
    getDracoLoader().decodeDracoFile(ab, (geom) => {
      try {
        if (geom.getAttribute('position').count > vertLimit) throw new Error('draco too many verts');
        resolve(normalizeMeshGeom(geom));
      } catch (err) { reject(err); }
    }, null, null, THREE.LinearSRGBColorSpace, reject);
  });
}

// Parses the Roblox .mesh container (v1 text, v2-v5 binary) into a BufferGeometry normalized to a
// centered unit box (each axis -0.5..0.5). Mesh vertices are in part-local space and Roblox scales a
// MeshPart's mesh bounding box to its Size, so after normalization the SAME instance matrix used for
// the box path places it exactly. Only LOD0 (the highest-detail band) is kept.
// v7 (DRACO) returns a {draco: <Buffer>} sentinel instead — decode it with decodeDraco().
export function parseRobloxMesh(buf) {
  const ver = /^version (\d+)\.(\d+)/.exec(buf.toString('ascii', 0, 12));
  if (!ver) throw new Error('not a mesh');
  const major = +ver[1];
  let pos, idx, uv = null;   // uv kept raw (Roblox top-left origin; textures upload unflipped)
  // v6/v7 wrap the mesh in a "COREMESH" container (reverse-engineered + validated against the local
  // Roblox cache). v6 is uncompressed, handled inline; v7 replaces the vert/face blocks with one raw
  // DRACO bitstream -> return a sentinel for the async WASM decode.
  if (buf.toString('ascii', 13, 21) === 'COREMESH') {
    if (major >= 7) {
      // layout: [13 "COREMESH"][21 u32=2][25 u32=fileSize-60][29 u32 blobLen][33 blob][31B trailer]
      const blobLen = buf.readUInt32LE(29);
      const blob = buf.subarray(33, 33 + blobLen);
      if (blob.length < 8 || blob.toString('ascii', 0, 5) !== 'DRACO') throw new Error('v7 bad draco blob');
      return { draco: blob };
    }
    // layout: [13 "COREMESH"][21 u32=1][25 u32 payloadSize][29 u32 numVerts]
    //         [33 verts: numVerts x 40B, first 12B = position xyz f32]
    //         [u32 numFaces][numFaces x 3 x u32 indices][31B trailer]
    const VSTRIDE = 40;
    const numVerts = buf.readUInt32LE(29);
    if (!(numVerts > 0) || numVerts > vertLimit) throw new Error(`v6 bad vert count ${numVerts}`);
    const facesOff = 33 + numVerts * VSTRIDE;
    const numFaces = buf.readUInt32LE(facesOff);
    if (!(numFaces > 0) || facesOff + 4 + numFaces * 12 > buf.length) throw new Error('v6 truncated');
    pos = new Float32Array(numVerts * 3);
    uv = new Float32Array(numVerts * 2);
    for (let v = 0; v < numVerts; v++) {
      const b = 33 + v * VSTRIDE;   // 40B record: pos(12) normal(12) uv(8) tangent/colour(8)
      pos[v * 3] = buf.readFloatLE(b); pos[v * 3 + 1] = buf.readFloatLE(b + 4); pos[v * 3 + 2] = buf.readFloatLE(b + 8);
      uv[v * 2] = buf.readFloatLE(b + 24); uv[v * 2 + 1] = buf.readFloatLE(b + 28);
    }
    idx = new Uint32Array(numFaces * 3);
    for (let i = 0, o = facesOff + 4; i < numFaces * 3; i++, o += 4) idx[i] = buf.readUInt32LE(o);
  } else if (major === 1) {
    // text: "version 1.0x\n<numFaces>\n[px,py,pz][nx,ny,nz][u,v,w]..." — 3 bracket-triples per vertex
    const txt = buf.toString('utf8');
    const nl1 = txt.indexOf('\n'), nl2 = txt.indexOf('\n', nl1 + 1);
    const numFaces = parseInt(txt.slice(nl1 + 1, nl2), 10);
    if (!(numFaces > 0)) throw new Error('v1 bad face count');
    const nums = txt.slice(nl2 + 1).match(/-?\d+\.?\d*(?:e[+-]?\d+)?/gi);
    const scale = ver[2] === '00' ? 0.5 : 1;   // v1.00 vertices are stored doubled
    const nVerts = numFaces * 3;
    if (nVerts > vertLimit || !nums || nums.length < nVerts * 9) throw new Error('v1 truncated');
    pos = new Float32Array(nVerts * 3);
    uv = new Float32Array(nVerts * 2);
    idx = new Uint32Array(nVerts);
    for (let v = 0; v < nVerts; v++) {
      const b = v * 9;   // 9 numbers per vertex: position, normal, uv
      pos[v * 3] = +nums[b] * scale; pos[v * 3 + 1] = +nums[b + 1] * scale; pos[v * 3 + 2] = +nums[b + 2] * scale;
      // v1 quirk (official FileMesh spec): "the tex_V coordinate is upside down! ... store the
      // UV coordinate as tex_U, 1.0 - tex_V" — without this, texture atlas regions land on the
      // wrong areas of classic gear meshes
      uv[v * 2] = +nums[b + 6]; uv[v * 2 + 1] = 1 - +nums[b + 7];
      idx[v] = v;
    }
  } else {
    // binary: "version x.xx\n" (13 bytes), u16 header size, then a version-specific header.
    // vertices are px,py,pz f32 at the start of each record; faces are 3x u32.
    const off = 13;
    const headerSize = buf.readUInt16LE(off);
    let numVerts, numFaces, vertSize = 40, numLODs = 0, numBones = 0;
    if (major === 2) {
      vertSize = buf.readUInt8(off + 2);
      numVerts = buf.readUInt32LE(off + 4);
      numFaces = buf.readUInt32LE(off + 8);
    } else if (major === 3) {
      vertSize = buf.readUInt8(off + 2);
      numLODs  = buf.readUInt16LE(off + 6);
      numVerts = buf.readUInt32LE(off + 8);
      numFaces = buf.readUInt32LE(off + 12);
    } else if (major === 4 || major === 5) {
      numVerts = buf.readUInt32LE(off + 4);
      numFaces = buf.readUInt32LE(off + 8);
      numLODs  = buf.readUInt16LE(off + 12);
      numBones = buf.readUInt16LE(off + 14);
    } else throw new Error('unsupported version ' + major);
    if (!(numVerts > 0) || numVerts > vertLimit) throw new Error(`bad vert count ${numVerts}`);
    const vertsOff = off + headerSize;
    const facesOff = vertsOff + numVerts * vertSize + (numBones > 0 ? numVerts * 8 : 0); // skip skinning envelopes
    const lodsOff = facesOff + numFaces * 12;
    let faceStart = 0, faceEnd = numFaces;
    if (numLODs >= 2) { faceStart = buf.readUInt32LE(lodsOff); faceEnd = buf.readUInt32LE(lodsOff + 4); }
    pos = new Float32Array(numVerts * 3);
    if (vertSize >= 32) uv = new Float32Array(numVerts * 2);   // 36/40B records carry uv at offset 24
    for (let v = 0; v < numVerts; v++) {
      const b = vertsOff + v * vertSize;
      pos[v * 3] = buf.readFloatLE(b); pos[v * 3 + 1] = buf.readFloatLE(b + 4); pos[v * 3 + 2] = buf.readFloatLE(b + 8);
      if (uv) { uv[v * 2] = buf.readFloatLE(b + 24); uv[v * 2 + 1] = buf.readFloatLE(b + 28); }
    }
    idx = new Uint32Array((faceEnd - faceStart) * 3);
    for (let f = faceStart, o = 0; f < faceEnd; f++) {
      const b = facesOff + f * 12;
      idx[o++] = buf.readUInt32LE(b); idx[o++] = buf.readUInt32LE(b + 4); idx[o++] = buf.readUInt32LE(b + 8);
    }
  }
  const geom = new THREE.BufferGeometry();
  geom.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  if (uv) geom.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  geom.setIndex(new THREE.BufferAttribute(idx, 1));
  return normalizeMeshGeom(geom);
}

// normalize to a centered unit box so the box-path instance matrix (basis * part size) fits it.
// Shared by the sync parser and the DRACO decode path. The pre-normalization extents are kept in
// geom.userData.size so an inspector can restore the true aspect ratio.
export function normalizeMeshGeom(geom) {
  geom.computeBoundingBox();
  const bb = geom.boundingBox;
  const pos = geom.getAttribute('position').array;
  const cx = (bb.min.x + bb.max.x) / 2, cy = (bb.min.y + bb.max.y) / 2, cz = (bb.min.z + bb.max.z) / 2;
  const sx = (bb.max.x - bb.min.x) || 1, sy = (bb.max.y - bb.min.y) || 1, sz = (bb.max.z - bb.min.z) || 1;
  for (let i = 0; i < pos.length; i += 3) {
    pos[i] = (pos[i] - cx) / sx; pos[i + 1] = (pos[i + 1] - cy) / sy; pos[i + 2] = (pos[i + 2] - cz) / sz;
  }
  geom.userData.size = [sx, sy, sz];
  // pre-normalization bbox centre: a SpecialMesh FileMesh is placed by its AUTHORED ORIGIN at
  // the part centre (not bbox-fitted like a MeshPart), so its renderer must add this back
  geom.userData.center = [cx, cy, cz];
  geom.getAttribute('position').needsUpdate = true;
  if (geom.getAttribute('normal')) geom.deleteAttribute('normal');   // invalid after non-uniform scale
  geom.computeVertexNormals();
  return geom;
}
