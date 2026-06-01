local tab = "Basketball"
ui.newTab(tab, "BBL")

local config_save, config_load

-- ============================================================
-- Perfect Shot
-- ============================================================

local ps_con = "Perfect Shot"
ui.newContainer(tab, ps_con, "Perfect Shot", { autosize = true })

local enable_ref   = ui.newCheckbox(tab, ps_con, "Enable Perfect Shot")
local hotkey_ref   = ui.newHotkey(tab, ps_con, "Perfect Shot Key", true, 0)
local duration_ref = ui.newSliderInt(tab, ps_con, "Hold Duration (ms)", 100, 1000, 350)
ui.newCheckbox(tab, ps_con, "Perfect Chance")
ui.newSliderInt(tab, ps_con, "Variance (ms)", 0, 100)

ui.setValue(tab, ps_con, "Variance (ms)", 10)
ui.SetVisibility(tab, ps_con, "Perfect Shot Key",   false)
ui.SetVisibility(tab, ps_con, "Hold Duration (ms)", false)
ui.SetVisibility(tab, ps_con, "Perfect Chance",     false)
ui.SetVisibility(tab, ps_con, "Variance (ms)",      false)

local isProcessing = false
local wasActive    = false

cheat.register("onUpdate", function()
    local enabled     = ui.getValue(tab, ps_con, "Enable Perfect Shot")
    local variance_on = enabled and ui.getValue(tab, ps_con, "Perfect Chance")
    ui.SetVisibility(tab, ps_con, "Perfect Shot Key",   enabled)
    ui.SetVisibility(tab, ps_con, "Hold Duration (ms)", enabled)
    ui.SetVisibility(tab, ps_con, "Perfect Chance",     enabled)
    ui.SetVisibility(tab, ps_con, "Variance (ms)",      variance_on)
end)

cheat.register("onUpdate", function()
    if not ui.getValue(enable_ref) then return end

    local keyActive = ui.getValue(hotkey_ref)

    if keyActive and not wasActive then
        wasActive = true
        if not isProcessing then
            isProcessing = true

            local holdMs = ui.getValue(tab, ps_con, "Hold Duration (ms)")
            if ui.getValue(tab, ps_con, "Perfect Chance") then
                local v = ui.getValue(tab, ps_con, "Variance (ms)")
                holdMs = math.max(1, holdMs + math.random(-v, v))
            end

            keyboard.Press("e")
            local start = utility.GetTickCount()
            while utility.GetTickCount() - start < holdMs do end
            keyboard.Release("e")

            isProcessing = false
        end
    elseif not keyActive then
        wasActive = false
    end
end)

-- ============================================================
-- Shared helpers
-- ============================================================

local cos, sin, sqrt = math.cos, math.sin, math.sqrt
local SEGS   = 32
local TWO_PI = math.pi * 2

local function circle_points(center, radius)
    local pts = {}
    local cx, cy, cz = center.X, center.Y, center.Z
    for i = 0, SEGS - 1 do
        local a = i * (TWO_PI / SEGS)
        local ok, sx, sy, on = pcall(function()
            return utility.WorldToScreen(Vector3.new(cx + cos(a) * radius, cy, cz + sin(a) * radius))
        end)
        if ok and on then pts[#pts + 1] = { sx, sy } end
    end
    return pts
end

-- ============================================================
-- Auto Steal
-- ============================================================

local as_con = "Auto Steal"
ui.newContainer(tab, as_con, "Auto Steal", { autosize = true })

local as_enable   = ui.newCheckbox(tab, as_con, "Enable Auto Steal")
local as_hotkey   = ui.newHotkey(tab, as_con, "Steal Key", true)
local as_show     = ui.newCheckbox(tab, as_con, "Show Zone")
local as_col      = ui.newColorpicker(tab, as_con, "Zone Color", { r = 255, g = 200, b = 0, a = 180 }, true)
local as_radius   = ui.newSliderFloat(tab, as_con, "Steal Radius",   1,  15)
local as_hold_min = ui.newSliderInt(tab,   as_con, "Hold Min (ms)", 50, 500)
local as_hold_max = ui.newSliderInt(tab,   as_con, "Hold Max (ms)", 50, 500)

ui.setValue(tab, as_con, "Steal Radius",  5)
ui.setValue(tab, as_con, "Hold Min (ms)", 80)
ui.setValue(tab, as_con, "Hold Max (ms)", 180)

ui.SetVisibility(tab, as_con, "Steal Key",      false)
ui.SetVisibility(tab, as_con, "Show Zone",       false)
ui.SetVisibility(tab, as_con, "Zone Color",      false)
ui.SetVisibility(tab, as_con, "Steal Radius",    false)
ui.SetVisibility(tab, as_con, "Hold Min (ms)",   false)
ui.SetVisibility(tab, as_con, "Hold Max (ms)",   false)

cheat.register("onUpdate", function()
    local on      = ui.getValue(tab, as_con, "Enable Auto Steal")
    local show_on = on and ui.getValue(tab, as_con, "Show Zone")
    ui.SetVisibility(tab, as_con, "Steal Key",     on)
    ui.SetVisibility(tab, as_con, "Show Zone",     on)
    ui.SetVisibility(tab, as_con, "Zone Color",    show_on)
    ui.SetVisibility(tab, as_con, "Steal Radius",  on)
    ui.SetVisibility(tab, as_con, "Hold Min (ms)", on)
    ui.SetVisibility(tab, as_con, "Hold Max (ms)", on)
end)

local function ball_holder_in_radius(lp_pos, lp_name, radius)
    local ok, players = pcall(function() return game.GetService("Players"):GetChildren() end)
    if not ok then return false end
    local r2 = radius * radius
    for _, p in ipairs(players) do
        if p.Name == lp_name then goto continue end
        local char = game.Workspace:FindFirstChild(p.Name)
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local ok2, pos = pcall(function() return hrp.Position end)
                if ok2 and pos then
                    local dx = pos.X - lp_pos.X
                    local dz = pos.Z - lp_pos.Z
                    if dx*dx + dz*dz <= r2 and char:FindFirstChild("Basketball") then
                        return true
                    end
                end
            end
        end
        ::continue::
    end
    return false
end

local as_last_t    = 0
local AS_COOLDOWN  = 600
local as_key_held  = false
local as_release_t = 0

local function as_tick()
    local now = utility.GetTickCount()
    if as_key_held and now >= as_release_t then
        keyboard.Release("r")
        as_key_held = false
    end
end

cheat.register("shutdown", function()
    if as_key_held then keyboard.Release("r") end
end)

local as_zone_center = nil

cheat.register("onUpdate", function()
    as_tick()
    as_zone_center = nil

    if not ui.getValue(as_enable) then return end

    local hk_bound  = ui.getHotkey(tab, as_con, "Steal Key")
    local hk_active = (not hk_bound or hk_bound.key == 0) or ui.getValue(as_hotkey)
    if not hk_active then return end

    local lp = entity.GetLocalPlayer()
    if not lp then return end
    local lp_pos = lp:GetBonePosition("HumanoidRootPart")
    if not lp_pos then return end

    as_zone_center = lp_pos

    local radius = ui.getValue(as_radius)
    if not ball_holder_in_radius(lp_pos, lp.Name, radius) then return end

    local now = utility.GetTickCount()
    if now - as_last_t < AS_COOLDOWN then return end
    if as_key_held then return end
    as_last_t = now

    local lo   = ui.getValue(as_hold_min)
    local hi   = math.max(ui.getValue(as_hold_max), lo)
    keyboard.Press("r")
    as_key_held  = true
    as_release_t = now + math.random(lo, hi)
end)

cheat.register("onPaint", function()
    if not ui.getValue(as_show) or not as_zone_center then return end
    local c = ui.getValue(as_col)
    if not c then return end
    local pts = circle_points(as_zone_center, ui.getValue(as_radius))
    if #pts >= 2 then
        draw.Polyline(pts, Color3.fromRGB(c.r, c.g, c.b), #pts == SEGS, 1.5, c.a)
    end
end)

-- ============================================================
-- Auto Block
-- ============================================================

local ab_con = "Auto Block"
ui.newContainer(tab, ab_con, "Auto Block", { autosize = true })

local ab_enable   = ui.newCheckbox(tab, ab_con, "Enable Auto Block")
local ab_hotkey   = ui.newHotkey(tab, ab_con, "Block Key", true)
local ab_show     = ui.newCheckbox(tab, ab_con, "Show Zone")
local ab_col      = ui.newColorpicker(tab, ab_con, "Zone Color", { r = 80, g = 180, b = 255, a = 180 }, true)
local ab_radius   = ui.newSliderFloat(tab, ab_con, "Block Radius",     1, 15)
local ab_windup   = ui.newSliderFloat(tab, ab_con, "Wind-up Threshold", 0, 5)
local ab_hold_min = ui.newSliderInt(tab,   ab_con, "Hold Min (ms)",    50, 300)
local ab_hold_max = ui.newSliderInt(tab,   ab_con, "Hold Max (ms)",    50, 300)

ui.setValue(tab, ab_con, "Block Radius",      7)
ui.setValue(tab, ab_con, "Wind-up Threshold", 1.5)
ui.setValue(tab, ab_con, "Hold Min (ms)",    80)
ui.setValue(tab, ab_con, "Hold Max (ms)",   160)

ui.SetVisibility(tab, ab_con, "Block Key",           false)
ui.SetVisibility(tab, ab_con, "Show Zone",           false)
ui.SetVisibility(tab, ab_con, "Zone Color",          false)
ui.SetVisibility(tab, ab_con, "Block Radius",        false)
ui.SetVisibility(tab, ab_con, "Wind-up Threshold",   false)
ui.SetVisibility(tab, ab_con, "Hold Min (ms)",       false)
ui.SetVisibility(tab, ab_con, "Hold Max (ms)",       false)

cheat.register("onUpdate", function()
    local on      = ui.getValue(tab, ab_con, "Enable Auto Block")
    local show_on = on and ui.getValue(tab, ab_con, "Show Zone")
    ui.SetVisibility(tab, ab_con, "Block Key",          on)
    ui.SetVisibility(tab, ab_con, "Show Zone",          on)
    ui.SetVisibility(tab, ab_con, "Zone Color",         show_on)
    ui.SetVisibility(tab, ab_con, "Block Radius",       on)
    ui.SetVisibility(tab, ab_con, "Wind-up Threshold",  on)
    ui.SetVisibility(tab, ab_con, "Hold Min (ms)",      on)
    ui.SetVisibility(tab, ab_con, "Hold Max (ms)",      on)
end)

local ab_last_t       = 0
local AB_COOLDOWN     = 400
local ab_key_held     = false
local ab_release_t    = 0
local ab_zone_center  = nil

local function ab_tick()
    local now = utility.GetTickCount()
    if ab_key_held and now >= ab_release_t then
        keyboard.Release("Space")
        ab_key_held = false
    end
end

cheat.register("shutdown", function()
    if ab_key_held then keyboard.Release("Space") end
end)

cheat.register("onUpdate", function()
    ab_tick()
    ab_zone_center = nil

    if not ui.getValue(ab_enable) then return end

    if not ui.getValue(ab_hotkey) then return end

    local lp = entity.GetLocalPlayer()
    if not lp then return end
    local lp_pos = lp:GetBonePosition("HumanoidRootPart")
    if not lp_pos then return end

    ab_zone_center = lp_pos

    local radius = ui.getValue(ab_radius)
    local r2     = radius * radius

    local ok, players = pcall(function() return game.GetService("Players"):GetChildren() end)
    if not ok then return end

    for _, p in ipairs(players) do
        if p.Name == lp.Name then goto continue end
        local char = game.Workspace:FindFirstChild(p.Name)
        if not char then goto continue end
        local ball   = char:FindFirstChild("Basketball")
        if not ball   then goto continue end
        local attach = ball:FindFirstChild("Attach")
        local hrp    = char:FindFirstChild("HumanoidRootPart")
        if not attach or not hrp then goto continue end
        local ok2, pos = pcall(function() return hrp.Position end)
        if not ok2 or not pos then goto continue end
        local dx = pos.X - lp_pos.X
        local dz = pos.Z - lp_pos.Z
        if dx*dx + dz*dz > r2 then goto continue end
        local ok3, delta = pcall(function() return attach.Position.Y - pos.Y end)
        if not ok3 or delta < ui.getValue(ab_windup) then goto continue end
        -- wind-up detected: ball is raised 1.5+ units above HRP
        if ab_key_held then return end
        local now = utility.GetTickCount()
        if now - ab_last_t < AB_COOLDOWN then return end
        ab_last_t = now
        local lo = ui.getValue(ab_hold_min)
        local hi = math.max(ui.getValue(ab_hold_max), lo)
        keyboard.Press("Space")
        ab_key_held  = true
        ab_release_t = now + math.random(lo, hi)
        ::continue::
    end
end)

cheat.register("onPaint", function()
    if not ui.getValue(ab_show) or not ab_zone_center then return end
    local c = ui.getValue(ab_col)
    if not c then return end
    local pts = circle_points(ab_zone_center, ui.getValue(ab_radius))
    if #pts >= 2 then
        draw.Polyline(pts, Color3.fromRGB(c.r, c.g, c.b), #pts == SEGS, 1.5, c.a)
    end
end)

-- ============================================================
-- Config
-- ============================================================

local cfg_con = "Config"
ui.newContainer(tab, cfg_con, "Config", { autosize = true })
ui.NewButton(tab, cfg_con, "Save Config",   function() config_save() end)
ui.NewButton(tab, cfg_con, "Load Config",   function() config_load() end)
ui.NewButton(tab, cfg_con, "Delete Config", function() file.delete("bl_config.lua") end)

local CONFIG_FILE = "bl_config.lua"

local SAVE_WIDGETS = {
    {ps_con, "Enable Perfect Shot", "val"},
    {ps_con, "Perfect Shot Key",    "hk"},
    {ps_con, "Hold Duration (ms)",  "val"},
    {ps_con, "Perfect Chance",      "val"},
    {ps_con, "Variance (ms)",       "val"},
    {as_con, "Enable Auto Steal",   "val"},
    {as_con, "Steal Key",           "hk"},
    {as_con, "Show Zone",           "val"},
    {as_con, "Zone Color",          "val"},
    {as_con, "Steal Radius",        "val"},
    {as_con, "Hold Min (ms)",       "val"},
    {as_con, "Hold Max (ms)",       "val"},
    {ab_con, "Enable Auto Block",   "val"},
    {ab_con, "Block Key",           "hk"},
    {ab_con, "Show Zone",           "val"},
    {ab_con, "Zone Color",          "val"},
    {ab_con, "Block Radius",        "val"},
    {ab_con, "Wind-up Threshold",   "val"},
    {ab_con, "Hold Min (ms)",       "val"},
    {ab_con, "Hold Max (ms)",       "val"},
}

local function ser(v)
    local t = type(v)
    if t == "boolean" then return v and "true" or "false"
    elseif t == "number" then return string.format("%.6g", v)
    elseif t == "table" then
        local parts = {}
        for k, val in pairs(v) do
            parts[#parts + 1] = string.format("[%q]=%s", tostring(k), ser(val))
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
end

config_save = function()
    local lines = {"return {"}
    for _, w in ipairs(SAVE_WIDGETS) do
        local container, label, wtype = w[1], w[2], w[3]
        local val
        if wtype == "hk" then
            local hk = ui.getHotkey(tab, container, label)
            val = hk and hk.key or 0
        else
            val = ui.getValue(tab, container, label)
        end
        lines[#lines + 1] = string.format("  [%q]=%s,", container .. "|" .. label, ser(val))
    end
    lines[#lines + 1] = "}"
    file.write(CONFIG_FILE, table.concat(lines, "\n"))
end

config_load = function()
    local src = file.read(CONFIG_FILE)
    if not src then return end
    local fn = loadstring(src)
    if not fn then return end
    local ok, data = pcall(fn)
    if not ok or type(data) ~= "table" then return end
    for _, w in ipairs(SAVE_WIDGETS) do
        local container, label = w[1], w[2]
        local val = data[container .. "|" .. label]
        if val ~= nil then
            pcall(function() ui.setValue(tab, container, label, val) end)
        end
    end
end

config_load()

print("Made By Aoruen & Mixer :3")
