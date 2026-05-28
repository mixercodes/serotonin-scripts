local TAB         = "LocalHUD"
local SETS        = "Settings"
local CONF        = "Config"
local FONTS       = {"Tahoma", "Verdana", "ConsolasBold", "SmallestPixel"}
local BAR_W       = 2
local CONFIG_FILE = "lhud_config.lua"

local DEFAULTS = {
    ["Enable"]            = true,
    ["Box Color"]         = {r=255, g=255, b=255, a=255},
    ["Box Outline"]       = true,
    ["Box Outline Color"] = {r=0,   g=0,   b=0,   a=200},
    ["Box Fill"]          = false,
    ["Box Fill Color"]    = {r=255, g=255, b=255, a=30},
    ["Health Bar"]        = true,
    ["HP High Color"]     = {r=0,   g=220, b=80,  a=255},
    ["HP Low Color"]      = {r=255, g=50,  b=50,  a=255},
    ["HP Bar Outline"]    = true,
    ["HP Outline Color"]  = {r=0,   g=0,   b=0,   a=200},
    ["HP Text"]           = false,
    ["HP Text X"]         = 0,
    ["HP Text Y"]         = 0,
    ["Mouse HP"]          = false,
    ["Mouse HP X"]        = 0,
    ["Mouse HP Y"]        = 18,
    ["Font"]              = 0,
}

local WIDGETS = {
    "Enable", "Box Color", "Box Outline", "Box Outline Color",
    "Box Fill", "Box Fill Color",
    "Health Bar", "HP High Color", "HP Low Color",
    "HP Bar Outline", "HP Outline Color",
    "HP Text", "HP Text X", "HP Text Y",
    "Mouse HP", "Mouse HP X", "Mouse HP Y",
    "Font",
}

local function ser(v)
    local t = type(v)
    if t == "boolean" then return v and "true" or "false"
    elseif t == "number" then return tostring(v)
    elseif t == "table" then
        return string.format("{r=%d,g=%d,b=%d,a=%d}",
            v.r or 255, v.g or 255, v.b or 255, v.a or 255)
    end
    return "nil"
end

local function apply_defaults()
    for label, val in pairs(DEFAULTS) do
        pcall(function() ui.setValue(TAB, SETS, label, val) end)
    end
end

local function config_save()
    local lines = {"return {"}
    for _, label in ipairs(WIDGETS) do
        local val = ui.getValue(TAB, SETS, label)
        lines[#lines + 1] = string.format("  [%q]=%s,", label, ser(val))
    end
    lines[#lines + 1] = "}"
    file.write(CONFIG_FILE, table.concat(lines, "\n"))
end

local function config_load()
    local src = file.read(CONFIG_FILE)
    if not src then return end
    local fn = loadstring(src)
    if not fn then return end
    local ok, data = pcall(fn)
    if not ok or type(data) ~= "table" then return end
    for _, label in ipairs(WIDGETS) do
        local val = data[label]
        if val ~= nil then
            pcall(function() ui.setValue(TAB, SETS, label, val) end)
        end
    end
end

-- UI
ui.NewTab(TAB, "Local HUD")
ui.NewContainer(TAB, SETS, "Settings", {autosize = true})
ui.NewContainer(TAB, CONF, "Config",   {autosize = true, next = true})

ui.NewCheckbox   (TAB, SETS, "Enable")
ui.NewColorpicker(TAB, SETS, "Box Color",         DEFAULTS["Box Color"],         true)

ui.NewCheckbox   (TAB, SETS, "Box Outline")
ui.NewColorpicker(TAB, SETS, "Box Outline Color", DEFAULTS["Box Outline Color"], true)

ui.NewCheckbox   (TAB, SETS, "Box Fill")
ui.NewColorpicker(TAB, SETS, "Box Fill Color",    DEFAULTS["Box Fill Color"],    true)

ui.NewCheckbox   (TAB, SETS, "Health Bar")
ui.NewColorpicker(TAB, SETS, "HP High Color",     DEFAULTS["HP High Color"],     true)
ui.NewColorpicker(TAB, SETS, "HP Low Color",      DEFAULTS["HP Low Color"],      true)

ui.NewCheckbox   (TAB, SETS, "HP Bar Outline")
ui.NewColorpicker(TAB, SETS, "HP Outline Color",  DEFAULTS["HP Outline Color"],  true)

ui.NewCheckbox   (TAB, SETS, "HP Text")
ui.NewSliderInt  (TAB, SETS, "HP Text X",  -50,  50)
ui.NewSliderInt  (TAB, SETS, "HP Text Y",  -50,  50)

ui.NewCheckbox   (TAB, SETS, "Mouse HP")
ui.NewSliderInt  (TAB, SETS, "Mouse HP X", -100, 100)
ui.NewSliderInt  (TAB, SETS, "Mouse HP Y", -50,  100)

ui.NewDropdown   (TAB, SETS, "Font", FONTS)

ui.NewButton(TAB, CONF, "Save Config",  config_save)
ui.NewButton(TAB, CONF, "Load Config",  config_load)
ui.NewButton(TAB, CONF, "Reset Config", apply_defaults)

apply_defaults()
config_load()

-- Logic
local function lerp_color(high_c, low_c, t)
    return Color3.fromRGB(
        math.floor(high_c.r + (low_c.r - high_c.r) * t + 0.5),
        math.floor(high_c.g + (low_c.g - high_c.g) * t + 0.5),
        math.floor(high_c.b + (low_c.b - high_c.b) * t + 0.5)
    )
end

local function get_box(lp)
    local bb = lp.BoundingBox
    if bb and bb.w > 0 then return bb end

    local head = lp:GetBonePosition("Head")
    local hrp  = lp:GetBonePosition("HumanoidRootPart")
    if not head or not hrp then return nil end

    local hx, hy, hon = utility.WorldToScreen(head)
    local fx, fy, fon = utility.WorldToScreen(Vector3.new(hrp.X, hrp.Y - 2.8, hrp.Z))
    if not hon or not fon then return nil end

    local bh = fy - hy
    if bh < 4 then return nil end
    local bw = bh * 0.45
    return { x = hx - bw * 0.5, y = hy - bh * 0.08, w = bw, h = bh * 1.08 }
end

cheat.register("onUpdate", function()
    local hp_text  = ui.getValue(TAB, SETS, "HP Text")
    local mouse_hp = ui.getValue(TAB, SETS, "Mouse HP")
    ui.SetVisibility(TAB, SETS, "HP Text X",  hp_text)
    ui.SetVisibility(TAB, SETS, "HP Text Y",  hp_text)
    ui.SetVisibility(TAB, SETS, "Mouse HP X", mouse_hp)
    ui.SetVisibility(TAB, SETS, "Mouse HP Y", mouse_hp)
end)

cheat.register("onPaint", function()
    if not ui.getValue(TAB, SETS, "Enable") then return end

    local lp = entity.GetLocalPlayer()
    if not lp or not lp.IsAlive then return end

    local max_hp = lp.MaxHealth
    if max_hp <= 0 then return end

    local health = math.max(0, lp.Health)
    local ratio  = math.max(0, math.min(1, health / max_hp))

    local hp_high_c = ui.getValue(TAB, SETS, "HP High Color")
    local hp_low_c  = ui.getValue(TAB, SETS, "HP Low Color")
    local hp_col    = lerp_color(hp_high_c, hp_low_c, 1 - ratio)

    local font = FONTS[(ui.getValue(TAB, SETS, "Font") or 0) + 1] or "Tahoma"

    local bb = get_box(lp)
    if not bb then return end

    local bx, by, bw, bh = bb.x, bb.y, bb.w, bb.h

    -- Box fill (drawn first, behind border)
    if ui.getValue(TAB, SETS, "Box Fill") then
        local fc = ui.getValue(TAB, SETS, "Box Fill Color")
        draw.RectFilled(bx, by, bw, bh, Color3.fromRGB(fc.r, fc.g, fc.b), 0, fc.a)
    end

    -- Bounding box
    local box_c = ui.getValue(TAB, SETS, "Box Color")
    if ui.getValue(TAB, SETS, "Box Outline") then
        local oc = ui.getValue(TAB, SETS, "Box Outline Color")
        draw.Rect(bx, by, bw, bh, Color3.fromRGB(oc.r, oc.g, oc.b), 3, 0, oc.a)
    end
    draw.Rect(bx, by, bw, bh, Color3.fromRGB(box_c.r, box_c.g, box_c.b), 1, 0, box_c.a)

    -- Health bar: left of box, fills bottom-to-top
    if ui.getValue(TAB, SETS, "Health Bar") then
        local bar_x  = bx - BAR_W - 2
        local bar_y  = by
        local bar_h  = bh
        local fill_h = math.max(1, math.floor(bar_h * ratio))

        if ui.getValue(TAB, SETS, "HP Bar Outline") then
            local oc = ui.getValue(TAB, SETS, "HP Outline Color")
            draw.RectFilled(bar_x - 1, bar_y - 1, BAR_W + 2, bar_h + 2,
                            Color3.fromRGB(oc.r, oc.g, oc.b), 0, oc.a)
        end
        draw.RectFilled(bar_x, bar_y,                   BAR_W, bar_h,   Color3.fromRGB(20, 20, 20), 0, 200)
        draw.RectFilled(bar_x, bar_y + bar_h - fill_h,  BAR_W, fill_h,  hp_col, 0, 255)

        if ui.getValue(TAB, SETS, "HP Text") then
            local text   = string.format("%d", math.floor(health))
            local tw, th = draw.GetTextSize(text, font)
            local ox     = ui.getValue(TAB, SETS, "HP Text X") or 0
            local oy     = ui.getValue(TAB, SETS, "HP Text Y") or 0
            draw.TextOutlined(text, bar_x - tw - 2 + ox, bar_y - th - 1 + oy, hp_col, font, 255)
        end
    end

    -- Mouse HP
    if ui.getValue(TAB, SETS, "Mouse HP") then
        local mp     = utility.GetMousePos()
        local text   = string.format("%d / %d", math.floor(health), math.floor(max_hp))
        local tw, th = draw.GetTextSize(text, font)
        local ox     = ui.getValue(TAB, SETS, "Mouse HP X") or 0
        local oy     = ui.getValue(TAB, SETS, "Mouse HP Y") or 18
        draw.TextOutlined(text, mp[1] - tw * 0.5 + ox, mp[2] + oy, hp_col, font, 255)
    end
end)
