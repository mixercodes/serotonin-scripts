-- blue_lock_rivals.lua (merged with ball_manipulation)

local TP_MODES     = {"Ball to Player (pull)", "Ball Control (glue)", "Player to Ball"}
local TRAVEL_MODES = {"Instant", "Tween"}
local VIS_FONTS    = {"SmallestPixel", "Verdana", "ConsolasBold", "Tahoma"}

local TAB  = "blr_tab"
local MAN  = "blr_man"
local FEAT = "blr_feat"
local VIS  = "blr_vis"

local OFF_UP     = 2.5
local pi         = math.pi
local pi2        = pi * 2
local sin, cos   = math.sin, math.cos
local CONFIG_FILE = "blr_config.lua"

local config_save, config_load  -- forward declarations for button callbacks

ui.newTab(TAB, "BL:R")

-- [Ball Manip]
ui.NewContainer(TAB, MAN, "Ball Manip", { autosize = true })
ui.NewCheckbox(TAB, MAN, "Orbit Enabled")
ui.newHotkey(TAB, MAN, "Orbit Key", true)
ui.newSliderFloat(TAB, MAN, "Radius",       0.5, 30.0)
ui.newSliderFloat(TAB, MAN, "Height",      -5.0, 100.0)
ui.newSliderFloat(TAB, MAN, "Speed (rps)",  0.1, 10.0)
ui.NewCheckbox(TAB, MAN, "BC Enabled")
ui.newHotkey(TAB, MAN, "BC Key", true)
ui.newSliderFloat(TAB, MAN, "Move Speed",   1.0, 100.0)
ui.NewCheckbox(TAB, MAN, "Freeze Player")
ui.NewCheckbox(TAB, MAN, "Auto Dribble")
ui.newHotkey(TAB, MAN, "Dribble Key", true)
ui.newSliderFloat(TAB, MAN, "Dribble Radius", 2.0, 15.0)
ui.NewCheckbox(TAB, MAN, "Show Radius")
ui.NewCheckbox(TAB, MAN, "Linger")
ui.newSliderFloat(TAB, MAN, "Linger Radius",   2.0, 15.0)
ui.NewSliderInt(TAB, MAN,   "Linger Time (ms)", 50, 500)

-- [Ball Features]
ui.NewContainer(TAB, FEAT, "Ball Features", { autosize = true, next = true })
ui.NewCheckbox(TAB, FEAT, "Speed Enabled")
ui.newHotkey(TAB, FEAT, "Speed Key", true)
ui.newSliderFloat(TAB, FEAT, "Speed Multiplier", 1.0, 10.0)
ui.newSliderFloat(TAB, FEAT, "Smoothing",         0.0, 1.0)
ui.NewCheckbox(TAB, FEAT, "Enable Speed Cap")
ui.newSliderFloat(TAB, FEAT, "Max Speed Cap",    10.0, 500.0)
ui.NewCheckbox(TAB, FEAT, "Ball Arc")
ui.newHotkey(TAB, FEAT, "Arc Key", true)
ui.newSliderFloat(TAB, FEAT, "Arc Level",         0.0, 1.0)
ui.NewCheckbox(TAB, FEAT, "Teleport Enabled")
ui.newHotkey(TAB, FEAT, "Teleport Key", true)
ui.newDropdown(TAB, FEAT, "TP Mode",     TP_MODES)
ui.newDropdown(TAB, FEAT, "Travel Mode", TRAVEL_MODES)
ui.newSliderFloat(TAB, FEAT, "Tween Time (sec)",  0.05, 1.0)
ui.newSliderFloat(TAB, FEAT, "Return Time (sec)", 0.05, 1.0)
ui.newSliderFloat(TAB, FEAT, "Dwell Time (sec)",  0.0,  5.0)
ui.newSliderFloat(TAB, FEAT, "Steal Dwell (sec)", 0.1,  5.0)
ui.NewCheckbox(TAB, FEAT, "Retry on Miss")
ui.NewSliderInt(TAB, FEAT, "Max Retries", 1, 10)
ui.NewCheckbox(TAB, FEAT, "Preserve Momentum")
ui.NewCheckbox(TAB, FEAT, "Auto Goal")
ui.newHotkey(TAB, FEAT, "Auto Goal Key", true)
ui.newDropdown(TAB, FEAT, "Goal Target", {"Auto (enemy)", "Home", "Away"})

-- [Visuals & Config]
ui.NewContainer(TAB, VIS, "Visuals", { autosize = true, next = true })
ui.newDropdown(TAB, VIS, "Font", VIS_FONTS)
ui.NewCheckbox(TAB, VIS, "Info Display")
ui.NewCheckbox(TAB, VIS, "Ball ESP")
ui.NewCheckbox(TAB, VIS, "Box")
ui.NewColorpicker(TAB, VIS, "Ball Color",      {r=255, g=255, b=255, a=255}, true)
ui.NewCheckbox(TAB, VIS, "Ball Fill")
ui.NewColorpicker(TAB, VIS, "Ball Fill Color", {r=255, g=255, b=255, a=60},  true)
ui.NewCheckbox(TAB, VIS, "Ball ESP Text")
ui.NewCheckbox(TAB, VIS, "Shape")
ui.NewColorpicker(TAB, VIS, "Shape Color", {r=0, g=120, b=255, a=255}, true)
ui.NewCheckbox(TAB, VIS, "Shape Fill")
ui.NewColorpicker(TAB, VIS, "Shape Fill Color", {r=0, g=120, b=255, a=50}, true)
ui.newDropdown(TAB, VIS, "Shape Type", {"Star of David", "Hexagon", "Circle"})
ui.newSliderFloat(TAB, VIS, "Shape Size",      10.0, 100.0)
ui.NewCheckbox(TAB, VIS, "Shape Spin")
ui.newSliderFloat(TAB, VIS, "Spin Speed",       0.1, 10.0)
ui.NewCheckbox(TAB, VIS, "Shape Breathe")
ui.newSliderFloat(TAB, VIS, "Breathe Amount",  0.05, 0.5)
ui.newSliderFloat(TAB, VIS, "Shape Thickness", 0.5,  6.0)
ui.NewCheckbox(TAB, VIS, "Goal ESP")
ui.NewColorpicker(TAB, VIS, "Home Color",      {r=0, g=180, b=255, a=255},   true)
ui.NewColorpicker(TAB, VIS, "Away Color",      {r=255, g=80, b=80, a=255},   true)
ui.NewCheckbox(TAB, VIS, "Goal ESP Text")
ui.NewCheckbox(TAB, VIS, "Goal Fill")
ui.NewColorpicker(TAB, VIS, "Home Fill Color", {r=0, g=180, b=255, a=40},    true)
ui.NewColorpicker(TAB, VIS, "Away Fill Color", {r=255, g=80, b=80, a=40},    true)
ui.NewCheckbox(TAB, VIS, "Ball Indicator")
ui.NewColorpicker(TAB, VIS, "Indicator Color", {r=29, g=123, b=188, a=164}, true)
ui.newSliderFloat(TAB, VIS, "Indicator Radius", 20.0, 200.0)
ui.NewCheckbox(TAB, VIS, "Velocity Arrow")
ui.NewColorpicker(TAB, VIS, "Arrow Color", {r=255, g=255, b=255, a=255}, true)
ui.newSliderFloat(TAB, VIS, "Arrow Scale", 0.5, 5.0)
ui.NewCheckbox(TAB, VIS, "Snap Line")
ui.NewColorpicker(TAB, VIS, "Snap Color", {r=255, g=255, b=255, a=150}, true)
ui.NewCheckbox(TAB, VIS, "Ball Trail")
ui.NewColorpicker(TAB, VIS, "Trail Color", {r=255, g=255, b=255, a=200}, true)
ui.NewSliderInt(TAB, VIS, "Trail Length", 5, 60)
ui.NewMultiselect(TAB, VIS, "ESP Outlines", {"Box", "Shape", "Goal", "Indicator", "Arrow", "Snap", "Trail"})
ui.NewButton(TAB, VIS, "Save Config",   function() config_save() end)
ui.NewButton(TAB, VIS, "Load Config",   function() config_load() end)
ui.NewButton(TAB, VIS, "Delete Config", function() file.delete(CONFIG_FILE) end)

-- [Defaults]
ui.setValue(TAB, MAN, "Orbit Enabled", false)
ui.setValue(TAB, MAN, "Radius",        3.5)
ui.setValue(TAB, MAN, "Height",        10.0)
ui.setValue(TAB, MAN, "Speed (rps)",   0.5)
ui.setValue(TAB, MAN, "BC Enabled",    false)
ui.setValue(TAB, MAN, "Move Speed",    15.0)
ui.setValue(TAB, MAN, "Freeze Player",   true)
ui.setValue(TAB, MAN, "Auto Dribble",   false)
ui.setValue(TAB, MAN, "Dribble Radius", 10.50)
ui.setValue(TAB, MAN, "Show Radius",     true)
ui.setValue(TAB, MAN, "Linger",          true)
ui.setValue(TAB, MAN, "Linger Radius",   11.50)
ui.setValue(TAB, MAN, "Linger Time (ms)", 500)

ui.setValue(TAB, FEAT, "Speed Enabled",     false)
ui.setValue(TAB, FEAT, "Speed Multiplier",  2.0)
ui.setValue(TAB, FEAT, "Smoothing",         0.0)
ui.setValue(TAB, FEAT, "Enable Speed Cap",  false)
ui.setValue(TAB, FEAT, "Max Speed Cap",     150.0)
ui.setValue(TAB, FEAT, "Ball Arc",          false)
ui.setValue(TAB, FEAT, "Arc Level",         0.5)
ui.setValue(TAB, FEAT, "Teleport Enabled",  false)
ui.setValue(TAB, FEAT, "TP Mode",           2)
ui.setValue(TAB, FEAT, "Travel Mode",       1)
ui.setValue(TAB, FEAT, "Tween Time (sec)",  0.05)
ui.setValue(TAB, FEAT, "Return Time (sec)", 0.05)
ui.setValue(TAB, FEAT, "Dwell Time (sec)",  0.3)
ui.setValue(TAB, FEAT, "Steal Dwell (sec)", 0.6)
ui.setValue(TAB, FEAT, "Retry on Miss",     false)
ui.setValue(TAB, FEAT, "Max Retries",       3)
ui.setValue(TAB, FEAT, "Preserve Momentum", true)
ui.setValue(TAB, FEAT, "Auto Goal",         false)
ui.setValue(TAB, FEAT, "Goal Target",       0)

ui.setValue(TAB, VIS, "Font",          1)
ui.setValue(TAB, VIS, "Info Display",  true)
ui.setValue(TAB, VIS, "Ball ESP",      false)
ui.setValue(TAB, VIS, "Box",           false)
ui.setValue(TAB, VIS, "Ball Fill",     false)
ui.setValue(TAB, VIS, "Ball ESP Text", true)
ui.setValue(TAB, VIS, "Shape",         false)
ui.setValue(TAB, VIS, "Shape Fill",    false)
ui.setValue(TAB, VIS, "Shape Type",    0)
ui.setValue(TAB, VIS, "Goal ESP",      false)
ui.setValue(TAB, VIS, "Goal ESP Text", true)
ui.setValue(TAB, VIS, "Goal Fill",     false)
ui.setValue(TAB, VIS, "Shape Size",    30.0)
ui.setValue(TAB, VIS, "Shape Spin",    false)
ui.setValue(TAB, VIS, "Spin Speed",    1.0)
ui.setValue(TAB, VIS, "Shape Breathe",    false)
ui.setValue(TAB, VIS, "Breathe Amount",   0.2)
ui.setValue(TAB, VIS, "Shape Thickness",  1.5)
ui.setValue(TAB, VIS, "Shape Fill",       false)
ui.setValue(TAB, VIS, "Ball Indicator",    false)
ui.setValue(TAB, VIS, "Indicator Radius",  60.0)
ui.setValue(TAB, VIS, "Velocity Arrow",   false)
ui.setValue(TAB, VIS, "Arrow Scale",      1.0)
ui.setValue(TAB, VIS, "Snap Line",        false)
ui.setValue(TAB, VIS, "Ball Trail",       false)
ui.setValue(TAB, VIS, "Trail Length",     20)
ui.setValue(TAB, VIS, "ESP Outlines",     {true,true,true,true,true,true,true})

-- [Shared state]

local free_ball      = nil
local held_ball      = nil
local world_ball     = nil
local holder_char    = nil
local local_char     = nil
local local_has_ball = false
local prev_vel    = Vector3.new(0, 0, 0)
local ball_status = "---"
local goal_boxes  = {}

local COLOR_WHITE = Color3.new(1, 1, 1)
local COLOR_BLUE  = Color3.fromHex("#3E79A7")
local COLOR_BLACK = Color3.new(0, 0, 0)
local _screen_buf = {}

local orbit_active = false
local orbit_angle  = 0.0
local orbit_last   = utility.GetTickCount()

local bc_active = false
local bc_pos_x, bc_pos_y, bc_pos_z = 0, 0, 0
local frozen_x, frozen_y, frozen_z = 0, 0, 0

local cam_fwx, cam_fwz = 0, 1
local cam_rx,  cam_rz  = 1, 0

local shape_angle     = 0.0
local shape_last      = utility.GetTickCount()
local shape_breathe_t = 0.0

local trail_positions = {}

local hk_prev = {}

local info_speed     = 0
local info_dist      = "--"
local info_tp_status = "Teleport disabled"

local flat_lock_y  = nil
local speed_active = false
local arc_active   = false

local glue_active          = false
local auto_goal_active     = false
local auto_dribble_active  = false
local dribble_q_down       = false
local dribble_q_time       = 0
local dribble_last_q       = 0
local dribble_enemy_near   = false
local dribble_enemy_slide  = false
local dribble_linger_near  = false
local dribble_linger_slide = false
local dribble_pos_history  = {}
local ptb_phase            = "idle"
local ptb_return_pos       = nil
local ptb_dwell_start      = 0
local ptb_retries          = 0
local ptb_start_time       = 0
local tween_to_phase       = "at_ball"
local tween_start_pos      = nil
local tween_start_time     = 0
local ret_tween_start      = nil
local ret_tween_start_time = 0
local ret_use_tween        = false

local PTB_TIMEOUT = 3.0

-- [Helpers]

local function hotkey_clicked(label, container)
    local key  = container .. "|" .. label
    local now  = ui.getValue(TAB, container, label)
    local prev = hk_prev[key] or false
    hk_prev[key] = now
    local hk   = ui.getHotkey(TAB, container, label)
    local mode = hk and hk.mode or 0
    if mode == 0 then
        return now and not prev
    else
        return now ~= prev
    end
end

local function hotkey_is_hold(label, container)
    local hk = ui.getHotkey(TAB, container, label)
    return (hk and hk.mode or 0) == 0
end

local function now_sec()
    return utility.GetTickCount() / 1000
end

local function front_target(hrp)
    return hrp.Position + Vector3.new(0, OFF_UP, 0)
end

local function picker_to_color3(t)
    if not t then return COLOR_WHITE end
    return Color3.fromRGB(t.r or 255, t.g or 255, t.b or 255)
end

local function get_ball_pos()
    if local_has_ball then return nil end
    if held_ball and held_ball.Parent then
        local ok, p = pcall(function() return held_ball.Position end)
        if ok and p then return p end
    end
    if world_ball and world_ball.Parent then
        local ok, p = pcall(function() return world_ball.Position end)
        if ok and p then return p end
    end
    if free_ball and free_ball.Parent then
        local ok, p = pcall(function() return free_ball.Position end)
        if ok and p then return p end
    end
    return nil
end

-- [Camera axes for BC movement]

local function get_cam_axes()
    local cam_pos = game.CameraPosition
    if not cam_pos then return nil end

    local sw, _sh = cheat.GetWindowSize()
    local cx = sw * 0.5
    local R  = 200

    local de
    local ex, _, eok = utility.WorldToScreen(Vector3.new(cam_pos.X + R, cam_pos.Y, cam_pos.Z))
    if eok then
        de = ex - cx
    else
        local wx, _, wok = utility.WorldToScreen(Vector3.new(cam_pos.X - R, cam_pos.Y, cam_pos.Z))
        if wok then de = -(wx - cx) else return nil end
    end

    local dz
    local zx, _, zok = utility.WorldToScreen(Vector3.new(cam_pos.X, cam_pos.Y, cam_pos.Z + R))
    if zok then
        dz = zx - cx
    else
        local nx, _, nok = utility.WorldToScreen(Vector3.new(cam_pos.X, cam_pos.Y, cam_pos.Z - R))
        if nok then dz = -(nx - cx) else return nil end
    end

    local len = math.sqrt(de * de + dz * dz)
    if len < 0.5 then return nil end
    local rx = de / len
    local rz = dz / len
    return -rz, rx, rx, rz
end

-- [Ball / char refresh]

local function refresh_ball_refs()
    local ball_model = game.Workspace:FindFirstChild("Ball")
    free_ball  = ball_model and ball_model:FindFirstChild("RootPart") or nil
    world_ball = game.Workspace:FindFirstChild("Football")

    held_ball   = nil
    holder_char = nil
    local ok_pl, all_players = pcall(function() return entity.GetPlayers(false) end)
    if ok_pl and all_players then
        for _, p in ipairs(all_players) do
            local ok2, char, is_holding = pcall(function()
                local c    = game.Workspace:FindFirstChild(p.Name)
                local vals = c and c:FindFirstChild("Values")
                local hb   = vals and vals:FindFirstChild("HasBall")
                return c, hb and (hb.Value == true or hb.Value == 1)
            end)
            if ok2 and char and is_holding then
                held_ball   = char:FindFirstChild("Football")
                holder_char = char
                ball_status = p.Name .. " (held)"
                return
            end
        end
    end

    if world_ball then
        local ok, spd = pcall(function() return world_ball.Velocity.Magnitude end)
        ball_status = (ok and spd or 0) > 0.5 and "ball in motion" or "ball idle"
    elseif free_ball and free_ball.Parent then
        local ok, spd = pcall(function() return free_ball.Velocity.Magnitude end)
        ball_status = (ok and spd or 0) > 0.5 and "ball in motion" or "ball idle"
    else
        ball_status = "no ball"
    end
end

local function refresh_local_char()
    local lp   = game.LocalPlayer
    local name = lp and lp.Name
    local_char = name and game.Workspace:FindFirstChild(name) or nil
end

local function bc_init()
    local cam_pos = game.CameraPosition
    if not cam_pos then return end
    local lp  = entity.GetLocalPlayer()
    local hrp = lp and lp:GetBonePosition("HumanoidRootPart")
    if hrp then
        bc_pos_x = hrp.X
        bc_pos_y = hrp.Y + 10
        bc_pos_z = hrp.Z
        frozen_x, frozen_y, frozen_z = hrp.X, hrp.Y, hrp.Z
    else
        bc_pos_x = cam_pos.X
        bc_pos_y = cam_pos.Y + 10
        bc_pos_z = cam_pos.Z
    end
end

-- [Goal refs]

local function refresh_goal_refs()
    goal_boxes = {}
    local goals_folder = game.Workspace:FindFirstChild("Goals")
    if not goals_folder then return end
    for _, child in ipairs(goals_folder:GetChildren()) do
        if child.ClassName == "Part" or child.ClassName == "MeshPart" then
            table.insert(goal_boxes, {part = child, name = child.Name})
        elseif child.ClassName == "Model" then
            for _, cc in ipairs(child:GetChildren()) do
                if (cc.ClassName == "Part" or cc.ClassName == "MeshPart") and cc.Name == "GoalBox" then
                    table.insert(goal_boxes, {part = cc, name = child.Name})
                end
            end
        end
    end
end

-- [Config]

local SAVE_WIDGETS = {
    {MAN,  "Orbit Enabled",    "val"},
    {MAN,  "Orbit Key",        "hk"},
    {MAN,  "Radius",           "val"},
    {MAN,  "Height",           "val"},
    {MAN,  "Speed (rps)",      "val"},
    {MAN,  "BC Enabled",       "val"},
    {MAN,  "BC Key",           "hk"},
    {MAN,  "Move Speed",       "val"},
    {MAN,  "Freeze Player",    "val"},
    {MAN,  "Auto Dribble",    "val"},
    {MAN,  "Dribble Key",     "hk"},
    {MAN,  "Dribble Radius",  "val"},
    {MAN,  "Show Radius",      "val"},
    {MAN,  "Linger",          "val"},
    {MAN,  "Linger Radius",   "val"},
    {MAN,  "Linger Time (ms)","val"},
    {FEAT, "Speed Enabled",    "val"},
    {FEAT, "Speed Key",        "hk"},
    {FEAT, "Speed Multiplier", "val"},
    {FEAT, "Smoothing",        "val"},
    {FEAT, "Enable Speed Cap", "val"},
    {FEAT, "Max Speed Cap",    "val"},
    {FEAT, "Ball Arc",         "val"},
    {FEAT, "Arc Key",          "hk"},
    {FEAT, "Arc Level",        "val"},
    {FEAT, "Teleport Enabled", "val"},
    {FEAT, "Teleport Key",     "hk"},
    {FEAT, "TP Mode",          "val"},
    {FEAT, "Travel Mode",      "val"},
    {FEAT, "Tween Time (sec)", "val"},
    {FEAT, "Return Time (sec)","val"},
    {FEAT, "Dwell Time (sec)", "val"},
    {FEAT, "Steal Dwell (sec)","val"},
    {FEAT, "Retry on Miss",    "val"},
    {FEAT, "Max Retries",      "val"},
    {FEAT, "Preserve Momentum","val"},
    {FEAT, "Auto Goal",        "val"},
    {FEAT, "Auto Goal Key",    "hk"},
    {FEAT, "Goal Target",      "val"},
    {VIS,  "Font",             "val"},
    {VIS,  "Info Display",     "val"},
    {VIS,  "Ball ESP",         "val"},
    {VIS,  "Box",              "val"},
    {VIS,  "Ball Fill",        "val"},
    {VIS,  "Ball Fill Color",  "val"},
    {VIS,  "Ball Color",       "val"},
    {VIS,  "Ball ESP Text",    "val"},
    {VIS,  "Shape",            "val"},
    {VIS,  "Shape Fill",       "val"},
    {VIS,  "Shape Fill Color", "val"},
    {VIS,  "Shape Color",      "val"},
    {VIS,  "Shape Type",       "val"},
    {VIS,  "Goal ESP",         "val"},
    {VIS,  "Home Color",       "val"},
    {VIS,  "Away Color",       "val"},
    {VIS,  "Goal ESP Text",    "val"},
    {VIS,  "Goal Fill",        "val"},
    {VIS,  "Home Fill Color",  "val"},
    {VIS,  "Away Fill Color",  "val"},
    {VIS,  "Shape Size",       "val"},
    {VIS,  "Shape Spin",       "val"},
    {VIS,  "Spin Speed",       "val"},
    {VIS,  "Shape Breathe",    "val"},
    {VIS,  "Breathe Amount",   "val"},
    {VIS,  "Shape Thickness",  "val"},
    {VIS,  "Shape Fill",       "val"},
    {VIS,  "Shape Fill Color", "val"},
    {VIS,  "Ball Indicator",    "val"},
    {VIS,  "Indicator Color",  "val"},
    {VIS,  "Indicator Radius", "val"},
    {VIS,  "Velocity Arrow",   "val"},
    {VIS,  "Arrow Color",      "val"},
    {VIS,  "Arrow Scale",      "val"},
    {VIS,  "Snap Line",        "val"},
    {VIS,  "Snap Color",       "val"},
    {VIS,  "Ball Trail",       "val"},
    {VIS,  "Trail Color",      "val"},
    {VIS,  "Trail Length",     "val"},
    {VIS,  "ESP Outlines",    "val"},
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
            local hk = ui.getHotkey(TAB, container, label)
            val = hk and hk.key or 0
        else
            val = ui.getValue(TAB, container, label)
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
            pcall(function() ui.setValue(TAB, container, label, val) end)
        end
    end
end

config_load()  -- auto-load on startup

-- [Update: local possession (runs every ~5ms so it's ahead of the 33ms ball-ref refresh)]

cheat.register("onUpdate", function()
    local lp   = game.LocalPlayer
    local char = lp and game.Workspace:FindFirstChild(lp.Name)
    local vals = char and char:FindFirstChild("Values")
    local hb   = vals and vals:FindFirstChild("HasBall")
    local ok, v = pcall(function() return hb and (hb.Value == true or hb.Value == 1) end)
    local_has_ball = ok and v or false
end)

-- [Slow update: goal refs]

cheat.register("onSlowUpdate", refresh_goal_refs)

-- [Update: ball/char refresh]

local _last_refresh = 0
cheat.register("onUpdate", function()
    local t = utility.GetTickCount() / 1000
    if t - _last_refresh < 0.033 then return end
    _last_refresh = t
    refresh_ball_refs()
    refresh_local_char()
    if ui.getValue(TAB, VIS, "Ball Trail") and not local_has_ball then
        local bp = get_ball_pos()
        if bp then
            trail_positions[#trail_positions + 1] = bp
            if #trail_positions > 60 then table.remove(trail_positions, 1) end
        end
    elseif #trail_positions > 0 then
        trail_positions = {}
    end
end)

cheat.register("onUpdate", function()
    if held_ball  and not held_ball.Parent  then held_ball = nil; holder_char = nil end
    if free_ball  and not free_ball.Parent  then free_ball  = nil end
    if world_ball and not world_ball.Parent then world_ball = nil end
    if local_char and not local_char.Parent then local_char = nil end
end)

-- [Update: ball distance info]

cheat.register("onUpdate", function()
    local ball_pos = get_ball_pos()
    local hrp = local_char and local_char:FindFirstChild("HumanoidRootPart")
    if ball_pos and hrp then
        info_dist = string.format("%.1f studs", (ball_pos - hrp.Position).Magnitude)
    else
        info_dist = "--"
    end
end)

-- [Update: conditional visibility]

cheat.register("onUpdate", function()
    local tp_on   = ui.getValue(TAB, FEAT, "Teleport Enabled")
    local mode    = ui.getValue(TAB, FEAT, "TP Mode")
    local is_pull = mode == 0
    local is_ptb  = mode == 2
    local is_tween  = is_ptb and ui.getValue(TAB, FEAT, "Travel Mode") == 1
    local retry_on  = is_ptb and ui.getValue(TAB, FEAT, "Retry on Miss")
    local auto_g    = tp_on and ui.getValue(TAB, FEAT, "Auto Goal")

    local spd_on = ui.getValue(TAB, FEAT, "Speed Enabled")
    local cap_on = spd_on and ui.getValue(TAB, FEAT, "Enable Speed Cap")
    local arc_on = ui.getValue(TAB, FEAT, "Ball Arc")

    ui.SetVisibility(TAB, FEAT, "Speed Multiplier",  spd_on)
    ui.SetVisibility(TAB, FEAT, "Smoothing",          spd_on)
    ui.SetVisibility(TAB, FEAT, "Enable Speed Cap",   spd_on)
    ui.SetVisibility(TAB, FEAT, "Max Speed Cap",      cap_on)
    ui.SetVisibility(TAB, FEAT, "Arc Level",          arc_on)
    ui.SetVisibility(TAB, FEAT, "TP Mode",            tp_on)
    ui.SetVisibility(TAB, FEAT, "Travel Mode",        tp_on and is_ptb)
    ui.SetVisibility(TAB, FEAT, "Tween Time (sec)",   tp_on and is_tween)
    ui.SetVisibility(TAB, FEAT, "Return Time (sec)",  tp_on and is_tween)
    ui.SetVisibility(TAB, FEAT, "Dwell Time (sec)",   tp_on and is_ptb)
    ui.SetVisibility(TAB, FEAT, "Steal Dwell (sec)",  tp_on and is_ptb)
    ui.SetVisibility(TAB, FEAT, "Retry on Miss",      tp_on and is_ptb)
    ui.SetVisibility(TAB, FEAT, "Max Retries",        tp_on and is_ptb and retry_on)
    ui.SetVisibility(TAB, FEAT, "Preserve Momentum",  tp_on and is_pull)
    ui.SetVisibility(TAB, FEAT, "Auto Goal",          tp_on)
    ui.SetVisibility(TAB, FEAT, "Goal Target",        auto_g)

    local ball_esp  = ui.getValue(TAB, VIS, "Ball ESP")
    local box_on    = ball_esp and ui.getValue(TAB, VIS, "Box")
    local shape_on  = ball_esp and ui.getValue(TAB, VIS, "Shape")
    local spin_on   = shape_on and ui.getValue(TAB, VIS, "Shape Spin")
    local breathe_on = shape_on and ui.getValue(TAB, VIS, "Shape Breathe")
    local goal_esp  = ui.getValue(TAB, VIS, "Goal ESP")
    local goal_fill = goal_esp and ui.getValue(TAB, VIS, "Goal Fill")

    ui.SetVisibility(TAB, VIS, "Box",              ball_esp)
    ui.SetVisibility(TAB, VIS, "Ball Color",       ball_esp)
    ui.SetVisibility(TAB, VIS, "Ball Fill",        box_on)
    ui.SetVisibility(TAB, VIS, "Ball Fill Color",  box_on)
    ui.SetVisibility(TAB, VIS, "Ball ESP Text",    box_on)
    ui.SetVisibility(TAB, VIS, "Shape",            ball_esp)
    ui.SetVisibility(TAB, VIS, "Shape Color",      ball_esp)
    ui.SetVisibility(TAB, VIS, "Shape Fill",       shape_on)
    ui.SetVisibility(TAB, VIS, "Shape Fill Color", shape_on)
    ui.SetVisibility(TAB, VIS, "Shape Type",       shape_on)
    ui.SetVisibility(TAB, VIS, "Shape Size",       shape_on)
    ui.SetVisibility(TAB, VIS, "Shape Spin",       shape_on)
    ui.SetVisibility(TAB, VIS, "Spin Speed",       spin_on)
    ui.SetVisibility(TAB, VIS, "Shape Breathe",    shape_on)
    ui.SetVisibility(TAB, VIS, "Breathe Amount",   breathe_on)
    ui.SetVisibility(TAB, VIS, "Shape Thickness",  shape_on)
    ui.SetVisibility(TAB, VIS, "Shape Fill",       shape_on)
    ui.SetVisibility(TAB, VIS, "Shape Fill Color", shape_fill_on)
    ui.SetVisibility(TAB, VIS, "Home Color",       goal_esp)
    ui.SetVisibility(TAB, VIS, "Away Color",       goal_esp)
    ui.SetVisibility(TAB, VIS, "Goal ESP Text",    goal_esp)
    ui.SetVisibility(TAB, VIS, "Goal Fill",        goal_esp)
    ui.SetVisibility(TAB, VIS, "Home Fill Color",  goal_fill)
    ui.SetVisibility(TAB, VIS, "Away Fill Color",  goal_fill)

    local ind_on   = ui.getValue(TAB, VIS, "Ball Indicator")
    local arrow_on = ui.getValue(TAB, VIS, "Velocity Arrow")
    local snap_on  = ui.getValue(TAB, VIS, "Snap Line")
    local trail_on = ui.getValue(TAB, VIS, "Ball Trail")
    ui.SetVisibility(TAB, VIS, "Indicator Color",  ind_on)
    ui.SetVisibility(TAB, VIS, "Indicator Radius", ind_on)
    ui.SetVisibility(TAB, VIS, "Arrow Color",     arrow_on)
    ui.SetVisibility(TAB, VIS, "Arrow Scale",     arrow_on)
    ui.SetVisibility(TAB, VIS, "Snap Color",      snap_on)
    ui.SetVisibility(TAB, VIS, "Trail Color",     trail_on)
    ui.SetVisibility(TAB, VIS, "Trail Length",    trail_on)

    local dribble_on = ui.getValue(TAB, MAN, "Auto Dribble")
    local linger_on  = dribble_on and ui.getValue(TAB, MAN, "Linger")
    ui.SetVisibility(TAB, MAN, "Dribble Key",      dribble_on)
    ui.SetVisibility(TAB, MAN, "Dribble Radius",   dribble_on)
    ui.SetVisibility(TAB, MAN, "Show Radius",      dribble_on)
    ui.SetVisibility(TAB, MAN, "Linger",           dribble_on)
    ui.SetVisibility(TAB, MAN, "Linger Radius",    linger_on)
    ui.SetVisibility(TAB, MAN, "Linger Time (ms)", linger_on)
end)

-- [Update: ball physics (speed / arc)]

cheat.register("onUpdate", function()
    local spd_enabled = ui.getValue(TAB, FEAT, "Speed Enabled")
    if spd_enabled then
        if hotkey_is_hold("Speed Key", FEAT) then
            speed_active = ui.getValue(TAB, FEAT, "Speed Key") == true
        elseif hotkey_clicked("Speed Key", FEAT) then
            speed_active = not speed_active
        end
    else
        speed_active = false
    end

    local arc_enabled = ui.getValue(TAB, FEAT, "Ball Arc")
    if arc_enabled then
        if hotkey_is_hold("Arc Key", FEAT) then
            arc_active = ui.getValue(TAB, FEAT, "Arc Key") == true
        elseif hotkey_clicked("Arc Key", FEAT) then
            arc_active = not arc_active
        end
    else
        arc_active = false
    end

    local spd_on = spd_enabled and speed_active
    local arc_on = arc_enabled and arc_active
    if not spd_on and not arc_on then flat_lock_y = nil; return end

    local target = world_ball
    if not target or not target.Parent then flat_lock_y = nil; return end

    local ok, vel = pcall(function() return target.Velocity end)
    if not ok or not vel then return end
    if vel.Magnitude < 0.5 then flat_lock_y = nil; return end

    if spd_on then
        local multiplier = ui.getValue(TAB, FEAT, "Speed Multiplier")
        local smoothing  = ui.getValue(TAB, FEAT, "Smoothing")
        local cap        = ui.getValue(TAB, FEAT, "Enable Speed Cap")
        local max_speed  = ui.getValue(TAB, FEAT, "Max Speed Cap")
        local boosted = vel * multiplier
        if smoothing > 0 then
            boosted = prev_vel:Lerp(boosted, 1 - smoothing)
        end
        if cap and boosted.Magnitude > max_speed then
            boosted = boosted.Unit * max_speed
        end
        pcall(function() target.Velocity = boosted end)
        prev_vel = boosted
        vel = boosted
    end

    if arc_on then
        local arc   = ui.getValue(TAB, FEAT, "Arc Level")
        local horiz = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
        if horiz < 0.1 then flat_lock_y = nil; return end

        if arc <= 0.0 then
            if not flat_lock_y then
                local ok2, pos = pcall(function() return target.Position end)
                flat_lock_y = ok2 and pos and pos.Y or nil
            end
            pcall(function() target.Velocity = Vector3.new(vel.X, 0, vel.Z) end)
            if flat_lock_y then
                pcall(function()
                    local pos = target.Position
                    if math.abs(pos.Y - flat_lock_y) > 0.3 then
                        target.Position = Vector3.new(pos.X, flat_lock_y, pos.Z)
                    end
                end)
            end
        else
            local target_vy = vel.Y * arc
            pcall(function()
                target.Velocity = Vector3.new(vel.X, vel.Y + (target_vy - vel.Y) * 0.2, vel.Z)
            end)
            flat_lock_y = nil
        end
    else
        flat_lock_y = nil
    end
end)

-- [Update: orbit + ball control]

cheat.register("onUpdate", function()
    local orb_enabled = ui.getValue(TAB, MAN, "Orbit Enabled")
    if orb_enabled then
        if hotkey_is_hold("Orbit Key", MAN) then
            orbit_active = ui.getValue(TAB, MAN, "Orbit Key") == true
        elseif hotkey_clicked("Orbit Key", MAN) then
            orbit_active = not orbit_active
        end
    else
        orbit_active = false
    end

    local bc_enabled = ui.getValue(TAB, MAN, "BC Enabled")
    local was_bc = bc_active
    if bc_enabled then
        if hotkey_is_hold("BC Key", MAN) then
            bc_active = ui.getValue(TAB, MAN, "BC Key") == true
        elseif hotkey_clicked("BC Key", MAN) then
            bc_active = not bc_active
        end
    else
        bc_active = false
    end

    if bc_active and not was_bc then bc_init() end

    local ball = world_ball
             or (held_ball and held_ball.Parent and held_ball)
             or (free_ball and free_ball.Parent and free_ball)
    if not ball or not ball.Parent then return end

    if bc_active then
        local dt   = utility.GetDeltaTime()
        local spd  = ui.getValue(TAB, MAN, "Move Speed")
        local step = spd * 10 * dt

        if keyboard.IsPressed("W") then
            bc_pos_x = bc_pos_x - cam_fwx * step
            bc_pos_z = bc_pos_z - cam_fwz * step
        end
        if keyboard.IsPressed("S") then
            bc_pos_x = bc_pos_x + cam_fwx * step
            bc_pos_z = bc_pos_z + cam_fwz * step
        end
        if keyboard.IsPressed("A") then
            bc_pos_x = bc_pos_x - cam_rx * step
            bc_pos_z = bc_pos_z - cam_rz * step
        end
        if keyboard.IsPressed("D") then
            bc_pos_x = bc_pos_x + cam_rx * step
            bc_pos_z = bc_pos_z + cam_rz * step
        end
        if keyboard.IsPressed("Space") then bc_pos_y = bc_pos_y + step end
        if keyboard.IsPressed("Shift") then bc_pos_y = bc_pos_y - step end

        ball.Position = Vector3.new(bc_pos_x, bc_pos_y, bc_pos_z)
        ball.Velocity = Vector3.new(0, 0, 0)

        if ui.getValue(TAB, MAN, "Freeze Player") then
            local lp = entity.GetLocalPlayer()
            if lp then
                local char     = game.Workspace:FindFirstChild(lp.Name)
                local hrp_part = char and char:FindFirstChild("HumanoidRootPart")
                if hrp_part then
                    local cur = lp:GetBonePosition("HumanoidRootPart")
                    if cur then
                        local dx = cur.X - frozen_x
                        local dz = cur.Z - frozen_z
                        if dx*dx + dz*dz < 100 then
                            hrp_part.Position = Vector3.new(frozen_x, frozen_y, frozen_z)
                            hrp_part.Velocity = Vector3.new(0, 0, 0)
                        else
                            frozen_x, frozen_y, frozen_z = cur.X, cur.Y, cur.Z
                        end
                    end
                end
            end
        end

    elseif orbit_active then
        local lp = entity.GetLocalPlayer()
        if not lp then return end
        local hrp = lp:GetBonePosition("HumanoidRootPart")
        if not hrp then return end

        local now  = utility.GetTickCount()
        local dt   = (now - orbit_last) / 1000.0
        orbit_last = now

        local radius = ui.getValue(TAB, MAN, "Radius")
        local height = ui.getValue(TAB, MAN, "Height")
        local spd    = ui.getValue(TAB, MAN, "Speed (rps)")

        orbit_angle = orbit_angle + dt * spd * pi2
        if orbit_angle > pi2 then orbit_angle = orbit_angle - pi2 end

        ball.Position = Vector3.new(
            hrp.X + cos(orbit_angle) * radius,
            hrp.Y + height,
            hrp.Z + sin(orbit_angle) * radius
        )
        ball.Velocity = Vector3.new(0, 0, 0)
    end
end)

-- [Update: teleport]

cheat.register("onUpdate", function()
    if not ui.getValue(TAB, FEAT, "Teleport Enabled") then
        if ptb_phase == "stealing" then keyboard.Release("e") end
        glue_active     = false
        ptb_phase       = "idle"
        ptb_retries     = 0
        ptb_return_pos  = nil
        tween_start_pos = nil
        ret_tween_start = nil
        ret_use_tween   = false
        info_tp_status  = "Teleport disabled"
        return
    end

    local hrp = local_char and local_char:FindFirstChild("HumanoidRootPart")
    if not hrp then info_tp_status = "Char not found"; return end

    if ptb_phase == "returning" then
        if ret_use_tween and ret_tween_start then
            local ret_dur  = ui.getValue(TAB, FEAT, "Return Time (sec)")
            local elapsed  = now_sec() - ret_tween_start_time
            local progress = math.min(elapsed / ret_dur, 1.0)
            local alpha    = 1 - (1 - progress) ^ 3
            local new_pos  = ret_tween_start:Lerp(ptb_return_pos, alpha)
            for _ = 1, 25 do pcall(function() hrp.Position = new_pos end) end
            if progress >= 1.0 then
                info_tp_status  = "Returned"
                ptb_phase       = "idle"
                ptb_return_pos  = nil
                ret_tween_start = nil
            else
                info_tp_status = string.format("Returning %d%%", math.floor(progress * 100))
            end
        else
            local target_pos = ptb_return_pos
            for _ = 1, 25 do pcall(function() hrp.Position = target_pos end) end
            local ok, dist = pcall(function() return (hrp.Position - target_pos).Magnitude end)
            if (ok and dist < 8) or (now_sec() - ptb_dwell_start > 0.5) then
                info_tp_status = "Returned"
                ptb_phase      = "idle"
                ptb_return_pos = nil
            else
                info_tp_status = "Returning..."
            end
        end
        return
    end

    local ball = world_ball or (free_ball and free_ball.Parent and free_ball)

    if not ball then
        if (ptb_phase == "at_ball" or ptb_phase == "stealing" or ptb_phase == "tweening") and ptb_return_pos then
            if ptb_phase == "stealing" then keyboard.Release("e") end
            ptb_retries          = 0
            tween_start_pos      = nil
            ret_use_tween        = ui.getValue(TAB, FEAT, "Travel Mode") == 1
            ret_tween_start      = hrp.Position
            ret_tween_start_time = now_sec()
            ptb_phase            = "returning"
            ptb_dwell_start      = now_sec()
            info_tp_status       = "Ball lost - returning"
        else
            info_tp_status = "Ball not found"
        end
        return
    end

    local mode     = ui.getValue(TAB, FEAT, "TP Mode")
    local dwell    = ui.getValue(TAB, FEAT, "Dwell Time (sec)")
    local preserve = ui.getValue(TAB, FEAT, "Preserve Momentum")
    local clicked  = hotkey_clicked("Teleport Key", FEAT)

    if mode == 0 then
        if clicked then
            local tgt       = front_target(hrp)
            local saved_vel = ball.Velocity
            local dist      = (ball.Position - hrp.Position).Magnitude
            local ok, err   = pcall(function()
                ball.Position = tgt
                ball.Velocity = preserve and saved_vel or Vector3.new(0, 0, 0)
            end)
            info_tp_status = ok and ("Pulled " .. string.format("%.0f", dist) .. "st")
                                or ("TP fail: " .. tostring(err))
        else
            info_tp_status = "Pull mode ready"
        end

    elseif mode == 1 then
        if hotkey_is_hold("Teleport Key", FEAT) then
            glue_active = ui.getValue(TAB, FEAT, "Teleport Key") == true
        elseif clicked then
            glue_active = not glue_active
        end
        if glue_active then
            local ok = pcall(function()
                ball.Position = front_target(hrp)
                ball.Velocity = Vector3.new(0, 0, 0)
            end)
            info_tp_status = ok and "Glue mode: on" or "Glue mode: fail"
        else
            info_tp_status = "Glue mode: off"
        end

    else
        local use_tween = ui.getValue(TAB, FEAT, "Travel Mode") == 1

        local is_local_holding = holder_char and local_char and holder_char.Name == local_char.Name
        local enemy_hrp = nil
        if holder_char and holder_char.Parent and not is_local_holding then
            enemy_hrp = holder_char:FindFirstChild("HumanoidRootPart")
        end

        local function ball_approach_target()
            return ball.Position + Vector3.new(0, OFF_UP, 0)
        end

        if ptb_phase == "idle" then
            if clicked then
                if is_local_holding then
                    info_tp_status = "Holding ball"
                else
                    ptb_return_pos = hrp.Position
                    ptb_start_time = now_sec()
                    if enemy_hrp then
                        if use_tween then
                            tween_start_pos  = hrp.Position
                            tween_start_time = now_sec()
                            tween_to_phase   = "stealing"
                            ptb_phase        = "tweening"
                            info_tp_status   = "Moving to enemy..."
                        else
                            local ok, err = pcall(function() hrp.Position = enemy_hrp.Position end)
                            if ok then
                                ptb_phase       = "stealing"
                                ptb_dwell_start = now_sec()
                                info_tp_status  = "Stealing..."
                            else
                                info_tp_status = "Steal fail: " .. tostring(err)
                                ptb_return_pos = nil
                            end
                        end
                    else
                        if use_tween then
                            tween_start_pos  = hrp.Position
                            tween_start_time = now_sec()
                            tween_to_phase   = "at_ball"
                            ptb_phase        = "tweening"
                            info_tp_status   = "Moving to ball..."
                        else
                            local tgt = ball_approach_target()
                            local ok, err = pcall(function() hrp.Position = tgt end)
                            if ok then
                                ptb_phase       = "at_ball"
                                ptb_dwell_start = now_sec()
                                ptb_retries     = 0
                                info_tp_status  = "At ball..."
                            else
                                info_tp_status = "TP fail: " .. tostring(err)
                                ptb_return_pos = nil
                            end
                        end
                    end
                end
            else
                if is_local_holding then
                    info_tp_status = "Holding ball"
                elseif enemy_hrp then
                    local ok, dist = pcall(function() return (hrp.Position - enemy_hrp.Position).Magnitude end)
                    info_tp_status = ok and string.format("Steal ready (%.0fst)", dist) or "Steal ready"
                else
                    info_tp_status = "To ball: ready"
                end
            end

        elseif ptb_phase == "tweening" or ptb_phase == "at_ball" or ptb_phase == "stealing" then
            if now_sec() - ptb_start_time > PTB_TIMEOUT then
                if ptb_phase == "stealing" then keyboard.Release("e") end
                ptb_retries          = 0
                tween_start_pos      = nil
                ret_use_tween        = use_tween
                ret_tween_start      = hrp.Position
                ret_tween_start_time = now_sec()
                ptb_phase            = "returning"
                ptb_dwell_start      = now_sec()
                info_tp_status       = "Timeout - returning"
                return
            end
        end

        if ptb_phase == "tweening" then
            local elapsed  = now_sec() - tween_start_time
            local tw_dur   = ui.getValue(TAB, FEAT, "Tween Time (sec)")
            local progress = math.min(elapsed / tw_dur, 1.0)
            local alpha    = 1 - (1 - progress) ^ 3

            local tgt_pos
            if tween_to_phase == "stealing" and enemy_hrp and enemy_hrp.Parent then
                tgt_pos = enemy_hrp.Position
            elseif ball and ball.Parent then
                tween_to_phase = "at_ball"
                tgt_pos = ball_approach_target()
            else
                tween_start_pos      = nil
                ret_use_tween        = use_tween
                ret_tween_start      = hrp.Position
                ret_tween_start_time = now_sec()
                ptb_phase            = "returning"
                ptb_dwell_start      = now_sec()
                info_tp_status       = "Lost target"
                return
            end

            local new_pos = tween_start_pos:Lerp(tgt_pos, alpha)
            for _ = 1, 25 do pcall(function() hrp.Position = new_pos end) end

            if progress >= 1.0 then
                tween_start_pos = nil
                if tween_to_phase == "stealing" then
                    ptb_phase       = "stealing"
                    ptb_dwell_start = now_sec()
                    info_tp_status  = "Stealing..."
                else
                    ptb_phase       = "at_ball"
                    ptb_dwell_start = now_sec()
                    ptb_retries     = 0
                    info_tp_status  = "At ball..."
                end
            else
                info_tp_status = string.format("Moving %d%%", math.floor(progress * 100))
            end

        elseif ptb_phase == "stealing" then
            if enemy_hrp and enemy_hrp.Parent then
                pcall(function() hrp.Position = enemy_hrp.Position end)
            end
            keyboard.Press("e")
            local steal_dwell = ui.getValue(TAB, FEAT, "Steal Dwell (sec)")
            local elapsed     = now_sec() - ptb_dwell_start
            if elapsed >= steal_dwell then
                keyboard.Release("e")
                ret_use_tween        = use_tween
                ret_tween_start      = hrp.Position
                ret_tween_start_time = now_sec()
                ptb_phase            = "returning"
                ptb_dwell_start      = now_sec()
                info_tp_status       = "Returning..."
            else
                info_tp_status = string.format("Stealing %.1fs", steal_dwell - elapsed)
            end

        elseif ptb_phase == "at_ball" then
            local ok_hb, got_ball = pcall(function()
                local vals = local_char and local_char:FindFirstChild("Values")
                local hb   = vals and vals:FindFirstChild("HasBall")
                return hb and (hb.Value == true or hb.Value == 1)
            end)
            if ok_hb and got_ball then
                ptb_retries          = 0
                ret_use_tween        = use_tween
                ret_tween_start      = hrp.Position
                ret_tween_start_time = now_sec()
                ptb_phase            = "returning"
                ptb_dwell_start      = now_sec()
                info_tp_status       = "Got ball - returning"
                return
            end

            local elapsed = now_sec() - ptb_dwell_start
            if use_tween then
                pcall(function() hrp.Position = ball_approach_target() end)
            end
            if elapsed >= dwell then
                local retry_on = ui.getValue(TAB, FEAT, "Retry on Miss")
                local max_r    = ui.getValue(TAB, FEAT, "Max Retries")
                if retry_on and ptb_retries < max_r then
                    ptb_retries = ptb_retries + 1
                    if use_tween then
                        tween_start_pos  = hrp.Position
                        tween_start_time = now_sec()
                        tween_to_phase   = "at_ball"
                        ptb_phase        = "tweening"
                    else
                        local tgt = ball_approach_target()
                        pcall(function() hrp.Position = tgt end)
                        ptb_dwell_start = now_sec()
                    end
                    info_tp_status = string.format("Retry %d/%d", ptb_retries, max_r)
                else
                    ptb_retries          = 0
                    ret_use_tween        = use_tween
                    ret_tween_start      = hrp.Position
                    ret_tween_start_time = now_sec()
                    ptb_phase            = "returning"
                    ptb_dwell_start      = now_sec()
                    info_tp_status       = "Returning..."
                end
            else
                info_tp_status = string.format("At ball %.1fs", dwell - elapsed)
            end
        end
    end
end)

-- [Update: auto goal]

cheat.register("onUpdate", function()
    if not ui.getValue(TAB, FEAT, "Auto Goal") then
        auto_goal_active = false
        return
    end

    if hotkey_is_hold("Auto Goal Key", FEAT) then
        auto_goal_active = ui.getValue(TAB, FEAT, "Auto Goal Key") == true
    elseif hotkey_clicked("Auto Goal Key", FEAT) then
        auto_goal_active = not auto_goal_active
    end

    if not auto_goal_active then return end

    local ball = world_ball
              or (held_ball and held_ball.Parent and held_ball)
              or (free_ball and free_ball.Parent and free_ball)
    if not ball then return end

    local target_idx = ui.getValue(TAB, FEAT, "Goal Target")

    if target_idx == 0 then
        local player_team = ""
        pcall(function()
            local lp = game.LocalPlayer
            if lp and lp.Team then player_team = tostring(lp.Team) end
        end)
        if player_team == "" then return end

        local goals_f = game.Workspace:FindFirstChild("Goals")
        if not goals_f then return end

        local goal_parts = {}
        for _, c in ipairs(goals_f:GetChildren()) do
            if c.ClassName == "Part" or c.ClassName == "MeshPart" then
                goal_parts[#goal_parts + 1] = c
            end
        end

        local on_team = false
        for _, g in ipairs(goal_parts) do
            if g.Name == player_team then on_team = true; break end
        end
        if not on_team then return end

        for _, g in ipairs(goal_parts) do
            if g.Name == player_team then
                pcall(function()
                    ball.Position = g.Position
                    ball.Velocity = Vector3.new(0, 0, 0)
                end)
                return
            end
        end
        return
    end

    local target_name = (target_idx == 1) and "Home" or "Away"
    local goals_f     = game.Workspace:FindFirstChild("Goals")
    local goal_part   = goals_f and goals_f:FindFirstChild(target_name)
    if not goal_part then return end

    local ok, pos = pcall(function() return goal_part.Position end)
    if not ok or not pos then return end
    pcall(function()
        ball.Position = pos
        ball.Velocity = Vector3.new(0, 0, 0)
    end)
end)

-- [Update: auto dribble]

cheat.register("onUpdate", function()
    -- release q once its hold duration has elapsed
    if dribble_q_down and (now_sec() - dribble_q_time) >= 0.15 then
        keyboard.Release("q")
        dribble_q_down = false
    end

    if not ui.getValue(TAB, MAN, "Auto Dribble") then
        if dribble_q_down then keyboard.Release("q"); dribble_q_down = false end
        auto_dribble_active = false
        return
    end

    if hotkey_is_hold("Dribble Key", MAN) then
        auto_dribble_active = ui.getValue(TAB, MAN, "Dribble Key") == true
    elseif hotkey_clicked("Dribble Key", MAN) then
        auto_dribble_active = not auto_dribble_active
    end

    if not auto_dribble_active and dribble_q_down then
        keyboard.Release("q"); dribble_q_down = false
    end

    local lp   = entity.GetLocalPlayer()
    local lpos = lp and lp:GetBonePosition("HumanoidRootPart")

    -- scan enemies (always runs so HUD stays live when inactive)
    dribble_enemy_near   = false
    dribble_enemy_slide  = false
    dribble_linger_near  = false
    dribble_linger_slide = false

    if lpos then
        local now_t      = utility.GetTickCount()
        local main_r     = ui.getValue(TAB, MAN, "Dribble Radius")    or 6.0
        local linger_enabled = ui.getValue(TAB, MAN, "Linger")
        local linger_r   = linger_enabled and (ui.getValue(TAB, MAN, "Linger Radius")    or 4.5)
        local linger_ms  = linger_enabled and (ui.getValue(TAB, MAN, "Linger Time (ms)") or 150)

        -- update position history and find the past position for the linger zone
        dribble_pos_history[#dribble_pos_history + 1] = {lpos, now_t}
        while #dribble_pos_history > 1 and now_t - dribble_pos_history[1][2] > 2000 do
            table.remove(dribble_pos_history, 1)
        end

        local linger_pos = nil
        if linger_enabled then
            for i = #dribble_pos_history, 1, -1 do
                if now_t - dribble_pos_history[i][2] >= linger_ms then
                    linger_pos = dribble_pos_history[i][1]
                    break
                end
            end
        end

        local ok, enemies = pcall(function() return entity.GetPlayers(true) end)
        if ok and enemies then
            for _, enemy in ipairs(enemies) do
                local epos = enemy:GetBonePosition("HumanoidRootPart")
                if epos then
                    local in_main   = (epos - lpos).Magnitude <= main_r
                    local in_linger = linger_pos and (epos - linger_pos).Magnitude <= linger_r

                    if in_main or in_linger then
                        if in_main   then dribble_enemy_near  = true end
                        if in_linger then dribble_linger_near = true end

                        local char = game.Workspace:FindFirstChild(enemy.Name)
                        local vals = char and char:FindFirstChild("Values")
                        local sl = vals and vals:FindFirstChild("Sliding")
                        local st = vals and vals:FindFirstChild("Stealing")
                        local is_sliding = (sl and (sl.Value == true or sl.Value == 1))
                                        or (st and (st.Value == true or st.Value == 1))

                        if is_sliding then
                            if in_main   then dribble_enemy_slide  = true end
                            if in_linger then dribble_linger_slide = true end
                        end
                    end
                end

                if dribble_enemy_slide and (not linger_pos or dribble_linger_slide) then break end
            end
        end
    end

    if not auto_dribble_active then return end

    local ok_hb, has_ball = pcall(function()
        local vals = local_char and local_char:FindFirstChild("Values")
        local hb   = vals and vals:FindFirstChild("HasBall")
        return hb and (hb.Value == true or hb.Value == 1)
    end)
    if not (ok_hb and has_ball) then return end

    if (dribble_enemy_slide or dribble_linger_slide) and not dribble_q_down then
        local t = now_sec()
        if t - dribble_last_q >= 0.4 then
            keyboard.Press("q")
            dribble_q_down = true
            dribble_q_time = t
            dribble_last_q = t
        end
    end
end)

-- [Paint: cam axes + draw]

local function get_part_hull(part)
    local corners = draw.GetPartCorners(part)
    if not corners then return nil end
    local n = 0
    for _, wp in ipairs(corners) do
        local ok, sx, sy = pcall(function()
            local x, y = utility.WorldToScreen(wp)
            return x, y
        end)
        if ok and sx and sy then
            n = n + 1
            _screen_buf[n] = _screen_buf[n] or {}
            _screen_buf[n][1] = sx
            _screen_buf[n][2] = sy
        end
    end
    if n < 2 then return nil end
    local pts = {}
    for i = 1, n do pts[i] = _screen_buf[i] end
    return draw.ComputeConvexHull(pts)
end

local function draw_hull_box(hull, color, alpha)
    if hull and #hull >= 2 then draw.Polyline(hull, color, true, 1.5, alpha) end
end

local function draw_hull_fill(hull, color, alpha)
    if hull and #hull >= 3 then draw.ConvexPolyFilled(hull, color, alpha) end
end

cheat.register("onPaint", function()
    local fwx, fwz, rx, rz = get_cam_axes()
    if fwx ~= nil then
        cam_fwx, cam_fwz, cam_rx, cam_rz = fwx, fwz, rx, rz
    end

    local font = VIS_FONTS[(ui.getValue(TAB, VIS, "Font") or 0) + 1] or "Tahoma"

    local _ol    = ui.getValue(TAB, VIS, "ESP Outlines") or {}
    local ol_box = _ol[1]; local ol_shape = _ol[2]; local ol_goal  = _ol[3]
    local ol_ind = _ol[4]; local ol_arrow = _ol[5]; local ol_snap  = _ol[6]
    local ol_trail = _ol[7]

    if holder_char and holder_char.Parent then
        local ok, v = pcall(function()
            local hrp = holder_char:FindFirstChild("HumanoidRootPart")
            return hrp and hrp.Velocity.Magnitude
        end)
        info_speed = ok and v and math.floor(v * 10) / 10 or 0
    elseif world_ball then
        local ok, v = pcall(function() return world_ball.Velocity.Magnitude end)
        info_speed = ok and v and math.floor(v * 10) / 10 or 0
    else
        info_speed = 0
    end

    if ui.getValue(TAB, VIS, "Info Display") then
        local _sw, sh = cheat.GetWindowSize()
        local x       = 10
        local COLOR_GREEN  = Color3.fromRGB(80, 255, 80)
        local COLOR_RED    = Color3.fromRGB(255, 80, 80)
        local COLOR_YELLOW = Color3.fromRGB(255, 220, 50)

        local lines = {}
        local function add(text, col) lines[#lines + 1] = {text, col or COLOR_WHITE} end
        local function hk_str(container, label)
            local hk = ui.getHotkey(TAB, container, label)
            if hk and hk.key and hk.key ~= 0 and hk.key_name and hk.key_name ~= "" then
                return " [" .. hk.key_name .. "]"
            end
            return ""
        end

        add("BL:R", COLOR_BLUE)
        add(tostring(info_speed) .. " st/s  " .. ball_status)
        add("Dist  " .. info_dist)

        if ui.getValue(TAB, FEAT, "Teleport Enabled") then
            add("TP" .. hk_str(FEAT, "Teleport Key") .. "  " .. info_tp_status)
        end
        if ui.getValue(TAB, FEAT, "Auto Goal") then
            local idx   = ui.getValue(TAB, FEAT, "Goal Target")
            local names = {"Auto", "Home", "Away"}
            local label = auto_goal_active and ("On -> " .. (names[idx + 1] or "?")) or "Ready"
            add("Goal" .. hk_str(FEAT, "Auto Goal Key") .. "  " .. label, auto_goal_active and COLOR_GREEN or COLOR_YELLOW)
        end
        if ui.getValue(TAB, FEAT, "Speed Enabled") then
            local state = speed_active and "On" or "Ready"
            add("Speed" .. hk_str(FEAT, "Speed Key") .. "  " .. state, speed_active and COLOR_GREEN or COLOR_YELLOW)
        end
        if ui.getValue(TAB, FEAT, "Ball Arc") then
            local state = arc_active and "On" or "Ready"
            add("Arc" .. hk_str(FEAT, "Arc Key") .. "  " .. state, arc_active and COLOR_GREEN or COLOR_YELLOW)
        end
        if ui.getValue(TAB, MAN, "Orbit Enabled") then
            local state = orbit_active and "On" or "Ready"
            add("Orbit" .. hk_str(MAN, "Orbit Key") .. "  " .. state, orbit_active and COLOR_GREEN or COLOR_YELLOW)
        end
        if ui.getValue(TAB, MAN, "BC Enabled") then
            local state = bc_active and "On" or "Ready"
            add("BC" .. hk_str(MAN, "BC Key") .. "  " .. state, bc_active and COLOR_GREEN or COLOR_YELLOW)
        end
        if ui.getValue(TAB, MAN, "Auto Dribble") then
            local state    = auto_dribble_active and "On" or "Ready"
            local any_near = dribble_enemy_near  or dribble_linger_near
            local any_slide = dribble_enemy_slide or dribble_linger_slide
            add("Dribble" .. hk_str(MAN, "Dribble Key") .. "  " .. state, auto_dribble_active and COLOR_GREEN or COLOR_YELLOW)
            add("  Near   " .. (any_near  and "YES" or "NO"), any_near  and COLOR_RED or COLOR_GREEN)
            add("  Slide  " .. (any_slide and "YES" or "NO"), any_slide and COLOR_RED or COLOR_GREEN)
        end

        local base_y = sh - 10
        for i = #lines, 1, -1 do
            base_y = base_y - 15
            draw.TextOutlined(lines[i][1], x, base_y, lines[i][2], font, 255)
        end
    end

    if ui.getValue(TAB, MAN, "Auto Dribble") and ui.getValue(TAB, MAN, "Show Radius") then
        local lp   = entity.GetLocalPlayer()
        local lpos = lp and lp:GetBonePosition("HumanoidRootPart")
        if lpos then
            local radius   = ui.getValue(TAB, MAN, "Dribble Radius") or 6.0
            local ring_col = dribble_enemy_slide and Color3.fromRGB(255, 50, 50)
                          or dribble_enemy_near  and Color3.fromRGB(255, 160, 0)
                          or Color3.fromRGB(80, 255, 80)
            local pts = {}
            for i = 0, 31 do
                local a  = i * (pi2 / 32)
                local wp = Vector3.new(lpos.X + cos(a) * radius, lpos.Y, lpos.Z + sin(a) * radius)
                local ok, sx, sy, on = pcall(function() return utility.WorldToScreen(wp) end)
                if ok and on then pts[#pts + 1] = {sx, sy} end
            end
            if #pts >= 2 then
                draw.Polyline(pts, ring_col, #pts == 32, 1.0, 180)
            end

            if ui.getValue(TAB, MAN, "Linger") then
                local linger_ms  = ui.getValue(TAB, MAN, "Linger Time (ms)") or 150
                local linger_r   = ui.getValue(TAB, MAN, "Linger Radius")    or 4.5
                local now_t      = utility.GetTickCount()
                local linger_pos = nil
                for i = #dribble_pos_history, 1, -1 do
                    if now_t - dribble_pos_history[i][2] >= linger_ms then
                        linger_pos = dribble_pos_history[i][1]
                        break
                    end
                end
                if linger_pos then
                    local linger_col = dribble_linger_slide and Color3.fromRGB(255, 50, 50)
                                   or dribble_linger_near  and Color3.fromRGB(255, 160, 0)
                                   or Color3.fromRGB(80, 255, 80)
                    local lpts = {}
                    for i = 0, 31 do
                        local a  = i * (pi2 / 32)
                        local wp = Vector3.new(linger_pos.X + cos(a) * linger_r, linger_pos.Y, linger_pos.Z + sin(a) * linger_r)
                        local ok2, sx2, sy2, on2 = pcall(function() return utility.WorldToScreen(wp) end)
                        if ok2 and on2 then lpts[#lpts + 1] = {sx2, sy2} end
                    end
                    if #lpts >= 2 then
                        draw.Polyline(lpts, linger_col, #lpts == 32, 1.0, 90)
                    end
                end
            end
        end
    end

    local ball_esp_on  = ui.getValue(TAB, VIS, "Ball ESP")
    local box_on       = ball_esp_on and ui.getValue(TAB, VIS, "Box")
    local ball_fill_on = box_on and ui.getValue(TAB, VIS, "Ball Fill")
    if box_on or ball_fill_on then
        local ball_col_t      = ui.getValue(TAB, VIS, "Ball Color") or {}
        local ball_color      = picker_to_color3(ball_col_t)
        local ball_alpha      = ball_col_t.a or 255
        local ball_fill_t     = ui.getValue(TAB, VIS, "Ball Fill Color") or {}
        local ball_fill_color = picker_to_color3(ball_fill_t)
        local ball_fill_alpha = ball_fill_t.a or 60

        local is_local_holding = local_has_ball
            or (holder_char and local_char and holder_char.Name == local_char.Name)
        local ball_part
        if is_local_holding then
            -- local player has the ball, skip ESP
        elseif held_ball and held_ball.Parent then
            ball_part = held_ball
        elseif holder_char and holder_char.Parent then
            ball_part = holder_char:FindFirstChild("Football")
                     or holder_char:FindFirstChild("Hitbox")
        else
            ball_part = world_ball
        end

        if ball_part then
            local hull = get_part_hull(ball_part)
            if ball_fill_on then draw_hull_fill(hull, ball_fill_color, ball_fill_alpha) end
            if box_on then
                if ol_box and hull and #hull >= 2 then draw.Polyline(hull, COLOR_BLACK, true, 3.5, ball_alpha) end
                draw_hull_box(hull, ball_color, ball_alpha)
            end

            if box_on and ui.getValue(TAB, VIS, "Ball ESP Text") then
                local ok, sx, sy, on = pcall(function()
                    return utility.WorldToScreen(ball_part.Position + Vector3.new(0, 4, 0))
                end)
                if ok and on then
                    local hrp = local_char and local_char:FindFirstChild("HumanoidRootPart")
                    if holder_char and holder_char.Parent then
                        draw.TextOutlined(holder_char.Name .. " [ball]", sx, sy, ball_color, font, ball_alpha)
                    elseif hrp then
                        local ok2, dist = pcall(function() return (ball_part.Position - hrp.Position).Magnitude end)
                        local label = ok2 and string.format("Ball [%.0f]", dist) or "Ball"
                        draw.TextOutlined(label, sx, sy, ball_color, font, ball_alpha)
                    else
                        draw.TextOutlined("Ball", sx, sy, ball_color, font, ball_alpha)
                    end
                end
            end
        end
    end

    local goal_esp_on  = ui.getValue(TAB, VIS, "Goal ESP")
    local goal_fill_on = goal_esp_on and ui.getValue(TAB, VIS, "Goal Fill")
    if goal_esp_on then
        local home_col_t    = ui.getValue(TAB, VIS, "Home Color") or {}
        local away_col_t    = ui.getValue(TAB, VIS, "Away Color") or {}
        local home_color    = picker_to_color3(home_col_t)
        local away_color    = picker_to_color3(away_col_t)
        local home_alpha    = home_col_t.a or 255
        local away_alpha    = away_col_t.a or 255
        local home_fill_t   = ui.getValue(TAB, VIS, "Home Fill Color") or {}
        local away_fill_t   = ui.getValue(TAB, VIS, "Away Fill Color") or {}
        local home_fill_col = picker_to_color3(home_fill_t)
        local away_fill_col = picker_to_color3(away_fill_t)
        local goal_text_on  = ui.getValue(TAB, VIS, "Goal ESP Text")

        for _, entry in ipairs(goal_boxes) do
            local gb = entry.part
            if gb and gb.Parent then
                local is_home  = entry.name == "Home"
                local col      = is_home and home_color    or away_color
                local col_a    = is_home and home_alpha    or away_alpha
                local fill_col = is_home and home_fill_col or away_fill_col
                local fill_a   = is_home and (home_fill_t.a or 40) or (away_fill_t.a or 40)
                local hull = get_part_hull(gb)
                if goal_fill_on then draw_hull_fill(hull, fill_col, fill_a) end
                if goal_esp_on then
                    if ol_goal and hull and #hull >= 2 then draw.Polyline(hull, COLOR_BLACK, true, 3.5, col_a) end
                    draw_hull_box(hull, col, col_a)
                end
                if goal_esp_on and goal_text_on and hull and #hull >= 1 then
                    local max_x, min_y = -math.huge, math.huge
                    for _, p in ipairs(hull) do
                        if p[1] > max_x then max_x = p[1] end
                        if p[2] < min_y then min_y = p[2] end
                    end
                    draw.TextOutlined(entry.name, max_x + 2, min_y - 14, col, font, col_a)
                end
            end
        end
    end

    -- [Shape ESP]
    local now_tick = utility.GetTickCount()
    local shape_dt = math.min((now_tick - shape_last) / 1000.0, 0.1)
    shape_last      = now_tick
    shape_breathe_t = shape_breathe_t + shape_dt

    if ball_esp_on and ui.getValue(TAB, VIS, "Shape") then
        local ball_pos = get_ball_pos()
        if ball_pos then
            local ok, bsx, bsy, bon = pcall(function()
                return utility.WorldToScreen(ball_pos)
            end)
            if ok and bon then
                if ui.getValue(TAB, VIS, "Shape Spin") then
                    local spd = ui.getValue(TAB, VIS, "Spin Speed")
                    shape_angle = shape_angle + shape_dt * spd * pi2
                    if shape_angle > pi2 then shape_angle = shape_angle - pi2 end
                else
                    shape_angle = 0
                end

                local base_size = ui.getValue(TAB, VIS, "Shape Size")
                local size      = base_size
                if ui.getValue(TAB, VIS, "Shape Breathe") then
                    local amt = ui.getValue(TAB, VIS, "Breathe Amount")
                    size = base_size * (1.0 + amt * sin(shape_breathe_t * pi2))
                end

                local shape_col_t  = ui.getValue(TAB, VIS, "Shape Color") or {}
                local shape_color  = picker_to_color3(shape_col_t)
                local shape_alpha  = shape_col_t.a or 255
                local shape_idx    = ui.getValue(TAB, VIS, "Shape Type") or 0
                local thickness    = ui.getValue(TAB, VIS, "Shape Thickness") or 1.5
                local fill_on      = ui.getValue(TAB, VIS, "Shape Fill")
                local fill_col_t   = fill_on and (ui.getValue(TAB, VIS, "Shape Fill Color") or {}) or {}
                local fill_color   = picker_to_color3(fill_col_t)
                local fill_alpha   = fill_col_t.a or 50

                if shape_idx == 0 then
                    -- Star of David: two equilateral triangles
                    local pts1, pts2 = {}, {}
                    local base = shape_angle - pi * 0.5
                    for i = 0, 2 do
                        local a1 = base + i * (pi2 / 3)
                        local a2 = base + pi / 3 + i * (pi2 / 3)
                        pts1[i + 1] = {bsx + cos(a1) * size, bsy + sin(a1) * size}
                        pts2[i + 1] = {bsx + cos(a2) * size, bsy + sin(a2) * size}
                    end
                    if fill_on then
                        draw.ConvexPolyFilled(pts1, fill_color, fill_alpha)
                        draw.ConvexPolyFilled(pts2, fill_color, fill_alpha)
                    end
                    if ol_shape then
                        draw.Polyline(pts1, COLOR_BLACK, true, thickness + 2, shape_alpha)
                        draw.Polyline(pts2, COLOR_BLACK, true, thickness + 2, shape_alpha)
                    end
                    draw.Polyline(pts1, shape_color, true, thickness, shape_alpha)
                    draw.Polyline(pts2, shape_color, true, thickness, shape_alpha)

                elseif shape_idx == 1 then
                    -- Hexagon
                    local pts = {}
                    for i = 0, 5 do
                        local a = shape_angle + i * (pi2 / 6)
                        pts[i + 1] = {bsx + cos(a) * size, bsy + sin(a) * size}
                    end
                    if fill_on then draw.ConvexPolyFilled(pts, fill_color, fill_alpha) end
                    if ol_shape then draw.Polyline(pts, COLOR_BLACK, true, thickness + 2, shape_alpha) end
                    draw.Polyline(pts, shape_color, true, thickness, shape_alpha)

                else
                    -- Circle (32 segments)
                    local pts = {}
                    for i = 0, 31 do
                        local a = i * (pi2 / 32)
                        pts[i + 1] = {bsx + cos(a) * size, bsy + sin(a) * size}
                    end
                    if fill_on then draw.ConvexPolyFilled(pts, fill_color, fill_alpha) end
                    if ol_shape then draw.Polyline(pts, COLOR_BLACK, true, thickness + 2, shape_alpha) end
                    draw.Polyline(pts, shape_color, true, thickness, shape_alpha)
                end
            end
        end
    end

    -- [Ball Trail]
    if ui.getValue(TAB, VIS, "Ball Trail") and #trail_positions >= 2 then
        local trail_len   = ui.getValue(TAB, VIS, "Trail Length") or 20
        local trail_col_t = ui.getValue(TAB, VIS, "Trail Color") or {}
        local trail_color = picker_to_color3(trail_col_t)
        local trail_alpha = trail_col_t.a or 200
        local start_idx   = math.max(1, #trail_positions - trail_len + 1)
        local pts = {}
        for i = start_idx, #trail_positions do
            local ok, tsx, tsy, ton = pcall(function()
                return utility.WorldToScreen(trail_positions[i])
            end)
            if ok and ton then pts[#pts + 1] = {tsx, tsy} end
        end
        if #pts >= 2 then
            if ol_trail then draw.Polyline(pts, COLOR_BLACK, false, 3.5, trail_alpha) end
            draw.Polyline(pts, trail_color, false, 1.5, trail_alpha)
        end
    end

    -- [Snap Line]
    if ui.getValue(TAB, VIS, "Snap Line") then
        local ball_pos = get_ball_pos()
        if ball_pos then
            local sw, sh = cheat.GetWindowSize()
            local ok, bsx, bsy = pcall(function()
                local x, y = utility.WorldToScreen(ball_pos)
                return x, y
            end)
            if ok and not (bsx and bsy) then
                local cam_pos = game.CameraPosition
                if cam_pos then
                    local wx = ball_pos.X - cam_pos.X
                    local wy = ball_pos.Y - cam_pos.Y
                    local wz = ball_pos.Z - cam_pos.Z
                    local wl = math.sqrt(wx*wx + wy*wy + wz*wz)
                    if wl > 0.1 then
                        bsx = sw * 0.5 + (wx/wl * cam_rx + wz/wl * cam_rz) * sw
                        bsy = sh * 0.5 - (wy/wl) * sh
                    end
                end
            end
            if ok and bsx and bsy then
                bsx = math.max(0, math.min(sw, bsx))
                bsy = math.max(0, math.min(sh, bsy))
                local snap_col_t = ui.getValue(TAB, VIS, "Snap Color") or {}
                local snap_color = picker_to_color3(snap_col_t)
                local snap_alpha = snap_col_t.a or 150
                if ol_snap then draw.Polyline({{sw * 0.5, sh}, {bsx, bsy}}, COLOR_BLACK, false, 2.5, snap_alpha) end
                draw.Polyline({{sw * 0.5, sh}, {bsx, bsy}}, snap_color, false, 1.0, snap_alpha)
            end
        end
    end

    -- [Velocity Arrow]
    if ui.getValue(TAB, VIS, "Velocity Arrow") then
        local ball_pos = get_ball_pos()
        if ball_pos and world_ball and world_ball.Parent then
            local ok_v, vel = pcall(function() return world_ball.Velocity end)
            if ok_v and vel and vel.Magnitude > 0.5 then
                local ok1, bsx, bsy, bon = pcall(function()
                    return utility.WorldToScreen(ball_pos)
                end)
                local ok2, vdx, vdy = pcall(function()
                    local x, y = utility.WorldToScreen(ball_pos + vel.Unit)
                    return x, y
                end)
                if ok1 and ok2 and bon then
                    local sdx, sdy = vdx - bsx, vdy - bsy
                    local slen = math.sqrt(sdx * sdx + sdy * sdy)
                    if slen > 0.5 then
                        local nx, ny   = sdx / slen, sdy / slen
                        local arr_len  = (ui.getValue(TAB, VIS, "Arrow Scale") or 1.0) * 50
                        local ex, ey   = bsx + nx * arr_len, bsy + ny * arr_len
                        local arr_col_t = ui.getValue(TAB, VIS, "Arrow Color") or {}
                        local arr_color = picker_to_color3(arr_col_t)
                        local arr_alpha = arr_col_t.a or 255

                        local R = 6
                        local B = R * 1.5
                        local H = R * 0.866
                        local apt = {
                            {ex,               ey},
                            {ex - nx*B - ny*H, ey - ny*B + nx*H},
                            {ex - nx*B + ny*H, ey - ny*B - nx*H},
                        }
                        if ol_arrow then
                            draw.Polyline({{bsx, bsy}, {ex, ey}}, COLOR_BLACK, false, 3.5, arr_alpha)
                            draw.Polyline(apt, COLOR_BLACK, true, 3.5, arr_alpha)
                        end
                        draw.Polyline({{bsx, bsy}, {ex, ey}}, arr_color, false, 1.5, arr_alpha)
                        draw.ConvexPolyFilled(apt, arr_color, arr_alpha)
                        draw.Polyline(apt, arr_color, true, 1.5, arr_alpha)
                    end
                end
            end
        end
    end

    -- [Off-screen Ball Indicator]
    if ui.getValue(TAB, VIS, "Ball Indicator") then
        local ball_pos = get_ball_pos()
        if ball_pos then
            local sw, sh   = cheat.GetWindowSize()
            local cx, cy   = sw * 0.5, sh * 0.5
            local cam_pos  = game.CameraPosition

            -- 3D world direction from camera to ball (used for dot-product + fallback)
            local wx, wy, wz, wl = 0, 0, 0, 0
            local ball_in_front  = false
            if cam_pos then
                wx = ball_pos.X - cam_pos.X
                wy = ball_pos.Y - cam_pos.Y
                wz = ball_pos.Z - cam_pos.Z
                wl = math.sqrt(wx*wx + wy*wy + wz*wz)
                if wl > 0.1 then
                    -- Positive dot = ball is in front of camera
                    ball_in_front = (wx * cam_fwx + wz * cam_fwz) > 0
                end
            end

            local ok, bsx, bsy = pcall(function()
                local x, y = utility.WorldToScreen(ball_pos)
                return x, y
            end)

            local pad = 5
            local on_screen = ok and bsx and bsy
                              and bsx >= pad and bsx <= sw - pad
                              and bsy >= pad and bsy <= sh - pad

            if not on_screen then
                -- Compute screen-space direction to ball
                local dx, dy
                if ok and bsx and bsy and ball_in_front then
                    -- In front but off-screen: WorldToScreen coords are valid
                    dx, dy = bsx - cx, bsy - cy
                elseif wl > 0.1 then
                    -- Behind camera or nil coords: project world dir onto camera axes
                    dx = (wx/wl * cam_rx + wz/wl * cam_rz) * sw
                    dy = -(wy/wl) * sh
                end

                if dx and dy then
                    local len = math.sqrt(dx*dx + dy*dy)
                    if len > 1 then
                        local nx, ny    = dx / len, dy / len
                        local mpos      = utility.GetMousePos()
                        local mx, my    = mpos[1], mpos[2]
                        local radius    = ui.getValue(TAB, VIS, "Indicator Radius") or 60
                        local ex, ey    = mx + nx * radius, my + ny * radius
                        local ind_col_t = ui.getValue(TAB, VIS, "Indicator Color") or {}
                        local ind_color = picker_to_color3(ind_col_t)
                        local ind_alpha = ind_col_t.a or 255
                        local R = 8
                        local B = R * 1.5
                        local H = R * 0.866
                        local ipt = {
                            {ex,               ey},
                            {ex - B*nx - H*ny, ey - B*ny + H*nx},
                            {ex - B*nx + H*ny, ey - B*ny - H*nx},
                        }
                        if ol_ind then draw.Polyline(ipt, COLOR_BLACK, true, 3.5, ind_alpha) end
                        draw.ConvexPolyFilled(ipt, ind_color, ind_alpha)
                        draw.Polyline(ipt, ind_color, true, 1.5, ind_alpha)
                    end
                end
            end
        end
    end
end)

-- [Shutdown]

cheat.register("shutdown", function()
    if ptb_phase == "stealing" then keyboard.Release("e") end
    keyboard.Release("e")
    if dribble_q_down then keyboard.Release("q") end
    free_ball          = nil
    held_ball          = nil
    world_ball         = nil
    holder_char        = nil
    local_char         = nil
    goal_boxes         = {}
    orbit_active       = false
    bc_active          = false
    glue_active        = false
    auto_goal_active   = false
    ptb_phase          = "idle"
    ptb_retries        = 0
    ptb_return_pos     = nil
    tween_start_pos    = nil
    ret_tween_start    = nil
    ret_use_tween      = false
    flat_lock_y        = nil
end)
