-- stream.lua — 3D web radar streamer
-- Streams the live Roblox world to files/stream/*.json for an Electron + Three.js viewer
-- (stream-viewer/ in this folder). Map geometry is oriented (rotation-correct) and re-scanned
-- periodically within a radius of the local player; players stream as R6/R15 skeletons.
--
-- File IPC layout (sandbox root is files/, so these land in C:/Serotonin/files/stream/):
--   meta.json    {status, place_id, t, map_ready}
--   map.json     {place_id, count, parts:[{p,u,v,w,c,t?,r?,m?,tx?,mt?,sh?,ms?,e?,mo?,dc?,un?}]}  oriented
--                boxes (t = transparency, r = reflectance, omitted when 0; m / tx = mesh / texture
--                asset id; mt = Enum.Material value (Plastic never streamed); sh = shape code
--                0 ball / 2 cylinder / 3 wedge / 4 corner wedge / 5 classic CylinderMesh (Y axis) /
--                6 ellipsoid (SpecialMesh Sphere/Head); ms = mesh scale; e=1 marks a SpecialMesh
--                whose render size is native mesh size x ms, not the part size; mo =
--                DataModelMesh.Offset (part-local studs); dc = decal/texture children —
--                Decal [face,id] or [face,id,tr], Texture [face,id,tileU,tileV(,tr)] where
--                tr is the decal's own partial transparency; un=1 marks a CSG union —
--                bounding box only), re-scanned periodically
--   players.json {place_id, t, players:[{name,dn,kind,team,tc,rig,hp,mhp,vis,face,pb,bones}]}
--                pb = per-part oriented boxes keyed by part name ("@n" = accessory handles),
--                each 12 numbers [+meshid[+scale x3]] -- see the pb entries section. ~15 Hz
--
-- Geometry note: part.CFrame / part.Orientation are nil in the sandbox, so rotation is recovered
-- from draw.GetPartCorners(part): center = (c1+c8)/2, and edge vectors u=c2-c1, v=c3-c1, w=c5-c1
-- give the box's local axes scaled by its dimensions (verified: |u|=sizeX, |v|=sizeY, |w|=sizeZ).

-- Generation guard: re-running the script supersedes any previously-registered callbacks
-- (Serotonin can't unregister them). Old callbacks see a newer _STREAM_GEN and no-op.
-- NOTE: an instance loaded BEFORE this guard existed will keep running until Roblox restarts.
_STREAM_GEN = (_STREAM_GEN or 0) + 1
local MY_GEN = _STREAM_GEN
local function active() return _STREAM_GEN == MY_GEN end

local STREAM_DIR = "stream"
local F_META     = "stream/meta.json"
local F_MAP      = "stream/map.json"
local F_PLAYERS  = "stream/players.json"
local F_CONFIG   = "stream/config.json"   -- written by the viewer; read here (reverse IPC)
local F_VIEW     = "stream/view.json"     -- viewer's camera position; scan is centred on it

-- ===== tunables (defaults; overridable live via the viewer's config.json) =====
local RADIUS         = 2000  -- studs around local player to include in the map (0 = unlimited)
local MAP_RESCAN_MS  = 4000  -- re-scan the map this often so in-world changes show up
local PLAYER_INTERVAL = 66   -- ms between player writes (~15 Hz)
local SCAN_BUDGET    = 500   -- nodes processed per frame during the chunked map scan

-- :IsA("BasePart") returns false in the sandbox, so detect parts by ClassName.
local PART_CLASSES = {
    Part = true, MeshPart = true, WedgePart = true, UnionOperation = true,
    TrussPart = true, CornerWedgePart = true, Seat = true, VehicleSeat = true,
    SpawnLocation = true,
}

-- ===== self-derived memory offsets (no external file, no absolute offsets) =====
-- These properties read as nil/garbage through the sandbox, so the script reads them straight
-- from memory at inst.Address + offset. Offsets move with Roblox builds, so no absolute offset
-- is ever assumed: resolve_offsets() pins each class to an ANCHOR found live by signature
-- (sandbox ground truth like part.Color, an asset-id string, Enum.Material membership, or the
-- adjacent Offset/Scale vec3 pair), then places the class's other fields from the last-known
-- intra-class layout -- ONLY after validating each one against the live samples. A failed
-- validation falls back to an anchored window scan; if that is ambiguous the field stays nil
-- and its feature simply doesn't stream (derive-or-disable -- a missing offset emits nothing,
-- a wrong one would emit garbage). Re-runs as the place streams in, then locks for the session.
local OFF = {}
-- Per-feature gates: a detail feature touches memory only once its offsets are confirmed.
local OFF_GOT = { mat = false, shape = false, dc = false, dc_tr = false, tx = false,
                  sm = false, sm_str = false, sm_tex = false, sm_off = false, sa = false,
                  cm = false }

-- Last-known intra-class layout: RELATIVE deltas from each class anchor, never absolute
-- addresses. A whole-struct shift (the common case across builds) moves the anchor and keeps
-- these valid; an intra-class reorder breaks one, validation catches it, and the window-scan
-- rescue re-derives it from scratch.
local D = {
    shape   =   29,   -- BasePart.Shape        <- Color3uint8 (the part-colour anchor)
    dc_face = -176,   -- Decal.Face            <- ColorMapContent (the dc anchor)
    dc_tr   =  148,   -- Decal.Transparency    <- ColorMapContent
    tx_u    =  224,   -- Texture.StudsPerTileU <- ColorMapContent
    tx_v    =  228,   -- Texture.StudsPerTileV <- ColorMapContent
    sm_str  =   52,   -- SpecialMesh.MeshId    <- DataModelMesh.Scale (the dmm anchor)
    sm_tex  =  100,   -- SpecialMesh.TextureId <- Scale
    sm_type =  132,   -- SpecialMesh.MeshType  <- Scale
    cm_body =   80,   -- CharacterMesh.BodyPart <- CharacterMesh.MeshId (the cm anchor)
}

-- Every valid Enum.Material value (from the official enum reference). Used both to drop misreads
-- and as the fingerprint that pins the Primitive pointer + Material offset: the one (ptr, off)
-- pair whose dereferenced value lands in this set for every sampled part is unique.
local MAT_VALID = {
    [256]=1,[272]=1,[288]=1,[512]=1,[528]=1,[784]=1,[788]=1,[800]=1,[804]=1,[816]=1,[820]=1,
    [832]=1,[836]=1,[848]=1,[864]=1,[880]=1,[896]=1,[912]=1,[1040]=1,[1056]=1,[1072]=1,[1088]=1,
    [1280]=1,[1284]=1,[1296]=1,[1312]=1,[1328]=1,[1344]=1,[1360]=1,[1376]=1,[1392]=1,[1536]=1,
    [1552]=1,[1568]=1,[1584]=1,[2048]=1,[2304]=1,[2305]=1,[2306]=1,[2307]=1,[2308]=1,[2309]=1,
    [2310]=1,[2311]=1,
}

-- ---- signature scanners and validators ----
-- All reads are memory-safe: memory.Read returns a STRING sentinel (not nil) on an unmapped
-- read, so every value is type-checked before any compare/index or the scan throws the moment
-- it steps off a struct. Acceptance is by QUORUM (~85% of samples), not all-must-pass: live
-- testing showed a single stale sample (instance streamed out, address reused) vetoing the true
-- offset at every position.
local function quorum(n) return math.max(2, math.ceil(n * 0.85)) end

local function rd_num(t, a)
    local v = memory.Read(t, a)
    if type(v) == "number" then return v end
    return nil
end
local function rd_vec3(a)
    local v = memory.Read("vector3", a)
    if type(v) == "userdata" then return v end
    return nil
end

-- Argmax offset holding a content-URL string (5+ digits or rbxasset://) across the samples,
-- gated by `floor` so a lone coincidental string never wins. The default floor is deliberately
-- low (35%, min 2): blank-heavy populations are normal -- decals with script-cleared textures,
-- geometric SpecialMeshes with no MeshId -- and a handful of instances agreeing on a content
-- URL at one offset is already conclusive.
local function scan_asset(addrs, lo, hi, floor)
    if #addrs < 2 then return nil end
    floor = floor or math.max(2, math.ceil(#addrs * 0.35))
    local best_off, best_hits = nil, 0
    for off = lo, hi, 4 do
        local hits = 0
        for _, a in ipairs(addrs) do
            local s = memory.Read("string", a + off)
            if type(s) == "string" and (s:match("%d%d%d%d%d") or s:match("^rbxasset")) then
                hits = hits + 1
            end
        end
        if hits > best_hits then best_hits, best_off = hits, off end
    end
    if best_hits >= floor then return best_off end
    return nil
end

-- Hypothesis validators: does the value at ONE offset look like the claimed field across the
-- sample? Validating a single anchored delta is far stronger than searching a window for the
-- same value-domain (a window of 25 offsets gets 25 chances to false-match; a hypothesis gets 1).
local function ok_enum(addrs, off, maxv, width)
    local pass = 0
    for _, a in ipairs(addrs) do
        local v = rd_num(width or "int", a + off)
        if v and v >= 0 and v <= maxv then pass = pass + 1 end
    end
    return pass >= quorum(#addrs)
end
local function ok_unit_float(addrs, off)
    local pass = 0
    for _, a in ipairs(addrs) do
        local v = rd_num("float", a + off)
        if v and v >= 0 and v <= 1.0001 then pass = pass + 1 end
    end
    return pass >= quorum(#addrs)
end
-- Two adjacent positive floats (Texture.StudsPerTileU/V) -- validated on Texture samples only;
-- Decals share the struct but have no tiling fields. Floor of 1 (not the usual 2): maps with a
-- single Texture instance are common, and validating the ONE layout-hypothesis offset against
-- one sample is sound where a window search would not be -- the call sites gate the window
-- rescue behind >= 2 samples.
local function ok_tile(addrs, off)
    local pass = 0
    for _, a in ipairs(addrs) do
        local u = rd_num("float", a + off)
        local v = rd_num("float", a + off + 4)
        if u and v and u > 0.01 and u < 1e4 and v > 0.01 and v < 1e4 then pass = pass + 1 end
    end
    return pass >= math.max(1, math.ceil(#addrs * 0.85))
end
-- An asset-string field: nearly every sample must read empty or asset-looking, and at least one
-- must actually carry an id -- an all-empty window can't distinguish a string field from zeroed
-- padding, and with no id on the map there is nothing to stream anyway.
local function ok_asset_str(addrs, off)
    local pass, with_id = 0, 0
    for _, a in ipairs(addrs) do
        local s = memory.Read("string", a + off)
        if type(s) == "string" then
            if s == "" then pass = pass + 1
            elseif s:match("%d%d%d%d%d") or s:match("^rbxasset") then
                pass = pass + 1; with_id = with_id + 1
            end
        end
    end
    return pass >= quorum(#addrs) and with_id >= 1
end

-- Window rescue for an enum field when its layout hypothesis fails: the unique offset whose
-- value is in [0,maxv] for a quorum of samples and spans >= 2 distinct values. Ambiguity (two
-- qualifying offsets) returns nil rather than guessing.
local function scan_enum(addrs, lo, hi, maxv, width)
    local found, cands = nil, 0
    local q = quorum(#addrs)
    for off = lo, hi, (width == "byte" and 1 or 4) do
        local pass, seen = 0, {}
        for _, a in ipairs(addrs) do
            local v = rd_num(width or "int", a + off)
            if v and v >= 0 and v <= maxv then pass = pass + 1; seen[v] = true end
        end
        if pass >= q then
            local span = 0; for _ in pairs(seen) do span = span + 1 end
            if span >= 2 then found = off; cands = cands + 1 end
        end
    end
    if cands == 1 then return found end
    return nil
end

-- Hypothesis validator for the Shape byte: Enum.PartType (in 0..4) for a quorum AND Block-modal.
-- Validates on all-Block maps too (constant 1), where a window scan is structurally blind --
-- see scan_shape below.
local function ok_shape_byte(PT, off)
    local pass, hist = 0, {}
    for _, p in ipairs(PT) do
        local v = rd_num("byte", p.a + off)
        if v and v >= 0 and v <= 4 then pass = pass + 1; hist[v] = (hist[v] or 0) + 1 end
    end
    if pass < quorum(#PT) then return false end
    local mode_v, mode_n = nil, -1
    for v, n in pairs(hist) do if n > mode_n then mode_v, mode_n = v, n end end
    return mode_v == 1
end

-- Rescue window scan for Shape (used only when the layout hypothesis fails). Block-modal and
-- span >= 2, AND at least one value in 2..4: a boolean flag byte reads {0,1} -- Ball+Block to a
-- value-domain test, mode Block and all -- and on an all-Block map it beat the true (constant)
-- Shape byte and streamed half the map as spheres (observed live). No boolean can produce a 2.
local function scan_shape(PT, c3)
    local found, cands = nil, 0
    local q = quorum(#PT)
    for off = c3 + 16, c3 + 44, 1 do
        local pass, hist = 0, {}
        for _, p in ipairs(PT) do
            local v = rd_num("byte", p.a + off)
            if v and v >= 0 and v <= 4 then pass = pass + 1; hist[v] = (hist[v] or 0) + 1 end
        end
        if pass >= q then
            local span, mode_v, mode_n, big = 0, nil, -1, false
            for v, n in pairs(hist) do
                span = span + 1
                if n > mode_n then mode_v, mode_n = v, n end
                if v >= 2 then big = true end
            end
            if span >= 2 and mode_v == 1 and big then found = off; cands = cands + 1 end
        end
    end
    if cands == 1 then return found end
    return nil
end

-- DataModelMesh anchor: Offset and Scale are ADJACENT vec3 fields -- Offset first (modally
-- (0,0,0), its default), Scale 12 bytes later (modally nonzero; negatives are legit -- the
-- classic mirror trick). Runs of zeros and ones overlap (VertexColor is another all-ones vec3
-- right after Scale), so candidates are scored by how many samples read all-zero in the FIRST
-- field: only the true pair has Offset zero on most samples. Nonzero Scale is required only on
-- a majority, not every sample -- games animate Scale components through zero to hide meshes,
-- and one mid-animation sample must not veto the pair (observed live).
local function scan_dmm_pair(addrs)
    if #addrs < 3 then return nil end
    local best, best_zeros = nil, -1
    -- 4-aligned window: vec3 fields sit on 4-byte boundaries, so the base must be too (a
    -- misaligned base steps over every real field and the scan silently finds nothing)
    for off = 148, 340, 4 do
        local pass, zeros, nz = 0, 0, 0
        for _, a in ipairs(addrs) do
            local v1 = rd_vec3(a + off)
            local v2 = rd_vec3(a + off + 12)
            if v1 and v2 and math.abs(v1.X) < 2e3 and math.abs(v1.Y) < 2e3 and math.abs(v1.Z) < 2e3
                and math.abs(v2.X) < 1e4 and math.abs(v2.Y) < 1e4 and math.abs(v2.Z) < 1e4 then
                pass = pass + 1
                if v1.X == 0 and v1.Y == 0 and v1.Z == 0 then zeros = zeros + 1 end
                if math.abs(v2.X) > 1e-4 and math.abs(v2.Y) > 1e-4 and math.abs(v2.Z) > 1e-4 then nz = nz + 1 end
            end
        end
        if pass >= math.max(3, math.ceil(#addrs * 0.6))
            and nz >= math.ceil(pass * 0.6)
            and zeros > best_zeros then
            best, best_zeros = off, zeros
        end
    end
    if best and best_zeros >= math.max(2, math.ceil(#addrs * 0.35)) then return best end
    return nil
end

-- CharacterMesh.BodyPart: an int in 0..5 that is DISTINCT within one character's body package
-- (one mesh per limb -- Torso, both arms, both legs). The within-character permutation is the
-- signature; no neighbouring byte mimics five distinct enum values on the same model. Samples
-- carry their parent (character) address for the grouping. Also used to validate the single
-- layout-hypothesis offset (a one-step window).
local function scan_cm_body(CMH, lo, hi)
    local found, cands = nil, 0
    local q = quorum(#CMH)
    for off = lo, hi, 4 do
        local pass, ok, groups = 0, true, {}
        for _, s in ipairs(CMH) do
            local v = rd_num("int", s.a + off)
            if v and v >= 0 and v <= 5 then
                local g = groups[s.par]
                if not g then g = {}; groups[s.par] = g end
                if g[v] then ok = false; break end   -- duplicate limb in one package: not BodyPart
                g[v] = true
                pass = pass + 1
            end
        end
        if ok and pass >= q then
            -- demand one real package: a character showing >= 4 distinct limb values
            for _, g in pairs(groups) do
                local n = 0
                for _ in pairs(g) do n = n + 1 end
                if n >= 4 then found = off; cands = cands + 1; break end
            end
        end
    end
    if cands == 1 then return found end
    return nil
end

-- Resolve every offset from live instances. A bounded workspace walk samples each class
-- (stride-sampled so one cloned model can't dominate), each class is pinned by its anchor
-- signature, and the remaining fields are layout hypotheses validated against the samples with
-- a window-scan rescue. Re-runnable: already-resolved families short-circuit, unresolved ones
-- retry as more of the place streams in.
local function resolve_offsets(attempt)
    pcall(function()
        local DC, TX, SM, CM, SA, BP, PT, CMH = {}, {}, {}, {}, {}, {}, {}, {}
        local n_part = 0
        local budget = 5000
        local walked_char = {}   -- char Model addresses done in the pre-pass; the main walk skips
                                 -- them (21 players double-walked starved map sampling, observed)
        local function collect(n, d)
            if budget <= 0 or d > 16 then return end
            budget = budget - 1
            local ok, kids = pcall(function() return n:GetChildren() end)
            if not ok or not kids then return end
            local nk = #kids
            -- Rotate the TOP-LEVEL start point per attempt: one budget can't cover a big map, so
            -- successive attempts walk different regions (a subtree at the end of the child order
            -- was otherwise never sampled and its whole class family stayed unresolved, observed).
            local off0 = (d == 0 and nk > 0) and (((attempt or 0) * 11) % nk) or 0
            for ii = 1, nk do
                local k = kids[1 + (ii - 1 + off0) % nk]
                local c, a = k.ClassName, k.Address
                local valid = type(a) == "number" and a ~= 0
                if not (valid and walked_char[a]) then
                    if valid then
                        if c == "Decal" then
                            if #DC < 12 then DC[#DC + 1] = a end
                        elseif c == "Texture" then
                            if #TX < 12 then TX[#TX + 1] = a end
                        elseif c == "SpecialMesh" then
                            if #SM < 14 then SM[#SM + 1] = a end
                        elseif c == "CylinderMesh" or c == "BlockMesh" then
                            if #CM < 14 then CM[#CM + 1] = a end
                        elseif c == "SurfaceAppearance" then
                            if #SA < 14 then SA[#SA + 1] = a end
                        elseif c == "CharacterMesh" then
                            if #CMH < 15 then
                                local pa = n.Address
                                CMH[#CMH + 1] = { a = a, par = (type(pa) == "number") and pa or 0 }
                            end
                        elseif PART_CLASSES[c] then
                            n_part = n_part + 1
                            if n_part % 3 == 1 and #BP < 24 then BP[#BP + 1] = a end
                            -- Parts carry sandbox-readable Color -> ground-truth anchor for Shape
                            if c == "Part" and n_part % 5 == 1 and #PT < 16 then
                                local okc, col = pcall(function() return k.Color end)
                                if okc and col then PT[#PT + 1] = { a = a, r = col.R, g = col.G, b = col.B } end
                            end
                        end
                    end
                    collect(k, d + 1)
                end
            end
        end
        -- characters first: CharacterMesh samples live on players, and a big map can exhaust the
        -- walk budget before the walk reaches them
        local okt, top = pcall(function() return game.Workspace:GetChildren() end)
        if okt and top then
            for i = 1, #top do
                local t = top[i]
                if t.ClassName == "Model" then
                    local hum = nil
                    pcall(function() hum = t:FindFirstChild("Humanoid") end)
                    if hum then
                        collect(t, 1)
                        local ta = t.Address
                        if type(ta) == "number" then walked_char[ta] = true end
                    end
                end
            end
        end
        collect(game.Workspace, 0)
        -- Decal and Texture share the FaceInstance struct: pooled for the anchor and Face,
        -- split for tiling (Texture-only fields). Same idea for the DataModelMesh classes.
        local DCTX = {}
        for i = 1, #DC do DCTX[#DCTX + 1] = DC[i] end
        for i = 1, #TX do DCTX[#DCTX + 1] = TX[i] end
        local DMM = {}
        for i = 1, #SM do DMM[#DMM + 1] = SM[i] end
        for i = 1, #CM do DMM[#DMM + 1] = CM[i] end

        -- BasePart Primitive + Material: the unique (ptr offset, ushort offset) pair landing in
        -- Enum.Material for every part. Enum membership is selective enough to pin both at once.
        if not OFF_GOT.mat and #BP >= 8 then
            local win_p, win_m, wins = nil, nil, 0
            for poff = 300, 348, 4 do
                for moff = 558, 574, 2 do
                    local good, total = 0, 0
                    for _, a in ipairs(BP) do
                        local p = memory.Read("pointer", a + poff)
                        if type(p) == "number" and p ~= 0 and memory.IsValid(p) then
                            total = total + 1
                            if MAT_VALID[memory.Read("ushort", p + moff)] then good = good + 1 end
                        end
                    end
                    if total >= 8 and good == total then wins = wins + 1; win_p, win_m = poff, moff end
                end
            end
            if wins == 1 then OFF.prim, OFF.mat, OFF_GOT.mat = win_p, win_m, true end
        end

        -- BasePart Shape: Color3uint8 is ground truth (match part.Color byte-triples), then the
        -- Shape byte is the layout hypothesis off it, validated; window rescue on failure.
        if not OFF_GOT.shape and #PT >= 8 then
            local c3, q = nil, quorum(#PT)
            for off = 384, 456, 1 do
                local pass = 0
                for _, p in ipairs(PT) do
                    if rd_num("byte", p.a + off) == p.r
                        and rd_num("byte", p.a + off + 1) == p.g
                        and rd_num("byte", p.a + off + 2) == p.b then pass = pass + 1 end
                end
                if pass >= q then c3 = off; break end
            end
            if c3 then
                local sh = nil
                if ok_shape_byte(PT, c3 + D.shape) then sh = c3 + D.shape
                else sh = scan_shape(PT, c3) end
                if sh then OFF.shape, OFF_GOT.shape = sh, true end
            end
        end

        -- Decal/Texture: ColorMapContent (asset string) anchors the class; Face and Transparency
        -- are layout hypotheses validated on the live samples (Face gets a window rescue; the
        -- Transparency window is hopeless -- on an all-opaque map every zero float qualifies).
        if not OFF_GOT.dc and #DCTX >= 2 then
            local anchor = scan_asset(DCTX, 360, 440)
            if anchor then
                OFF.dc_tex = anchor
                local face = nil
                if ok_enum(DCTX, anchor + D.dc_face, 5) then face = anchor + D.dc_face
                else face = scan_enum(DCTX, anchor - 224, anchor - 128, 5) end
                if face then
                    OFF.dc_face, OFF_GOT.dc = face, true
                    if ok_unit_float(DCTX, anchor + D.dc_tr) then
                        OFF.dc_tr, OFF_GOT.dc_tr = anchor + D.dc_tr, true
                    end
                end
            end
        end
        -- Texture tiling: needs actual Texture samples (Decals share the struct but have no
        -- tiling floats -- pooled validation could never pass on a mixed sample). The layout
        -- hypothesis accepts a single sample; the window rescue needs at least two.
        if not OFF_GOT.tx and OFF.dc_tex and #TX >= 1 then
            if ok_tile(TX, OFF.dc_tex + D.tx_u) then
                OFF.tx_tileu, OFF.tx_tilev, OFF_GOT.tx = OFF.dc_tex + D.tx_u, OFF.dc_tex + D.tx_v, true
            elseif #TX >= 2 then
                for off = OFF.dc_tex + 196, OFF.dc_tex + 256, 4 do
                    if ok_tile(TX, off) then
                        OFF.tx_tileu, OFF.tx_tilev, OFF_GOT.tx = off, off + 4, true
                        break
                    end
                end
            end
        end

        -- DataModelMesh (SpecialMesh/CylinderMesh/BlockMesh): the adjacent Offset/Scale vec3
        -- pair anchors the base class -- no asset string needed, so geometric-mesh-only maps
        -- (where SpecialMeshes matter most: spheres, heads, skydomes) still resolve.
        if not OFF_GOT.sm then
            local pair = scan_dmm_pair(DMM)
            if pair then
                OFF.sm_off, OFF.sm_scale = pair, pair + 12
                OFF_GOT.sm, OFF_GOT.sm_off = true, true
            end
        end
        -- SpecialMesh-only fields hang off the Scale anchor: MeshType (enum byte), MeshId and
        -- TextureId (asset strings; unresolved on maps with no FileMesh -- nothing to stream).
        if OFF_GOT.sm and #SM >= 2 then
            local scale = OFF.sm_scale
            if not OFF.sm_type and ok_enum(SM, scale + D.sm_type, 11, "byte") then
                OFF.sm_type = scale + D.sm_type
            end
            if not OFF_GOT.sm_str and ok_asset_str(SM, scale + D.sm_str) then
                OFF.sm_mesh, OFF_GOT.sm_str = scale + D.sm_str, true
            end
            if not OFF_GOT.sm_str then
                -- rescue: pin MeshId by argmax string scan (works when FileMesh samples exist)
                local mesh = scan_asset(SM, 240, 300, 3)
                if mesh then OFF.sm_mesh, OFF_GOT.sm_str = mesh, true end
            end
            if OFF_GOT.sm_str and not OFF_GOT.sm_tex then
                if ok_asset_str(SM, scale + D.sm_tex) then
                    OFF.sm_tex, OFF_GOT.sm_tex = scale + D.sm_tex, true
                else
                    local stex = scan_asset(SM, OFF.sm_mesh + 16, OFF.sm_mesh + 80, 1)
                    if stex and stex ~= OFF.sm_mesh then OFF.sm_tex, OFF_GOT.sm_tex = stex, true end
                end
            end
        end

        -- SurfaceAppearance ColorMap (asset string)
        if not OFF_GOT.sa and #SA >= 2 then
            local cm = scan_asset(SA, 192, 264)
            if cm then OFF.sa_color, OFF_GOT.sa = cm, true end
        end

        -- CharacterMesh (packaged R6 limbs): MeshId content string anchors the class; BodyPart
        -- is the layout hypothesis validated by the permutation signature, window-rescued.
        if not OFF_GOT.cm and #CMH >= 4 then
            local flat = {}
            for i = 1, #CMH do flat[i] = CMH[i].a end
            local anchor = scan_asset(flat, 240, 300)
            if anchor then
                local body = scan_cm_body(CMH, anchor + D.cm_body, anchor + D.cm_body)
                    or scan_cm_body(CMH, anchor + 16, anchor + 160)
                if body then OFF.cm_mesh, OFF.cm_body, OFF_GOT.cm = anchor, body, true end
            end
        end
    end)
end

-- Re-resolve over the first few seconds in a place (instances stream in gradually) until the
-- core families resolve or the attempt budget is spent. Offsets are build-global, so a family
-- stays resolved across places this session.
local resolve_attempts = 0
local RESOLVE_MAX = 8
-- CharacterMesh samples only exist while packaged players are present, and one can join after
-- the attempt budget is spent: seeing a CharacterMesh while the cm family is unresolved re-arms
-- one more resolve (bounded by this counter so a never-resolving game can't re-scan forever).
local cm_rearm = 0
local CM_REARM_MAX = 6
local function offsets_ready() return OFF_GOT.mat and OFF_GOT.dc end
resolve_offsets(0)   -- first pass now (covers an in-game script reload immediately)

-- Rig bone sets. R15 has no "Torso"; R6 has no "UpperTorso".
local R6_BONES = { "Head", "Torso", "HumanoidRootPart", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
-- Enum.BodyPart -> the R6 limb part a CharacterMesh replaces
local CM_BONE = { [0] = "Head", [1] = "Torso", [2] = "Left Arm", [3] = "Right Arm",
                  [4] = "Left Leg", [5] = "Right Leg" }
local R15_BONES = {
    "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart",
    "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
}

local floor  = math.floor
local sqrt   = math.sqrt
local format = string.format
local concat = table.concat

-- ===== state =====
local scan          = nil
local scanned_place = nil
local last_scan_done = 0
local last_pwrite    = 0
local last_pid       = nil  -- place id seen last tick; any change triggers a full state clear
local pos_cache  = {}  -- name -> {x, z}  (for facing delta)
local face_cache = {}  -- name -> {fx, fz}
local mat_cache  = {}  -- part Address -> Enum.Material value or false; material is static, so
                       -- the pointer-chase runs once per part instead of every rescan
local force_scan = false  -- set by the viewer's "load map now" button (one-shot)
-- Teleport grace: instances churn violently while a new place streams in, and memory reads on
-- a dying instance are the prime crash suspect (joins with the menu closed crash hardest -- no
-- menu pause throttling the callbacks). No memory reads or new scans until the place settles.
local place_changed_at = 0
local function mem_safe() return utility.GetTickCount() - place_changed_at > 3000 end

-- ===== helpers =====
local function now_ts() return utility.GetTimestamp() end
local function place_id() return game.PlaceId or 0 end

-- Reverse IPC: the viewer writes stream/config.json; apply rates live (no JSON lib, so match numbers).
local CHAMS_ON = false   -- when the viewer enables chams, also stream each player's body-part boxes
-- detail flags (viewer-pushed; default off so a standalone stream does no memory reads)
local DETAIL_DECALS    = false   -- dc (Decal/Texture children: face + asset id) via memory
local DETAIL_MESHES    = false   -- classic SpecialMesh/CylinderMesh/BlockMesh children via memory
local DETAIL_MATERIALS = false   -- mt (Enum.Material value) via memory
local MAP_AUTO   = true   -- auto re-scan the map every MAP_RESCAN_MS (viewer toggle)
local last_map_now = 0    -- last "load map now" trigger value seen from the viewer
local function apply_config()
    local raw = file.read(F_CONFIG)
    if not raw then return end
    local hz  = tonumber(raw:match('"player_hz"%s*:%s*([%d%.]+)'))
    local sec = tonumber(raw:match('"map_rescan_s"%s*:%s*([%d%.]+)'))
    local rad = tonumber(raw:match('"radius"%s*:%s*([%d%.]+)'))
    local ch  = raw:match('"chams"%s*:%s*(%a+)')
    local dcl = raw:match('"decals"%s*:%s*(%a+)')
    local cm  = raw:match('"classic_meshes"%s*:%s*(%a+)')
    local mtl = raw:match('"materials"%s*:%s*(%a+)')
    local auto = raw:match('"map_auto"%s*:%s*(%a+)')
    local mnow = tonumber(raw:match('"map_now"%s*:%s*([%d%.]+)'))
    if hz and hz > 0 then PLAYER_INTERVAL = 1000 / hz end
    if sec and sec > 0 then MAP_RESCAN_MS = sec * 1000 end
    if rad and rad >= 0 then RADIUS = rad end
    if ch then CHAMS_ON = (ch == "true") end
    if auto then MAP_AUTO = (auto == "true") end
    if mnow and mnow > last_map_now then last_map_now = mnow; force_scan = true end
    if dcl then DETAIL_DECALS = (dcl == "true") end
    if cm then DETAIL_MESHES = (cm == "true") end
    if mtl then DETAIL_MATERIALS = (mtl == "true") end
end

local function json_str(s)
    s = tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"')
    return '"' .. s .. '"'
end

local function write_meta(status, map_ready)
    file.write(F_META, format('{"status":"%s","place_id":%d,"t":%d,"map_ready":%s}',
        status, place_id(), now_ts(), map_ready and "true" or "false"))
end

local function reset_files()
    file.mkdir(STREAM_DIR)
    file.write(F_META,    '{"status":"loading","place_id":0,"t":0,"map_ready":false}')
    file.write(F_MAP,     '{"place_id":0,"count":0,"parts":[]}')
    file.write(F_PLAYERS, '{"place_id":0,"t":0,"players":[]}')
end

-- ===== character resolution =====
-- Most games parent characters at the workspace root, but plenty use a container instead
-- (Workspace.Characters, Alive, etc.) — there, FindFirstChild(name) at the root finds nothing
-- and every character feature dies (rig misdetected, 2 bones, no pb). Resolve root-first, then
-- scan top-level Folders/Models for a Model named after the player. The container that hits is
-- cached so the scan runs once per game, and misses (dead players) re-scan at most every 2s.
local char_root    = nil   -- container holding character models (nil until a scan hits)
local char_scan_at = 0
local function find_char(name)
    local ws = game.Workspace
    local c = ws:FindFirstChild(name)
    if c then return c end
    if char_root then
        local hit
        pcall(function() hit = char_root:FindFirstChild(name) end)
        if hit then return hit end
    end
    local now = utility.GetTickCount()
    if now - char_scan_at < 2000 then return nil end
    char_scan_at = now
    local found
    pcall(function()
        for _, ch in ipairs(ws:GetChildren()) do
            local cc = ch.ClassName
            if cc == "Folder" or cc == "Model" then
                local f = ch:FindFirstChild(name)
                if f and f.ClassName == "Model" then found = ch; return end
            end
        end
    end)
    if found then
        char_root = found
        return found:FindFirstChild(name)
    end
    return nil
end

local function local_pos()
    local lp = entity.GetLocalPlayer()
    if not lp then return nil end
    local char = find_char(lp.Name)
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local p = hrp.Position
    if type(p.X) ~= "number" then return nil end
    return p.X, p.Y, p.Z
end

-- Scan centre: prefer the viewer's camera position (so freecam loads what you're looking at),
-- fall back to the local player when the camera feed is stale/absent. cx/cz may be negative.
local function scan_center()
    local raw = file.read(F_VIEW)
    if raw then
        local t = tonumber(raw:match('"t"%s*:%s*([%d%.]+)'))
        if t and (now_ts() - t) <= 5 then
            local cx = tonumber(raw:match('"cx"%s*:%s*(%-?[%d%.]+)'))
            local cy = tonumber(raw:match('"cy"%s*:%s*(%-?[%d%.]+)'))
            local cz = tonumber(raw:match('"cz"%s*:%s*(%-?[%d%.]+)'))
            if cx and cz then return cx, cy, cz end
        end
    end
    return local_pos()
end

-- ===== chunked, radius-limited, rotation-correct map scan =====
local function start_scan()
    local lx, _, lz = scan_center()   -- camera if the viewer is feeding it, else the player
    scan = {
        stack = { game.Workspace }, parts = {}, count = 0,
        lx = lx, lz = lz, radius2 = (RADIUS > 0 and lx) and (RADIUS * RADIUS) or nil,
    }
end

-- emit_part_inner runs under pcall(fn, node, kids) — a static function, not a fresh closure,
-- so the scan doesn't allocate one per part (SCAN_BUDGET of them per frame while scanning)
local function emit_part_inner(node, kids)
        local tr = node.Transparency
        if type(tr) ~= "number" then return end
        if tr >= 1 then
            -- the engine renders Decal/Texture children at FULL visibility even on a fully
            -- transparent part (the classic floating-sign pattern: invisible part + decal).
            -- Keep such parts (t=1 -> the viewer shows only the decal pixels); drop the rest.
            if not (DETAIL_DECALS and kids) then return end
            local has = false
            for i = 1, #kids do
                local cc = kids[i].ClassName
                if cc == "Decal" or cc == "Texture" then has = true; break end
            end
            if not has then return end
            tr = 1
        end
        local pos = node.Position
        if type(pos.X) ~= "number" then return end
        if scan.radius2 then
            local dx, dz = pos.X - scan.lx, pos.Z - scan.lz
            if dx * dx + dz * dz > scan.radius2 then return end
        end
        local col = node.Color
        if type(col.R) ~= "number" then return end
        local corners = draw.GetPartCorners(node)
        if not corners or #corners < 8 then return end
        local c1, c2, c3, c5, c8 = corners[1], corners[2], corners[3], corners[5], corners[8]
        local cls = node.ClassName
        -- transparency / reflectance: streamed only when nonzero (most parts are 0/0)
        local extra = ""
        if tr > 0 then extra = format(',"t":%.2f', tr) end
        local refl = node.Reflectance
        if type(refl) == "number" and refl > 0 then extra = extra .. format(',"r":%.2f', refl) end
        -- mesh asset id for MeshParts ("rbxassetid://NNN" or "...?id=NNN") so the viewer can
        -- optionally render the real mesh instead of the bounding box
        if cls == "MeshPart" then
            local mid = node.MeshId
            if type(mid) == "string" then
                local id = mid:match("(%d+)%s*$")
                if id then extra = extra .. format(',"m":"%s"', id) end
            end
            -- texture asset id, for the viewer's optional textured-mesh rendering
            local tid = node.TextureId
            local tx = type(tid) == "string" and tid:match("(%d+)%s*$") or nil
            -- a SurfaceAppearance child OVERRIDES TextureId in-engine; without this the part
            -- renders with the (often stale/unrelated) legacy TextureId texture
            if DETAIL_MESHES and OFF_GOT.sa and kids then
                for i = 1, #kids do
                    if kids[i].ClassName == "SurfaceAppearance" then
                        pcall(function()
                            local cm = memory.Read("string", kids[i].Address + OFF.sa_color):match("(%d+)%s*$")
                            if cm and cm ~= "0" then tx = cm end
                        end)
                        break
                    end
                end
            end
            if tx then extra = extra .. format(',"tx":"%s"', tx) end
        end
        -- CSG unions: their geometry is irrecoverable (no fetchable mesh asset — the CSG result
        -- lives in the place file), so they always render as bounding boxes. Flag them so the
        -- viewer's "Hide unions" toggle can drop them instead.
        if cls == "UnionOperation" then extra = extra .. ',"un":1' end
        -- shape: free from the ClassName for wedges; a memory byte for Part's Ball/Cylinder.
        -- Codes the viewer understands: 0=ball, 2=cylinder (X axis), 3=wedge, 4=corner wedge,
        -- 5=classic CylinderMesh (Y axis). Block (1) is the default and never streamed.
        local sh = nil
        if cls == "WedgePart" then sh = 3
        elseif cls == "CornerWedgePart" then sh = 4
        elseif cls == "TrussPart" then sh = 7
        elseif cls == "Part" and OFF_GOT.shape then
            -- Enum.PartType byte: Ball=0, Block=1 (default, never streamed), Cylinder=2, Wedge=3,
            -- CornerWedge=4 (the 2023 additions map onto the same viewer codes as the legacy classes).
            pcall(function()
                local addr = node.Address
                if type(addr) == "number" and addr ~= 0 then
                    local b = memory.Read("byte", addr + OFF.shape)
                    if b >= 0 and b <= 4 and b ~= 1 then sh = b end
                end
            end)
        end
        -- material: Enum.Material ushort behind the Primitive pointer. Misreads land outside
        -- MAT_VALID and are dropped silently; Plastic (256, the default) is never streamed.
        if DETAIL_MATERIALS and OFF_GOT.mat then
            local addr = node.Address
            local mt = (type(addr) == "number") and mat_cache[addr]
            if mt == nil then   -- not yet resolved for this address: do the pointer-chase once
                mt = false
                pcall(function()
                    if type(addr) == "number" and addr ~= 0 then
                        local prim = memory.Read("pointer", addr + OFF.prim)
                        if type(prim) == "number" and prim ~= 0 and memory.IsValid(prim) then
                            local m = memory.Read("ushort", prim + OFF.mat)
                            if MAT_VALID[m] and m ~= 256 then mt = m end
                        end
                    end
                end)
                if type(addr) == "number" then mat_cache[addr] = mt end
            end
            if mt then extra = extra .. format(',"mt":%d', mt) end
        end
        -- children carry the classic visuals: Decal/Texture (face textures on plain parts) and
        -- SpecialMesh/CylinderMesh/BlockMesh (pre-MeshPart mesh modifiers). The traversal already
        -- fetched kids; MeshParts skip this (they render their own mesh, child decals are rare).
        if kids and (DETAIL_DECALS or DETAIL_MESHES) and cls ~= "MeshPart" then
            local dcs, ndc = {}, 0
            for i = 1, #kids do
                local ch = kids[i]
                local ccls = ch.ClassName
                if DETAIL_DECALS and OFF_GOT.dc and ndc < 6 and (ccls == "Decal" or ccls == "Texture") then
                    pcall(function()
                        local tex = memory.Read("string", ch.Address + OFF.dc_tex)
                        -- numeric ids only: rbxasset:// (engine-local files) can't be fetched
                        local id = (not tex:match("^rbxasset://")) and tex:match("(%d+)%s*$") or nil
                        if id and id ~= "0" then
                            local face = memory.Read("int", ch.Address + OFF.dc_face)
                            if type(face) == "number" and face >= 0 and face <= 5 then
                                -- Decal.Transparency (Texture shares the offset): fully invisible
                                -- decals are dropped; partial opacity rides the entry tail -- Decal
                                -- [f,id,tr], Texture [f,id,tileU,tileV,tr]. Only when its offset
                                -- resolved; otherwise decals stream opaque.
                                local dtr = 0
                                if OFF_GOT.dc_tr then
                                    local v = memory.Read("float", ch.Address + OFF.dc_tr)
                                    dtr = (type(v) == "number" and v > 0.01 and v <= 1.01) and v or 0
                                end
                                if dtr < 0.99 then
                                    ndc = ndc + 1
                                    -- Texture instances TILE at StudsPerTileU/V (Decals stretch once):
                                    -- [face,id,tileU,tileV] entries so the viewer can repeat it
                                    local entry
                                    if ccls == "Texture" then
                                        local tu, tv
                                        if OFF_GOT.tx then
                                            local u = memory.Read("float", ch.Address + OFF.tx_tileu)
                                            local v = memory.Read("float", ch.Address + OFF.tx_tilev)
                                            if type(u) == "number" and u > 0.01 and u < 1e4
                                                and type(v) == "number" and v > 0.01 and v < 1e4 then tu, tv = u, v end
                                        end
                                        -- a Texture NEVER stretches in-engine: when its tiling is
                                        -- unreadable, the class default (StudsPerTile = 2) is wrong at
                                        -- worst about density -- the stretch form is wrong always
                                        tu = tu or 2
                                        tv = tv or 2
                                        if dtr > 0 then entry = format('[%d,"%s",%.2f,%.2f,%.2f]', face, id, tu, tv, dtr)
                                        else entry = format('[%d,"%s",%.2f,%.2f]', face, id, tu, tv) end
                                    else
                                        -- Decal: stretched once across the face IS the engine behaviour
                                        if dtr > 0 then entry = format('[%d,"%s",%.2f]', face, id, dtr)
                                        else entry = format('[%d,"%s"]', face, id) end
                                    end
                                    dcs[ndc] = entry
                                end
                            end
                        end
                    end)
                elseif DETAIL_MESHES and OFF_GOT.sm and (ccls == "SpecialMesh" or ccls == "CylinderMesh" or ccls == "BlockMesh") then
                    pcall(function()
                        -- rd_vec3 returns nil on the string sentinel; indexing .X raw would throw
                        -- and silently abort this whole child block, skipping the misread guard
                        local sc = rd_vec3(ch.Address + OFF.sm_scale)
                        local sx, sy, sz = 1, 1, 1
                        if sc then sx, sy, sz = sc.X, sc.Y, sc.Z end
                        -- NEGATIVE scales are legit (the classic mirror trick — flipped wedges,
                        -- inside-out skydomes); only clamp magnitude. The viewer mirrors via the
                        -- instance matrix and reverts world-swallowing extents to the part size.
                        local ax, ay, az = math.abs(sx), math.abs(sy), math.abs(sz)
                        if not (ax > 1e-4 and ax < 1e4 and ay > 1e-4 and ay < 1e4 and az > 1e-4 and az < 1e4) then
                            sx, sy, sz = 1, 1, 1   -- misread guard
                        end
                        -- DataModelMesh.Offset displaces the rendered mesh from the part centre
                        -- (part-local studs); streamed as "mo" so the viewer renders at the true spot
                        local mo = ""
                        if OFF_GOT.sm_off then
                            local ofs = rd_vec3(ch.Address + OFF.sm_off)
                            local ox, oy, oz = 0, 0, 0
                            if ofs then ox, oy, oz = ofs.X, ofs.Y, ofs.Z end
                            if ox*ox + oy*oy + oz*oz > 1e-6
                               and ox > -1e4 and ox < 1e4 and oy > -1e4 and oy < 1e4 and oz > -1e4 and oz < 1e4 then
                                mo = format(',"mo":[%.3f,%.3f,%.3f]', ox, oy, oz)
                            end
                        end
                        local file_mesh = false
                        if ccls == "SpecialMesh" then
                            local mid = nil
                            if OFF_GOT.sm_str then
                                local s = memory.Read("string", ch.Address + OFF.sm_mesh)
                                if type(s) == "string" then mid = s:match("(%d+)%s*$") end
                            end
                            if mid and mid ~= "0" then
                                -- FileMesh: renders at native mesh size x Scale, NOT the part size --
                                -- "e":1 tells the viewer to use that scaling
                                extra = extra .. format(',"m":"%s","e":1,"ms":[%.3f,%.3f,%.3f]', mid, sx, sy, sz)
                                file_mesh = true
                                if OFF_GOT.sm_tex then
                                    local tid = memory.Read("string", ch.Address + OFF.sm_tex):match("(%d+)%s*$")
                                    if tid and tid ~= "0" then extra = extra .. format(',"tx":"%s"', tid) end
                                end
                            elseif OFF.sm_type then
                                -- typeless SpecialMesh: the MeshType byte picks a geometric shape
                                -- that scales with the part size (Enum.MeshType: Head=0, Torso=1,
                                -- Wedge=2, Sphere=3, Cylinder=4, Brick=6, ..., CornerWedge=11)
                                local mt = memory.Read("byte", ch.Address + OFF.sm_type)
                                if mt == 3 or mt == 0 then sh = 6      -- Sphere / classic Head -> ellipsoid
                                elseif mt == 4 then sh = 5             -- Cylinder (Y axis)
                                elseif mt == 2 then sh = 3             -- Wedge
                                elseif mt == 11 then sh = 4 end        -- CornerWedge
                                -- Torso/Brick/Prism/Pyramid/ramps and misreads stay boxes
                            end
                        elseif ccls == "CylinderMesh" then
                            sh = 5
                        end
                        -- geometric types and Cylinder/BlockMesh: Scale multiplies the part size
                        if not file_mesh and (sx ~= 1 or sy ~= 1 or sz ~= 1) then
                            extra = extra .. format(',"ms":[%.3f,%.3f,%.3f]', sx, sy, sz)
                        end
                        extra = extra .. mo
                    end)
                end
            end
            if ndc > 0 then extra = extra .. ',"dc":[' .. concat(dcs, ",") .. ']' end
        end
        if sh then extra = extra .. format(',"sh":%d', sh) end
        scan.count = scan.count + 1
        scan.parts[scan.count] = format(
            '{"p":[%.3f,%.3f,%.3f],"u":[%.3f,%.3f,%.3f],"v":[%.3f,%.3f,%.3f],"w":[%.3f,%.3f,%.3f],"c":[%d,%d,%d]%s}',
            (c1.X + c8.X) * 0.5, (c1.Y + c8.Y) * 0.5, (c1.Z + c8.Z) * 0.5,
            c2.X - c1.X, c2.Y - c1.Y, c2.Z - c1.Z,
            c3.X - c1.X, c3.Y - c1.Y, c3.Z - c1.Z,
            c5.X - c1.X, c5.Y - c1.Y, c5.Z - c1.Z,
            floor(col.R + 0.5), floor(col.G + 0.5), floor(col.B + 0.5), extra)
end

local function emit_part(node, kids)
    pcall(emit_part_inner, node, kids)
end

local function step_scan()
    local stack = scan.stack
    local processed = 0
    while #stack > 0 and processed < SCAN_BUDGET do
        local node = stack[#stack]
        stack[#stack] = nil
        processed = processed + 1
        local cls = node.ClassName
        -- one GetChildren serves the character check, the traversal, AND emit_part's
        -- decal/mesh child scan (a separate is_character() doubled the calls on every Model)
        local kids = node:GetChildren()
        if cls == "Model" and kids then
            for i = 1, #kids do
                if kids[i].ClassName == "Humanoid" then kids = nil; break end   -- character: skip subtree
            end
        end
        if PART_CLASSES[cls] then emit_part(node, kids) end
        if kids then
            for i = 1, #kids do stack[#stack + 1] = kids[i] end
        end
    end
    if #stack == 0 then
        file.write(F_MAP, format('{"place_id":%d,"count":%d,"parts":[%s]}',
            place_id(), scan.count, concat(scan.parts, ",")))
        scanned_place = place_id()
        last_scan_done = utility.GetTickCount()
        scan = nil
        write_meta("ready", true)
    end
end

-- ===== player stream =====
local function rig_of(char)
    if char and char:FindFirstChild("UpperTorso") then return "R15" end
    return "R6"
end

-- `part`/`looked_up`: when the caller already resolved char:FindFirstChild(bone) (so it can be reused
-- by the pb block), it passes the part and looked_up=true so we don't look it up a second time.
local function read_bone(p, char, bone, part, looked_up)
    if p.IsEnemy then
        local b = p:GetBonePosition(bone)
        if b and not (b.X == 0 and b.Y == 0 and b.Z == 0) then return b.X, b.Y, b.Z end
    end
    if not looked_up and char then part = char:FindFirstChild(bone) end
    if part then
        local pos = part.Position
        if type(pos.X) == "number" then return pos.X, pos.Y, pos.Z end
    end
    return nil
end

-- Facing from the HRP's rotation matrix. Animations never rotate the HumanoidRootPart, so this is
-- sway-free (unlike skeleton-derived facing) and follows in-place turns exactly. The matrix is the
-- CFrame rotation components row-major (R00..R22); LookVector = -(R02, R12, R22) = -(m[3],m[6],m[9]).
local function facing_from_rotation(p)
    local ok, m = pcall(function() return p:GetBoneRotation("HumanoidRootPart") end)
    if not ok or type(m) ~= "table" or #m < 9 then return nil end
    local fx, fz = -m[3], -m[9]
    local d = sqrt(fx * fx + fz * fz)
    if d < 1e-4 then return nil end
    return { fx / d, fz / d }
end

-- Skeleton-derived facing — fallback for players whose HRP rotation isn't in the entity cache
-- (the cache is documented enemy-only; rotation availability for teammates is unverified).
-- right = (rightSide - leftSide); summing shoulders + hips cancels stride wobble because arms and
-- legs counter-swing. Roblox LookVector = Up x Right  =>  forward = (right.z, -right.x).
local function facing_from_bones(bpos, rig)
    local ra, la, rl, ll
    if rig == "R15" then
        ra, la = bpos["RightUpperArm"], bpos["LeftUpperArm"]
        rl, ll = bpos["RightUpperLeg"], bpos["LeftUpperLeg"]
    else
        ra, la = bpos["Right Arm"], bpos["Left Arm"]
        rl, ll = bpos["Right Leg"], bpos["Left Leg"]
    end
    local rx, rz, cnt = 0, 0, 0
    if ra and la then rx = rx + (ra[1] - la[1]); rz = rz + (ra[3] - la[3]); cnt = cnt + 1 end
    if rl and ll then rx = rx + (rl[1] - ll[1]); rz = rz + (rl[3] - ll[3]); cnt = cnt + 1 end
    if cnt == 0 then return nil end
    local fx, fz = rz, -rx
    local d = sqrt(fx * fx + fz * fz)
    if d < 1e-4 then return nil end
    return { fx / d, fz / d }
end

-- Movement-delta facing — fallback only (e.g. when a character exposes just Head + HRP).
local function update_facing(name, x, z)
    local last = pos_cache[name]
    pos_cache[name] = { x, z }
    if last then
        local dx, dz = x - last[1], z - last[2]
        local d2 = dx * dx + dz * dz
        if d2 > 0.0025 then
            local d = sqrt(d2)
            face_cache[name] = { dx / d, dz / d }
        end
    end
    return face_cache[name]
end

-- ===== pb entries (oriented box + optional mesh id per character part) =====
-- 12 numbers = plain box; +13th string = MeshPart mesh id (mesh renders AT the part size);
-- +3 more numbers = mesh renders at native size x that Scale (classic Part+SpecialMesh handles,
-- and packaged R6 limbs via CharacterMesh, whose meshes have no Scale -- streamed as 1,1,1).
local PB_FMT = '%s:[%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f%s]'
local pb_mesh_cache = {}   -- part Address -> SpecialMesh suffix string ("" = none); never changes at runtime
local cm_mesh_cache = {}   -- CharacterMesh Address -> {bn, sfx} | false; one read per instance life
local function pb_mesh_suffix(part)
    local addr = part.Address
    if type(addr) ~= "number" or addr == 0 then return "" end
    local hit = pb_mesh_cache[addr]
    if hit ~= nil then return hit end
    if part.ClassName == "MeshPart" then
        -- sandbox-readable, but cached too: R15 limbs hit this every player tick, and the
        -- MeshId string marshal isn't free across 15 bones x players x stream rate
        local s = part.MeshId
        local id = type(s) == "string" and s:match("(%d+)%s*$") or nil
        local suffix = (id and id ~= "0") and (',"' .. id .. '"') or ""
        pb_mesh_cache[addr] = suffix
        return suffix
    end
    -- classic handle/head: Part + SpecialMesh child. MeshId/Scale are sandbox-invisible —
    -- memory reads, cached per part address so the GetChildren+reads happen once per part.
    if not mem_safe() then return "" end   -- teleport grace: no reads, no caching
    local suffix = ""
    -- needs both the Scale anchor and the MeshId string offset (FileMesh handles only)
    if not (OFF_GOT.sm and OFF_GOT.sm_str) then return "" end
    pcall(function()
        for _, ch in ipairs(part:GetChildren()) do
            if ch.ClassName == "SpecialMesh" then
                local mid = memory.Read("string", ch.Address + OFF.sm_mesh):match("(%d+)%s*$")
                if mid and mid ~= "0" then
                    local sc = memory.Read("vector3", ch.Address + OFF.sm_scale)
                    local sx, sy, sz = sc.X, sc.Y, sc.Z
                    if not (sx > 0 and sx < 1e4 and sy > 0 and sy < 1e4 and sz > 0 and sz < 1e4) then
                        sx, sy, sz = 1, 1, 1
                    end
                    suffix = format(',"%s",%.3f,%.3f,%.3f', mid, sx, sy, sz)
                end
                return
            end
        end
    end)
    pb_mesh_cache[addr] = suffix
    return suffix
end
-- key arrives pre-quoted (json_str(bone) or '"@n"' for accessories); suffix overrides the
-- per-part mesh detection ("" forces a plain box — used for R6 body limbs)
local function pb_entry(key, part, suffix)
    local entry = nil
    pcall(function()
        local c = draw.GetPartCorners(part)
        if c and #c >= 8 then
            local c1, c2, c3, c5, c8 = c[1], c[2], c[3], c[5], c[8]
            entry = format(PB_FMT, key,
                (c1.X + c8.X) * 0.5, (c1.Y + c8.Y) * 0.5, (c1.Z + c8.Z) * 0.5,
                c2.X - c1.X, c2.Y - c1.Y, c2.Z - c1.Z,
                c3.X - c1.X, c3.Y - c1.Y, c3.Z - c1.Z,
                c5.X - c1.X, c5.Y - c1.Y, c5.Z - c1.Z,
                suffix or pb_mesh_suffix(part))
        end
    end)
    return entry
end

-- static pcall targets: player_json runs per player per tick, and pcall(function() end)
-- allocates a fresh closure every call — these run thousands of times a minute
local function p_team(p) return tostring(p.Team) end
local function p_teamcolor(p)
    local c = p.TeamColor
    if c and type(c.R) == "number" then
        return format('[%d,%d,%d]', floor(c.R + 0.5), floor(c.G + 0.5), floor(c.B + 0.5))
    end
    return nil
end
local function p_health(p) return p.Health, p.MaxHealth end
local function p_dn(p) return p.DisplayName end
local function p_vis(p) return p.IsVisible end

local function player_json(p, is_local)
    local char = find_char(p.Name)
    local rig = rig_of(char)
    local bones = (rig == "R15") and R15_BONES or R6_BONES
    local parts, n = {}, 0
    local hx, hz
    local bpos = {}
    -- Resolve each part once and reuse it in the pb block below (avoids a second FindFirstChild per
    -- bone). Keep the enemy fast-path: enemies read bones from the entity cache, so only hit the
    -- workspace when pb actually needs the part instance (chams, or R6's box-derived skeleton).
    local need_pb = (CHAMS_ON or rig == "R6") and char ~= nil
    local resolve_parts = char ~= nil and (need_pb or not p.IsEnemy)
    local bpart = {}
    for _, bn in ipairs(bones) do
        local part = resolve_parts and char:FindFirstChild(bn) or nil
        if part then bpart[bn] = part end
        local x, y, z = read_bone(p, char, bn, part, resolve_parts)
        if x then
            n = n + 1
            parts[n] = format('%s:[%.2f,%.2f,%.2f]', json_str(bn), x, y, z)
            bpos[bn] = { x, y, z }
            if bn == "HumanoidRootPart" then hx, hz = x, z end
        end
    end
    if n == 0 then return nil end
    local face = facing_from_rotation(p)             -- HRP rotation: sway-free, exact
        or facing_from_bones(bpos, rig)              -- skeleton-derived (sways slightly)
    if not face and hx then face = update_facing(p.Name, hx, hz) end
    face = face or face_cache[p.Name]
    local face_str = face and format('[%.4f,%.4f]', face[1], face[2]) or "null"
    local team = "?"
    do local ok, t = pcall(p_team, p); if ok and t then team = t end end
    local tc = "null"   -- in-game team colour (Color3, 0-255), used to colour the skeleton
    do local ok, t = pcall(p_teamcolor, p); if ok and t then tc = t end end
    local kind = is_local and "local" or (p.IsEnemy and "enemy" or "ally")
    -- health, display name, visibility (vis defaults true — IsVisible errors unless a Visible Only check is on)
    local hp, mhp = 100, 100
    do local ok, h, mh = pcall(p_health, p); if ok then hp = h or hp; mhp = mh or mhp end end
    local dn = p.Name
    do local ok, d = pcall(p_dn, p); if ok and type(d) == "string" and #d > 0 then dn = d end end
    local vis = true
    do local ok, v = pcall(p_vis, p); if ok and type(v) == "boolean" then vis = v end end
    -- oriented box per body part, KEYED BY PART NAME (centre p + edge vectors u,v,w from
    -- GetPartCorners) so the viewer can map boxes to limbs. Always sent for R6 (its skeleton is derived
    -- from these); for R15 only when chams is on (R15's skeleton uses joints directly).
    local pb = "null"
    if need_pb then
        local bx, m = {}, 0
        -- One pass over the character's children feeds both: CharacterMesh -> per-limb mesh
        -- suffixes (packaged R6 limbs), Accessory -> handle entries (keyed "@n" so the viewer
        -- hull-chams them individually while the skeleton/ESP-box code skips them).
        local limb_sfx = nil
        local acc_e, acc_n = {}, 0
        local saw_cm = false
        pcall(function()
            local na = 0
            for _, ch in ipairs(char:GetChildren()) do
                local ccls = ch.ClassName
                if ccls == "CharacterMesh" then
                    if OFF_GOT.cm then
                        local a = ch.Address
                        if type(a) == "number" and a ~= 0 then
                            local hit = cm_mesh_cache[a]
                            if hit == nil and mem_safe() then
                                hit = false
                                local s = memory.Read("string", a + OFF.cm_mesh)
                                local b = memory.Read("int", a + OFF.cm_body)
                                local id = (type(s) == "string") and s:match("(%d+)%s*$") or nil
                                local bn = (type(b) == "number") and CM_BONE[b] or nil
                                if id and id ~= "0" and bn then
                                    hit = { bn = bn, sfx = format(',"%s",1,1,1', id) }
                                end
                                cm_mesh_cache[a] = hit
                            end
                            if hit then
                                if not limb_sfx then limb_sfx = {} end
                                limb_sfx[hit.bn] = hit.sfx
                            end
                        end
                    else
                        saw_cm = true
                    end
                elseif ccls == "Accessory" and na < 10 then
                    local handle = ch:FindFirstChild("Handle")
                    if handle then
                        na = na + 1
                        local e = pb_entry(format('"@%d"', na), handle)
                        if e then acc_n = acc_n + 1; acc_e[acc_n] = e end
                    end
                end
            end
        end)
        -- a packaged player can join after the resolve budget is spent: seeing a CharacterMesh
        -- while the cm family is unresolved re-arms one more attempt (bounded)
        if saw_cm and not OFF_GOT.cm and resolve_attempts >= RESOLVE_MAX and cm_rearm < CM_REARM_MAX then
            cm_rearm = cm_rearm + 1
            resolve_attempts = RESOLVE_MAX - 1
        end
        -- R6 body parts: a packaged limb renders its CharacterMesh; the Head may carry its own
        -- SpecialMesh (FileMesh heads ride pb_mesh_suffix); everything else is a plain box --
        -- which IS the classic silhouette (default limbs are real boxes, the fallback is exact).
        for _, bn in ipairs(bones) do
            local part = bpart[bn]   -- reuse the ref resolved above (no second FindFirstChild)
            if part and bn ~= "HumanoidRootPart" then   -- HRP isn't used by the skeleton or chams
                local sfx = nil
                if rig ~= "R15" then
                    sfx = limb_sfx and limb_sfx[bn]
                    if not sfx and bn ~= "Head" then sfx = "" end
                end
                local e = pb_entry(json_str(bn), part, sfx)
                if e then m = m + 1; bx[m] = e end
            end
        end
        for i = 1, acc_n do m = m + 1; bx[m] = acc_e[i] end
        if m > 0 then pb = "{" .. concat(bx, ",") .. "}" end
    end
    return format('{"name":%s,"dn":%s,"kind":"%s","team":%s,"tc":%s,"rig":"%s","hp":%.1f,"mhp":%.1f,"vis":%s,"face":%s,"pb":%s,"bones":{%s}}',
        json_str(p.Name), json_str(dn), kind, json_str(team), tc, rig, hp, mhp,
        vis and "true" or "false", face_str, pb, concat(parts, ","))
end

local function write_players()
    local rows, n = {}, 0
    local lp = entity.GetLocalPlayer()
    if lp then
        local r = player_json(lp, true)
        if r then n = n + 1; rows[n] = r end
    end
    for _, p in ipairs(entity.GetPlayers(false)) do
        local r = player_json(p, false)
        if r then n = n + 1; rows[n] = r end
    end
    file.write(F_PLAYERS, format('{"place_id":%d,"t":%d,"players":[%s]}',
        place_id(), now_ts(), concat(rows, ",")))
end

-- ===== lifecycle =====
reset_files()
apply_config()   -- adopt the viewer's persisted rate settings, if any
write_meta("loading", false)
print("[stream] loaded — wiped files/stream/, scanning map...")

-- Drop everything that references the old game. scan.stack holds Instance userdata from the old
-- workspace — stepping it after a teleport is the prime crash suspect (crashes on the 2nd/3rd
-- instance join). Also wipes the stream files so the viewer clears its player visuals instead of
-- drawing the last in-game snapshot. place_id 0 = in menu / not in a game.
local function clear_game_state(pid)
    scan = nil
    scanned_place = nil
    pos_cache = {}
    face_cache = {}
    -- address-keyed caches are poison across places: old addresses get recycled by new
    -- instances, and reads through them during the join are the prime crash suspect
    pb_mesh_cache = {}
    cm_mesh_cache = {}
    mat_cache = {}
    force_scan = false
    char_root = nil
    char_scan_at = 0
    place_changed_at = utility.GetTickCount()
    reset_files()
    write_meta(pid == 0 and "menu" or "loading", false)
end

cheat.register("onUpdate", function()
    if not active() then return end
    local pid = place_id()
    if pid ~= last_pid then
        last_pid = pid
        clear_game_state(pid)
    end
    if pid == 0 then return end

    if scan == nil and mem_safe() then   -- teleport grace: let the new place settle before scanning
        local now = utility.GetTickCount()
        -- first scan of a place always runs; the manual "load now" button always runs; the
        -- periodic refresh only when auto is enabled
        if scanned_place ~= pid or force_scan
           or (MAP_AUTO and (now - last_scan_done) > MAP_RESCAN_MS) then
            force_scan = false
            start_scan()
        end
    end
    if scan then                          -- progress scan AND stream players the same frame
        -- a node deleted mid-scan (teleport starting) can throw; drop the scan, retry next tick
        if not pcall(step_scan) then scan = nil end
    end

    local now = utility.GetTickCount()
    if now - last_pwrite < PLAYER_INTERVAL then return end
    last_pwrite = now
    write_players()
end)

cheat.register("onSlowUpdate", function()
    if not active() then return end
    apply_config()   -- pick up live rate changes from the viewer
    if place_id() == 0 then
        write_meta("menu", false)   -- keep the heartbeat fresh so the viewer shows "in menu", not stale
        return
    end
    -- self-derive memory offsets as the place streams in (settled instances only); each attempt
    -- rotates its walk start so big maps get cumulative coverage across the attempt budget
    if mem_safe() and resolve_attempts < RESOLVE_MAX then
        resolve_attempts = resolve_attempts + 1
        resolve_offsets(resolve_attempts)
    end
    write_meta(scan and "loading" or "ready", scanned_place ~= nil)
end)

cheat.register("newPlace", function()
    if not active() then return end
    print("[stream] newPlace — clearing old game state")
    last_pid = nil   -- force the onUpdate place-change guard to re-clear with the new pid's status
    resolve_attempts = 0   -- give any still-unresolved offset families fresh samples in the new place
    cm_rearm = 0
    clear_game_state(place_id())
end)

cheat.register("shutdown", function()
    if not active() then return end
    write_meta("offline", false)
    print("[stream] shutdown — wrote offline")
end)
