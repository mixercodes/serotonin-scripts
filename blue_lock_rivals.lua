-- blue_lock_rivals.lua

local TP_MODES     = {"Ball to Player (pull)", "Ball Control (glue)", "Player to Ball"}
local TRAVEL_MODES = {"Instant", "Tween"}
local VIS_FONTS    = {"SmallestPixel", "Verdana", "ConsolasBold", "Tahoma"}

local TAB = "ballt_tab"
local SPD = "ballt_spd"
local TP  = "ballt_tp"
local VIS = "ballt_vis"

local OFF_UP = 2

ui.newTab(TAB, "BL:R")

-- [Ball Physics]
ui.NewContainer(TAB, SPD, "Ball Physics", { autosize = true })
ui.NewCheckbox(TAB, SPD, "Speed Enabled")
ui.newSliderFloat(TAB, SPD, "Speed Multiplier", 1.0, 10.0)
ui.newSliderFloat(TAB, SPD, "Smoothing", 0.0, 1.0)
ui.NewCheckbox(TAB, SPD, "Enable Speed Cap")
ui.newSliderFloat(TAB, SPD, "Max Speed Cap", 10.0, 500.0)
ui.NewCheckbox(TAB, SPD, "Ball Arc")
ui.newSliderFloat(TAB, SPD, "Arc Level", 0.0, 1.0)

-- [Ball Teleport]
ui.NewContainer(TAB, TP, "Ball Teleport", { autosize = true, next = true })
ui.NewCheckbox(TAB, TP, "Teleport Enabled")
ui.newHotkey(TAB, TP, "Teleport Key", true)
ui.newDropdown(TAB, TP, "TP Mode", TP_MODES)
ui.newDropdown(TAB, TP, "Travel Mode", TRAVEL_MODES)
ui.newSliderFloat(TAB, TP, "Tween Time (sec)", 0.05, 5.0)
ui.newSliderFloat(TAB, TP, "Return Time (sec)", 0.05, 5.0)
ui.newSliderFloat(TAB, TP, "Dwell Time (sec)", 0.0, 5.0)
ui.newSliderFloat(TAB, TP, "Steal Dwell (sec)", 0.1, 5.0)
ui.NewCheckbox(TAB, TP, "Retry on Miss")
ui.NewSliderInt(TAB, TP, "Max Retries", 1, 10)
ui.NewCheckbox(TAB, TP, "Preserve Momentum")
ui.NewCheckbox(TAB, TP, "Auto Goal")
ui.newHotkey(TAB, TP, "Auto Goal Key", true)
ui.newDropdown(TAB, TP, "Goal Target", {"Auto (enemy)", "Home", "Away"})

-- [Visuals]
ui.NewContainer(TAB, VIS, "Visuals", { autosize = true, next = true })
ui.newDropdown(TAB, VIS, "Font", VIS_FONTS)
ui.NewCheckbox(TAB, VIS, "Info Display")
ui.NewCheckbox(TAB, VIS, "Ball ESP")
ui.NewColorpicker(TAB, VIS, "Ball Color", {r=255, g=255, b=255, a=255}, true)
ui.NewCheckbox(TAB, VIS, "Ball ESP Text")
ui.NewCheckbox(TAB, VIS, "Ball Fill")
ui.NewColorpicker(TAB, VIS, "Ball Fill Color", {r=255, g=255, b=255, a=60}, true)
ui.NewCheckbox(TAB, VIS, "Goal ESP")
ui.NewColorpicker(TAB, VIS, "Home Color", {r=0, g=180, b=255, a=255}, true)
ui.NewColorpicker(TAB, VIS, "Away Color", {r=255, g=80, b=80, a=255}, true)
ui.NewCheckbox(TAB, VIS, "Goal ESP Text")
ui.NewCheckbox(TAB, VIS, "Goal Fill")
ui.NewColorpicker(TAB, VIS, "Home Fill Color", {r=0, g=180, b=255, a=40}, true)
ui.NewColorpicker(TAB, VIS, "Away Fill Color", {r=255, g=80, b=80, a=40}, true)

-- defaults
ui.setValue(TAB, SPD, "Speed Enabled",    false)
ui.setValue(TAB, SPD, "Speed Multiplier", 2.0)
ui.setValue(TAB, SPD, "Smoothing",        0.0)
ui.setValue(TAB, SPD, "Enable Speed Cap", false)
ui.setValue(TAB, SPD, "Max Speed Cap",    150.0)
ui.setValue(TAB, SPD, "Ball Arc",         false)
ui.setValue(TAB, SPD, "Arc Level",        0.5)
ui.setValue(TAB, TP,  "Teleport Enabled", false)
ui.setValue(TAB, TP,  "Teleport Key",     0x46)
ui.setValue(TAB, TP,  "TP Mode",          2)
ui.setValue(TAB, TP,  "Travel Mode",      1)
ui.setValue(TAB, TP,  "Tween Time (sec)", 0.05)
ui.setValue(TAB, TP,  "Return Time (sec)", 0.05)
ui.setValue(TAB, TP,  "Dwell Time (sec)", 0.3)
ui.setValue(TAB, TP,  "Steal Dwell (sec)", 0.6)
ui.setValue(TAB, TP,  "Retry on Miss",    false)
ui.setValue(TAB, TP,  "Max Retries",      3)
ui.setValue(TAB, TP,  "Preserve Momentum", true)
ui.setValue(TAB, TP,  "Auto Goal",        false)
ui.setValue(TAB, TP,  "Auto Goal Key",    0x47)
ui.setValue(TAB, TP,  "Goal Target",      0)
ui.setValue(TAB, VIS, "Font",             1)
ui.setValue(TAB, VIS, "Info Display",     true)
ui.setValue(TAB, VIS, "Ball ESP",         false)
ui.setValue(TAB, VIS, "Ball ESP Text",    true)
ui.setValue(TAB, VIS, "Ball Fill",        false)
ui.setValue(TAB, VIS, "Goal ESP",         false)
ui.setValue(TAB, VIS, "Goal ESP Text",    true)
ui.setValue(TAB, VIS, "Goal Fill",        false)

-- [Shared state]

local free_ball   = nil
local held_ball   = nil
local world_ball  = nil
local holder_char = nil
local local_char  = nil
local prev_vel    = Vector3.new(0, 0, 0)
local ball_status = "---"

local COLOR_WHITE = Color3.new(1, 1, 1)
local COLOR_BLUE  = Color3.fromHex("#3E79A7")

local _screen_buf = {}

local function refresh_ball_refs()
    local ball_model = game.Workspace:FindFirstChild("Ball")
    free_ball  = ball_model and ball_model:FindFirstChild("RootPart") or nil
    world_ball = game.Workspace:FindFirstChild("Football")

    held_ball   = nil
    holder_char = nil
    for _, child in ipairs(game.Workspace:GetChildren()) do
        if child.ClassName == "Model" and child:FindFirstChild("Football") then
            held_ball   = child:FindFirstChild("Football")
            holder_char = child
            ball_status = child.Name .. " (held)"
            return
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

local _last_refresh = 0
cheat.register("onUpdate", function()
    local t = utility.GetTickCount() / 1000
    if t - _last_refresh < 0.1 then return end
    _last_refresh = t
    refresh_ball_refs()
    refresh_local_char()
end)

cheat.register("onUpdate", function()
    if held_ball  and not held_ball.Parent  then held_ball = nil; holder_char = nil end
    if free_ball  and not free_ball.Parent  then free_ball  = nil end
    if world_ball and not world_ball.Parent then world_ball = nil end
    if local_char and not local_char.Parent then local_char = nil end
end)

-- [Goal refs]

local goal_boxes = {}

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

cheat.register("onSlowUpdate", refresh_goal_refs)

-- [Helpers]

local function now_sec()
    return utility.GetTickCount() / 1000
end

local hk_prev = {}
local function hotkey_clicked(label)
    local now  = ui.getValue(TAB, TP, label)
    local edge = now and not (hk_prev[label] or false)
    hk_prev[label] = now
    return edge
end

local function front_target(hrp)
    return hrp.Position + Vector3.new(0, OFF_UP, 0)
end

local function picker_to_color3(t)
    if not t then return COLOR_WHITE end
    return Color3.fromRGB(t.r or 255, t.g or 255, t.b or 255)
end

local info_speed     = 0
local info_dist      = "--"
local info_tp_status = "Teleport disabled"

cheat.register("onUpdate", function()
    local ball = world_ball
              or (held_ball and held_ball.Parent and held_ball)
              or (free_ball and free_ball.Parent and free_ball)
    local hrp = local_char and local_char:FindFirstChild("HumanoidRootPart")
    if ball and hrp then
        info_dist = string.format("%.1f studs", (ball.Position - hrp.Position).Magnitude)
    else
        info_dist = "--"
    end
end)

-- [Conditional visibility]

cheat.register("onUpdate", function()
    local tp_on    = ui.getValue(TAB, TP, "Teleport Enabled")
    local mode     = ui.getValue(TAB, TP, "TP Mode")
    local is_pull  = mode == 0
    local is_ptb   = mode == 2
    local is_tween = is_ptb and ui.getValue(TAB, TP, "Travel Mode") == 1
    local retry_on = is_ptb and ui.getValue(TAB, TP, "Retry on Miss")
    local auto_g   = tp_on and ui.getValue(TAB, TP, "Auto Goal")

    local spd_on  = ui.getValue(TAB, SPD, "Speed Enabled")
    local cap_on  = spd_on and ui.getValue(TAB, SPD, "Enable Speed Cap")
    local arc_on  = ui.getValue(TAB, SPD, "Ball Arc")

    ui.SetVisibility(TAB, SPD, "Speed Multiplier", spd_on)
    ui.SetVisibility(TAB, SPD, "Smoothing",        spd_on)
    ui.SetVisibility(TAB, SPD, "Enable Speed Cap", spd_on)
    ui.SetVisibility(TAB, SPD, "Max Speed Cap",    cap_on)
    ui.SetVisibility(TAB, SPD, "Arc Level",        arc_on)

    ui.SetVisibility(TAB, TP, "Teleport Key",      tp_on)
    ui.SetVisibility(TAB, TP, "TP Mode",           tp_on)
    ui.SetVisibility(TAB, TP, "Travel Mode",       tp_on and is_ptb)
    ui.SetVisibility(TAB, TP, "Tween Time (sec)",  tp_on and is_tween)
    ui.SetVisibility(TAB, TP, "Return Time (sec)", tp_on and is_tween)
    ui.SetVisibility(TAB, TP, "Dwell Time (sec)",  tp_on and is_ptb and not is_tween)
    ui.SetVisibility(TAB, TP, "Steal Dwell (sec)", tp_on and is_ptb and not is_tween)
    ui.SetVisibility(TAB, TP, "Retry on Miss",     tp_on and is_ptb)
    ui.SetVisibility(TAB, TP, "Max Retries",       tp_on and is_ptb and retry_on)
    ui.SetVisibility(TAB, TP, "Preserve Momentum", tp_on and is_pull)
    ui.SetVisibility(TAB, TP, "Auto Goal",         tp_on)
    ui.SetVisibility(TAB, TP, "Auto Goal Key",     auto_g)
    ui.SetVisibility(TAB, TP, "Goal Target",       auto_g)

    local ball_esp  = ui.getValue(TAB, VIS, "Ball ESP")
    local ball_fill = ball_esp and ui.getValue(TAB, VIS, "Ball Fill")
    local goal_esp  = ui.getValue(TAB, VIS, "Goal ESP")
    local goal_fill = goal_esp and ui.getValue(TAB, VIS, "Goal Fill")

    ui.SetVisibility(TAB, VIS, "Ball Color",      ball_esp)
    ui.SetVisibility(TAB, VIS, "Ball ESP Text",   ball_esp)
    ui.SetVisibility(TAB, VIS, "Ball Fill",       ball_esp)
    ui.SetVisibility(TAB, VIS, "Ball Fill Color", ball_fill)
    ui.SetVisibility(TAB, VIS, "Home Color",      goal_esp)
    ui.SetVisibility(TAB, VIS, "Away Color",      goal_esp)
    ui.SetVisibility(TAB, VIS, "Goal ESP Text",   goal_esp)
    ui.SetVisibility(TAB, VIS, "Goal Fill",       goal_esp)
    ui.SetVisibility(TAB, VIS, "Home Fill Color", goal_fill)
    ui.SetVisibility(TAB, VIS, "Away Fill Color", goal_fill)
end)

-- [Speed logic]

cheat.register("onUpdate", function()
    if not ui.getValue(TAB, SPD, "Speed Enabled") then return end

    local multiplier = ui.getValue(TAB, SPD, "Speed Multiplier")
    local smoothing  = ui.getValue(TAB, SPD, "Smoothing")
    local cap        = ui.getValue(TAB, SPD, "Enable Speed Cap")
    local max_speed  = ui.getValue(TAB, SPD, "Max Speed Cap")

    local target = (held_ball and held_ball.Parent and held_ball)
                or (free_ball and free_ball.Parent and free_ball)
    if not target then return end

    local ok, vel = pcall(function() return target.Velocity end)
    if not ok or not vel then return end
    if vel.Magnitude < 0.1 then return end

    local boosted = vel * multiplier
    if smoothing > 0 then
        boosted = prev_vel:Lerp(boosted, 1 - smoothing)
    end
    if cap and boosted.Magnitude > max_speed then
        boosted = boosted.Unit * max_speed
    end

    pcall(function() target.Velocity = boosted end)
    prev_vel = boosted
end)

-- [Arc logic]

local flat_lock_y = nil

cheat.register("onUpdate", function()
    if not ui.getValue(TAB, SPD, "Ball Arc") then flat_lock_y = nil; return end
    local arc = ui.getValue(TAB, SPD, "Arc Level")

    local target = (held_ball and held_ball.Parent and held_ball)
                or (free_ball and free_ball.Parent and free_ball)
    if not target then flat_lock_y = nil; return end

    local ok, vel = pcall(function() return target.Velocity end)
    if not ok or not vel then return end

    local horiz = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
    if horiz < 0.1 then flat_lock_y = nil; return end

    pcall(function() target.Velocity = Vector3.new(vel.X, vel.Y * arc, vel.Z) end)

    if arc <= 0.0 then
        if not flat_lock_y then
            local ok2, pos = pcall(function() return target.Position end)
            flat_lock_y = ok2 and pos and pos.Y or nil
        end
        if flat_lock_y then
            pcall(function()
                local pos = target.Position
                if math.abs(pos.Y - flat_lock_y) > 0.5 then
                    target.Position = Vector3.new(pos.X, flat_lock_y, pos.Z)
                end
            end)
        end
    else
        flat_lock_y = nil
    end
end)

-- [Teleport / Ball Control logic]

local glue_active        = false
local auto_goal_active   = false
local ptb_phase          = "idle"
local ptb_return_pos     = nil
local ptb_dwell_start    = 0
local ptb_retries        = 0
local tween_to_phase     = "at_ball"
local tween_start_pos    = nil
local tween_start_time   = 0
local ret_tween_start      = nil
local ret_tween_start_time = 0
local ret_use_tween        = false

cheat.register("onUpdate", function()
    if not ui.getValue(TAB, TP, "Teleport Enabled") then
        if ptb_phase == "stealing" then keyboard.Release("e") end
        glue_active        = false
        ptb_phase          = "idle"
        ptb_retries        = 0
        ptb_return_pos     = nil
        tween_start_pos    = nil
        ret_tween_start    = nil
        ret_use_tween      = false
        info_tp_status     = "Teleport disabled"
        return
    end

    local hrp = local_char and local_char:FindFirstChild("HumanoidRootPart")
    if not hrp then info_tp_status = "Char not found"; return end

    if ptb_phase == "returning" then
        if ret_use_tween and ret_tween_start then
            local ret_dur  = ui.getValue(TAB, TP, "Return Time (sec)")
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
            ret_use_tween        = ui.getValue(TAB, TP, "Travel Mode") == 1
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

    local mode     = ui.getValue(TAB, TP, "TP Mode")
    local dwell    = ui.getValue(TAB, TP, "Dwell Time (sec)")
    local preserve = ui.getValue(TAB, TP, "Preserve Momentum")
    local clicked  = hotkey_clicked("Teleport Key")

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
        if clicked then glue_active = not glue_active end
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
        local use_tween = ui.getValue(TAB, TP, "Travel Mode") == 1

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

        elseif ptb_phase == "tweening" then
            local elapsed  = now_sec() - tween_start_time
            local tw_dur   = ui.getValue(TAB, TP, "Tween Time (sec)")
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
            local steal_dwell = ui.getValue(TAB, TP, "Steal Dwell (sec)")
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
            if local_char and local_char:FindFirstChild("Football") then
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
            if use_tween or elapsed >= dwell then
                local retry_on = ui.getValue(TAB, TP, "Retry on Miss")
                local max_r    = ui.getValue(TAB, TP, "Max Retries")
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

-- [Visuals paint]

local function get_part_hull(part)
    local corners = draw.GetPartCorners(part)
    if not corners then return nil end
    local n = 0
    for _, wp in ipairs(corners) do
        local sx, sy, on = utility.WorldToScreen(wp)
        if on then
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
    local font = VIS_FONTS[(ui.getValue(TAB, VIS, "Font") or 0) + 1] or "Tahoma"

    local display = world_ball
                 or (held_ball and held_ball.Parent and held_ball)
                 or (free_ball and free_ball.Parent and free_ball)
    if display then
        local ok, v = pcall(function() return display.Velocity.Magnitude end)
        info_speed = ok and v and math.floor(v * 10) / 10 or 0
    else
        info_speed = 0
    end

    if ui.getValue(TAB, VIS, "Info Display") then
        local _sw, sh = cheat.GetWindowSize()
        local x, y = 10, sh - 85
        local gg_target_idx   = ui.getValue(TAB, TP, "Goal Target")
        local gg_target_names = {"Auto", "Home", "Away"}
        local gg_label = auto_goal_active
            and ("On -> " .. (gg_target_names[gg_target_idx + 1] or "?"))
            or "Off"
        draw.TextOutlined("BL:R", x, y, COLOR_BLUE, font, 255)
        draw.TextOutlined("Speed:  " .. tostring(info_speed) .. " (" .. ball_status .. ")", x, y + 15, COLOR_WHITE, font, 255)
        draw.TextOutlined("Dist:   " .. info_dist,     x, y + 30, COLOR_WHITE, font, 255)
        draw.TextOutlined("TP:     " .. info_tp_status, x, y + 45, COLOR_WHITE, font, 255)
        draw.TextOutlined("Goal:   " .. gg_label,        x, y + 60, COLOR_WHITE, font, 255)
    end

    local ball_esp_on  = ui.getValue(TAB, VIS, "Ball ESP")
    local ball_fill_on = ui.getValue(TAB, VIS, "Ball Fill")
    if ball_esp_on or ball_fill_on then
        local ball_color      = picker_to_color3(ui.getValue(TAB, VIS, "Ball Color"))
        local ball_fill_t     = ui.getValue(TAB, VIS, "Ball Fill Color") or {}
        local ball_fill_color = picker_to_color3(ball_fill_t)
        local ball_fill_alpha = ball_fill_t.a or 60

        local is_local_holding = holder_char and local_char and holder_char.Name == local_char.Name
        local ball_part
        if is_local_holding then
            -- local player has the ball
        elseif holder_char and holder_char.Parent then
            ball_part = holder_char:FindFirstChild("Hitbox") or holder_char:FindFirstChild("HumanoidRootPart")
        else
            ball_part = world_ball or (free_ball and free_ball.Parent and free_ball)
        end

        if ball_part then
            local hull = get_part_hull(ball_part)
            if ball_fill_on then draw_hull_fill(hull, ball_fill_color, ball_fill_alpha) end
            if ball_esp_on  then draw_hull_box(hull, ball_color, 255) end

            if ball_esp_on and ui.getValue(TAB, VIS, "Ball ESP Text") then
                local ok, sx, sy, on = pcall(function()
                    return utility.WorldToScreen(ball_part.Position + Vector3.new(0, 4, 0))
                end)
                if ok and on then
                    local hrp = local_char and local_char:FindFirstChild("HumanoidRootPart")
                    if holder_char and holder_char.Parent then
                        draw.TextOutlined(holder_char.Name .. " [ball]", sx, sy, ball_color, font, 255)
                    elseif hrp then
                        local ok2, dist = pcall(function() return (ball_part.Position - hrp.Position).Magnitude end)
                        local label = ok2 and string.format("Ball [%.0f]", dist) or "Ball"
                        draw.TextOutlined(label, sx, sy, ball_color, font, 255)
                    else
                        draw.TextOutlined("Ball", sx, sy, ball_color, font, 255)
                    end
                end
            end
        end
    end

    local goal_esp_on  = ui.getValue(TAB, VIS, "Goal ESP")
    local goal_fill_on = ui.getValue(TAB, VIS, "Goal Fill")
    if goal_esp_on or goal_fill_on then
        local home_color    = picker_to_color3(ui.getValue(TAB, VIS, "Home Color"))
        local away_color    = picker_to_color3(ui.getValue(TAB, VIS, "Away Color"))
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
                local fill_col = is_home and home_fill_col or away_fill_col
                local fill_a   = is_home and (home_fill_t.a or 40) or (away_fill_t.a or 40)
                local hull = get_part_hull(gb)
                if goal_fill_on then draw_hull_fill(hull, fill_col, fill_a) end
                if goal_esp_on  then draw_hull_box(hull, col, 200) end
                if goal_esp_on and goal_text_on then
                    local ok, sx, sy, on = pcall(function()
                        return utility.WorldToScreen(gb.Position + Vector3.new(0, 8, 0))
                    end)
                    if ok and on then
                        draw.TextOutlined(entry.name, sx, sy, col, font, 255)
                    end
                end
            end
        end
    end
end)

-- [Auto Goal logic]

cheat.register("onUpdate", function()
    if not ui.getValue(TAB, TP, "Auto Goal") then
        auto_goal_active = false
        return
    end

    if hotkey_clicked("Auto Goal Key") then
        auto_goal_active = not auto_goal_active
    end

    if not auto_goal_active then return end

    local ball = world_ball
              or (held_ball and held_ball.Parent and held_ball)
              or (free_ball and free_ball.Parent and free_ball)
    if not ball then return end

    local target_idx = ui.getValue(TAB, TP, "Goal Target")

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

-- [Cleanup]

cheat.register("shutdown", function()
    free_ball          = nil
    held_ball          = nil
    world_ball         = nil
    holder_char        = nil
    local_char         = nil
    goal_boxes         = {}
    glue_active        = false
    auto_goal_active   = false
    ptb_phase          = "idle"
    ptb_retries        = 0
    ptb_return_pos     = nil
    tween_start_pos    = nil
    ret_tween_start    = nil
    ret_use_tween      = false
    flat_lock_y        = nil
    keyboard.Release("e")
end)
