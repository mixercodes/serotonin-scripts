-- ball_manipulation.lua

local TAB  = "ballmanip_tab"
local CIRC = "ballmanip_circ"
local BC   = "ballmanip_bc"

local pi  = math.pi
local pi2 = pi * 2
local sin, cos = math.sin, math.cos

ui.newTab(TAB, "Ball Manip")

-- Orbit container
ui.NewContainer(TAB, CIRC, "Orbit", { autosize = true })
ui.NewCheckbox(TAB, CIRC, "Orbit Enabled")
ui.newHotkey(TAB, CIRC, "Orbit Key", true)
ui.newSliderFloat(TAB, CIRC, "Radius",      0.5, 30.0)
ui.newSliderFloat(TAB, CIRC, "Height",     -5.0, 100.0)
ui.newSliderFloat(TAB, CIRC, "Speed (rps)", 0.1, 10.0)

ui.setValue(TAB, CIRC, "Orbit Enabled", false)
ui.setValue(TAB, CIRC, "Radius",        3.5)
ui.setValue(TAB, CIRC, "Height",        10.0)
ui.setValue(TAB, CIRC, "Speed (rps)",   0.5)

-- Ball Control container
ui.NewContainer(TAB, BC, "Ball Control", { autosize = true, next = true })
ui.NewCheckbox(TAB, BC, "BC Enabled")
ui.newHotkey(TAB, BC, "BC Key", true)
ui.newSliderFloat(TAB, BC, "Move Speed", 1.0, 100.0)
ui.NewCheckbox(TAB, BC, "Freeze Player")

ui.setValue(TAB, BC, "BC Enabled",    false)
ui.setValue(TAB, BC, "Move Speed",    2.0)
ui.setValue(TAB, BC, "Freeze Player", true)

-- State

local orbit_active = false
local orbit_angle  = 0.0
local orbit_last   = utility.GetTickCount()

local bc_active = false
local bc_pos_x, bc_pos_y, bc_pos_z = 0, 0, 0

-- frozen player position (set on BC activation, written every frame while active)
local frozen_x, frozen_y, frozen_z = 0, 0, 0

-- camera axes cached from onPaint (WorldToScreen only reflects live camera there)
local cam_fwx, cam_fwz = 0, 1
local cam_rx,  cam_rz  = 1, 0

local hk_prev = {}

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

local function find_ball()
    for _, child in ipairs(game.Workspace:GetChildren()) do
        if child.ClassName == "Model" then
            local fb = child:FindFirstChild("Football")
            if fb then return fb end
        end
    end
    for _, child in ipairs(game.Workspace:GetChildren()) do
        if child.Name == "Football" and (child.ClassName == "MeshPart" or child.ClassName == "Part") then
            return child
        end
    end
    return nil
end

-- Derives camera horizontal forward and right vectors from WorldToScreen projections.
-- When a primary cardinal is behind the camera the opposite is used and negated.
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

    -- forward = right rotated 90 degrees: (-rz, rx)
    return -rz, rx, rx, rz
end

local function bc_init()
    local cam_pos = game.CameraPosition
    if not cam_pos then return end

    local lp = entity.GetLocalPlayer()
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

-- Refresh camera axes every frame (WorldToScreen is only live here)
cheat.register("onPaint", function()
    local fwx, fwz, rx, rz = get_cam_axes()
    if fwx ~= nil then
        cam_fwx, cam_fwz, cam_rx, cam_rz = fwx, fwz, rx, rz
    end
end)

cheat.register("onUpdate", function()

    -- Orbit toggle
    local orb_enabled = ui.getValue(TAB, CIRC, "Orbit Enabled")
    if orb_enabled then
        if hotkey_is_hold("Orbit Key", CIRC) then
            orbit_active = ui.getValue(TAB, CIRC, "Orbit Key") == true
        elseif hotkey_clicked("Orbit Key", CIRC) then
            orbit_active = not orbit_active
        end
    else
        orbit_active = false
    end

    -- Ball Control toggle
    local bc_enabled = ui.getValue(TAB, BC, "BC Enabled")
    local was_bc = bc_active
    if bc_enabled then
        if hotkey_is_hold("BC Key", BC) then
            bc_active = ui.getValue(TAB, BC, "BC Key") == true
        elseif hotkey_clicked("BC Key", BC) then
            bc_active = not bc_active
        end
    else
        bc_active = false
    end

    if bc_active and not was_bc then
        bc_init()
    end

    local ball = find_ball()
    if not ball or not ball.Parent then return end

    if bc_active then
        local dt    = utility.GetDeltaTime()
        local speed = ui.getValue(TAB, BC, "Move Speed")
        local step  = speed * 10 * dt

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

        if ui.getValue(TAB, BC, "Freeze Player") then
            local lp = entity.GetLocalPlayer()
            if lp then
                local char = game.Workspace:FindFirstChild(lp.Name)
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

        local radius = ui.getValue(TAB, CIRC, "Radius")
        local height = ui.getValue(TAB, CIRC, "Height")
        local spd    = ui.getValue(TAB, CIRC, "Speed (rps)")

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

cheat.register("shutdown", function()
    orbit_active = false
    bc_active    = false
end)
