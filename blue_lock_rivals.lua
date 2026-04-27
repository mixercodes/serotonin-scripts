-- blue_lock_rivals.lua
-- Ball Physics + Ball Teleport + Visuals (ESP + on-screen info)

local KeyOptions = {"f1","f2","f3","f4","f5","f6","q","e","r","t","z","x","c","v","g","mouse5","mouse4"}
local TP_MODES   = {"Ball to Player (pull)", "Ball Control (glue)", "Snap / Auto Steal"}
local VIS_FONTS  = {"Tahoma", "Verdana", "ConsolasBold", "SmallestPixel"}

local TAB = "ballt_tab"
local SPD = "ballt_spd"
local TP  = "ballt_tp"
local VIS = "ballt_vis"

ui.newTab(TAB, "Pitch Control")

-- [Ball Physics container]
ui.NewContainer(TAB, SPD, "Ball Physics", { autosize = true })
ui.NewCheckbox(TAB, SPD, "Speed Enabled")
ui.newSliderFloat(TAB, SPD, "Speed Multiplier", 1.0, 10.0, 2.0)
ui.newSliderFloat(TAB, SPD, "Activation Threshold", 0.5, 20.0, 2.0)
ui.newSliderFloat(TAB, SPD, "Smoothing", 0.0, 1.0, 0.0)
ui.NewCheckbox(TAB, SPD, "Enable Speed Cap")
ui.newSliderFloat(TAB, SPD, "Max Speed Cap", 10.0, 500.0, 150.0)
ui.NewCheckbox(TAB, SPD, "Flat Path")

-- [Teleport container]
ui.NewContainer(TAB, TP, "Ball Teleport", { autosize = true, next = true })
ui.NewCheckbox(TAB, TP, "Teleport Enabled")
ui.newDropdown(TAB, TP, "TP Mode", TP_MODES, 3)
ui.newDropdown(TAB, TP, "Teleport Key", KeyOptions, 11) -- default z
ui.newSliderFloat(TAB, TP, "Offset Forward", 0.0, 10.0, 3.0)
ui.newSliderFloat(TAB, TP, "Offset Up", 0.0, 10.0, 2.0)
ui.newSliderFloat(TAB, TP, "Dwell Time (sec)", 0.0, 5.0, 0.10)
ui.newSliderFloat(TAB, TP, "Steal Dwell (sec)", 0.3, 3.0, 0.6)
ui.NewCheckbox(TAB, TP, "Preserve Momentum")
ui.NewCheckbox(TAB, TP, "Auto Goal")
ui.newDropdown(TAB, TP, "Goal Target", {"Auto (enemy)", "Home", "Away"}, 1)
ui.newDropdown(TAB, TP, "Auto Goal Key", KeyOptions, 15) -- default g

-- [Visuals container]
ui.NewContainer(TAB, VIS, "Visuals", { autosize = true, next = true })
ui.newDropdown(TAB, VIS, "Font", VIS_FONTS, 1)
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

ui.setValue(TAB, SPD, "Speed Enabled", false)
ui.setValue(TAB, SPD, "Enable Speed Cap", false)
ui.setValue(TAB, SPD, "Flat Path", false)
ui.setValue(TAB, TP,  "Teleport Enabled", false)
ui.setValue(TAB, TP,  "Preserve Momentum", true)
ui.setValue(TAB, TP,  "Auto Goal", false)
ui.setValue(TAB, VIS, "Info Display", true)
ui.setValue(TAB, VIS, "Ball ESP", false)
ui.setValue(TAB, VIS, "Ball ESP Text", true)
ui.setValue(TAB, VIS, "Ball Fill", false)
ui.setValue(TAB, VIS, "Goal ESP", false)
ui.setValue(TAB, VIS, "Goal ESP Text", true)
ui.setValue(TAB, VIS, "Goal Fill", false)

-- [Shared state]

local free_ball    = nil
local held_ball    = nil
local world_ball   = nil
local holder_char  = nil
local local_char   = nil   -- cached, refreshed on slowUpdate
local prev_vel     = Vector3.new(0, 0, 0)
local ball_status  = "---"

-- static colors (created once, not per-frame)
local COLOR_WHITE  = Color3.new(1, 1, 1)
local COLOR_YELLOW = Color3.fromRGB(255, 220, 0)

-- reusable screen-point buffer (avoids per-frame table allocation)
local _screen_buf = {}

local function refresh_ball_refs()
    local ball_model = game.Workspace:FindFirstChild("Ball")
    free_ball = ball_model and ball_model:FindFirstChild("RootPart") or nil
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
        ball_status = (ok and spd or 0) > 0.5 and "ball in air" or "ball idle"
    elseif free_ball and free_ball.Parent then
        local ok, spd = pcall(function() return free_ball.Velocity.Magnitude end)
        ball_status = (ok and spd or 0) > 0.5 and "ball in air" or "ball idle"
    else
        ball_status = "no ball"
    end
end

local function refresh_local_char()
    local lp = game.LocalPlayer
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

local key_prev = {}

local function key_clicked(key)
    if key == "mouse4" or key == "mouse5" then
        return mouse.IsClicked(key)
    end
    local now = keyboard.IsPressed(key)
    local edge = now and not (key_prev[key] or false)
    key_prev[key] = now
    return edge
end

local function front_target(hrp, off_fwd, off_up)
    local ok, lv = pcall(function() return hrp.CFrame.LookVector end)
    local fwd = ok and lv or Vector3.new(0, 0, -1)
    return hrp.Position + fwd * off_fwd + Vector3.new(0, off_up, 0)
end

local function picker_to_color3(t)
    if not t then return COLOR_WHITE end
    return Color3.fromRGB(t.r or 255, t.g or 255, t.b or 255)
end

-- [Live info state]

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

-- [Speed logic]

cheat.register("onUpdate", function()
    if not ui.getValue(TAB, SPD, "Speed Enabled") then return end

    local threshold  = ui.getValue(TAB, SPD, "Activation Threshold")
    local multiplier = ui.getValue(TAB, SPD, "Speed Multiplier")
    local smoothing  = ui.getValue(TAB, SPD, "Smoothing")
    local cap        = ui.getValue(TAB, SPD, "Enable Speed Cap")
    local max_speed  = ui.getValue(TAB, SPD, "Max Speed Cap")

    local target = (held_ball and held_ball.Parent and held_ball)
                or (free_ball and free_ball.Parent and free_ball)
    if not target then return end

    local ok, vel = pcall(function() return target.Velocity end)
    if not ok or not vel then return end
    local speed = vel.Magnitude
    if speed < threshold then return end

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

-- [Flat path logic]
-- Cancels Roblox gravity accumulation on the ball by zeroing vel.Y each tick
-- while the ball has meaningful horizontal movement. This keeps it at the height
-- it was at when kicked, travelling in a straight line instead of an arc.
-- Deactivates automatically when horizontal speed drops below threshold so the
-- ball can settle/land normally once it reaches its target.

local flat_lock_y = nil  -- locked Y position; set when the ball gains speed

cheat.register("onUpdate", function()
    if not ui.getValue(TAB, SPD, "Flat Path") then
        flat_lock_y = nil
        return
    end

    local target = (held_ball and held_ball.Parent and held_ball)
                or (free_ball and free_ball.Parent and free_ball)
    if not target then flat_lock_y = nil; return end

    local ok, vel = pcall(function() return target.Velocity end)
    if not ok or not vel then return end

    local horiz = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)

    -- only engage while the ball is genuinely moving horizontally
    local threshold = ui.getValue(TAB, SPD, "Activation Threshold") or 2.0
    if horiz < threshold then
        flat_lock_y = nil
        return
    end

    -- latch the Y position on the first frame we engage
    if not flat_lock_y then
        local ok2, pos = pcall(function() return target.Position end)
        flat_lock_y = ok2 and pos and pos.Y or nil
        if not flat_lock_y then return end
    end

    -- rewrite velocity with Y = 0, keeping horizontal motion untouched
    pcall(function() target.Velocity = Vector3.new(vel.X, 0, vel.Z) end)

    -- also correct position drift (gravity may have moved it a stud already)
    pcall(function()
        local pos = target.Position
        if math.abs(pos.Y - flat_lock_y) > 0.5 then
            target.Position = Vector3.new(pos.X, flat_lock_y, pos.Z)
        end
    end)
end)

-- [Teleport / Ball Control logic]

local glue_active      = false
local auto_goal_active = false
local ptb_phase        = "idle"
local ptb_return_pos   = nil
local ptb_dwell_start  = 0

cheat.register("onUpdate", function()
    if not ui.getValue(TAB, TP, "Teleport Enabled") then
        if ptb_phase == "stealing" then keyboard.Release("e") end
        glue_active    = false
        ptb_phase      = "idle"
        ptb_return_pos = nil
        info_tp_status = "Teleport disabled"
        return
    end

    local ball = world_ball or (free_ball and free_ball.Parent and free_ball)
    local hrp  = local_char and local_char:FindFirstChild("HumanoidRootPart")

    if not ball then info_tp_status = "Ball not found"; return end
    if not hrp  then info_tp_status = "Char not found"; return end

    local key_idx  = ui.getValue(TAB, TP, "Teleport Key") or 11
    local key      = KeyOptions[key_idx + 1] or "z"
    local mode     = ui.getValue(TAB, TP, "TP Mode")
    local off_fwd  = ui.getValue(TAB, TP, "Offset Forward")
    local off_up   = ui.getValue(TAB, TP, "Offset Up")
    local dwell    = ui.getValue(TAB, TP, "Dwell Time (sec)")
    local preserve = ui.getValue(TAB, TP, "Preserve Momentum")
    local clicked  = key_clicked(key)

    if mode == 0 then
        if clicked then
            local tgt = front_target(hrp, off_fwd, off_up)
            local saved_vel = ball.Velocity
            local dist = (ball.Position - hrp.Position).Magnitude
            local ok, err = pcall(function()
                ball.Position = tgt
                ball.Velocity = preserve and saved_vel or Vector3.new(0, 0, 0)
            end)
            info_tp_status = ok and ("Pulled " .. string.format("%.0f", dist) .. "st")
                                or ("TP fail: " .. tostring(err))
        else
            info_tp_status = "[" .. key .. "] pull ball"
        end

    elseif mode == 1 then
        if clicked then glue_active = not glue_active end
        if glue_active then
            local ok = pcall(function()
                ball.Position = front_target(hrp, off_fwd, off_up)
                ball.Velocity = Vector3.new(0, 0, 0)
            end)
            info_tp_status = ok and "GLUE ON" or "Glue fail"
        else
            info_tp_status = "[" .. key .. "] glue ball"
        end

    else
        -- find enemy holder for steal branch
        local is_local_holding = holder_char and local_char and holder_char.Name == local_char.Name
        local enemy_hrp = nil
        if holder_char and holder_char.Parent and not is_local_holding then
            enemy_hrp = holder_char:FindFirstChild("HumanoidRootPart")
        end

        if ptb_phase == "idle" then
            if clicked then
                ptb_return_pos = hrp.Position
                if enemy_hrp then
                    -- steal: teleport onto holder, dwell pressing e
                    local ok, err = pcall(function() hrp.Position = enemy_hrp.Position end)
                    if ok then
                        ptb_phase       = "stealing"
                        ptb_dwell_start = now_sec()
                        info_tp_status  = "Stealing..."
                    else
                        info_tp_status = "Steal fail: " .. tostring(err)
                        ptb_return_pos = nil
                    end
                else
                    -- no holder: snap to ball
                    local dir = ball.Position - hrp.Position
                    local tgt = ball.Position + Vector3.new(0, off_up, 0)
                    if dir.Magnitude > 0.1 then
                        local flat = Vector3.new(dir.X, 0, dir.Z)
                        if flat.Magnitude > 0.1 then
                            tgt = ball.Position - flat.Unit * off_fwd + Vector3.new(0, off_up, 0)
                        end
                    end
                    local ok, err = pcall(function() hrp.Position = tgt end)
                    if ok then
                        ptb_phase       = "at_ball"
                        ptb_dwell_start = now_sec()
                        info_tp_status  = "At ball..."
                    else
                        info_tp_status = "TP fail: " .. tostring(err)
                        ptb_return_pos = nil
                    end
                end
            else
                if enemy_hrp then
                    local ok, dist = pcall(function() return (hrp.Position - enemy_hrp.Position).Magnitude end)
                    info_tp_status = ok and string.format("[%s] steal (%.0fst)", key, dist) or "[" .. key .. "] steal"
                else
                    info_tp_status = "[" .. key .. "] snap to ball"
                end
            end

        elseif ptb_phase == "stealing" then
            if enemy_hrp and enemy_hrp.Parent then
                pcall(function() hrp.Position = enemy_hrp.Position end)
            end
            keyboard.Press("e")
            local steal_dwell = ui.getValue(TAB, TP, "Steal Dwell (sec)") or 0.6
            local elapsed = now_sec() - ptb_dwell_start
            if elapsed >= steal_dwell then
                keyboard.Release("e")
                pcall(function() hrp.Position = ptb_return_pos end)
                ptb_phase      = "idle"
                ptb_return_pos = nil
                info_tp_status = "Steal done"
            else
                info_tp_status = string.format("Stealing %.1fs", steal_dwell - elapsed)
            end

        elseif ptb_phase == "at_ball" then
            local dir = ball.Position - hrp.Position
            local tgt = ball.Position + Vector3.new(0, off_up, 0)
            if dir.Magnitude > 0.1 then
                local flat = Vector3.new(dir.X, 0, dir.Z)
                if flat.Magnitude > 0.1 then
                    tgt = ball.Position - flat.Unit * off_fwd + Vector3.new(0, off_up, 0)
                end
            end
            pcall(function() hrp.Position = tgt end)
            local elapsed = now_sec() - ptb_dwell_start
            if elapsed >= dwell then
                pcall(function() hrp.Position = ptb_return_pos end)
                info_tp_status = "Returned"
                ptb_phase      = "idle"
                ptb_return_pos = nil
            else
                info_tp_status = string.format("Returning %.1fs", dwell - elapsed)
            end
        end
    end
end)

-- [Visuals paint]

-- hull computed once per part; shared by box and fill draws
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
    -- pass only the filled slice (ComputeConvexHull reads up to n entries)
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

    -- ball speed (read once for info display)
    local display = world_ball
                 or (held_ball and held_ball.Parent and held_ball)
                 or (free_ball and free_ball.Parent and free_ball)
    if display then
        local ok, v = pcall(function() return display.Velocity.Magnitude end)
        info_speed = ok and v and math.floor(v * 10) / 10 or 0
    else
        info_speed = 0
    end

    -- Info Display
    if ui.getValue(TAB, VIS, "Info Display") then
        local _sw, sh = cheat.GetWindowSize()
        local x, y = 10, sh - 85
        local gg_target_idx = ui.getValue(TAB, TP, "Goal Target") or 0
        local gg_target_names = {"Auto", "Home", "Away"}
        local gg_label = auto_goal_active
            and ("ON -> " .. (gg_target_names[gg_target_idx + 1] or "?"))
            or "OFF"
        draw.TextOutlined("Pitch Control", x, y,      COLOR_YELLOW, font, 255)
        draw.TextOutlined("Speed:  " .. tostring(info_speed) .. " (" .. ball_status .. ")", x, y + 15, COLOR_WHITE, font, 255)
        draw.TextOutlined("Dist:   " .. info_dist,      x, y + 30, COLOR_WHITE, font, 255)
        draw.TextOutlined("TP:     " .. info_tp_status,  x, y + 45, COLOR_WHITE, font, 255)
        draw.TextOutlined("Goal:   " .. gg_label,         x, y + 60, COLOR_WHITE, font, 255)
    end

    -- Ball ESP / Fill
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
            -- local player has the ball, nothing to display
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

    -- Goal ESP / Fill
    local goal_esp_on  = ui.getValue(TAB, VIS, "Goal ESP")
    local goal_fill_on = ui.getValue(TAB, VIS, "Goal Fill")
    if goal_esp_on or goal_fill_on then
        local home_color    = picker_to_color3(ui.getValue(TAB, VIS, "Home Color"))
        local away_color    = picker_to_color3(ui.getValue(TAB, VIS, "Away Color"))
        local home_fill_t   = ui.getValue(TAB, VIS, "Home Fill Color") or {}
        local away_fill_t   = ui.getValue(TAB, VIS, "Away Fill Color") or {}
        local home_fill_col = picker_to_color3(home_fill_t)
        local away_fill_col = picker_to_color3(away_fill_t)

        local goal_text_on = ui.getValue(TAB, VIS, "Goal ESP Text")
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

-- 0=Auto, 1=Home, 2=Away (matches dropdown order)
local GOAL_TARGETS = {"Auto (enemy)", "Home", "Away"}

cheat.register("onUpdate", function()
    if not ui.getValue(TAB, TP, "Auto Goal") then
        auto_goal_active = false
        return
    end

    local gg_key_idx = ui.getValue(TAB, TP, "Auto Goal Key") or 11
    local gg_key     = KeyOptions[gg_key_idx + 1] or "g"
    if key_clicked(gg_key) then
        auto_goal_active = not auto_goal_active
    end

    if not auto_goal_active then return end

    local ball = world_ball
              or (held_ball and held_ball.Parent and held_ball)
              or (free_ball and free_ball.Parent and free_ball)
    if not ball then return end

    local target_idx = ui.getValue(TAB, TP, "Goal Target") or 0
    local target_name
    if target_idx == 0 then
        local ok, team = pcall(function() return game.LocalPlayer.Team end)
        local my_team = ok and tostring(team) or ""
        target_name = (my_team == "Home") and "Home" or "Away"
    else
        target_name = GOAL_TARGETS[target_idx + 1]
    end

    local goals     = game.Workspace:FindFirstChild("Goals")
    local goal_part = goals and goals:FindFirstChild(target_name)
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
    free_ball      = nil
    held_ball      = nil
    world_ball     = nil
    holder_char    = nil
    local_char     = nil
    goal_boxes     = {}
    glue_active      = false
    auto_goal_active = false
    ptb_phase        = "idle"
    keyboard.Release("e")
    ptb_return_pos = nil
    flat_lock_y    = nil
end)
