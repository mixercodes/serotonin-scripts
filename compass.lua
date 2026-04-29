-- compass.lua
-- Projects cardinal direction markers via WorldToScreen (uses live camera matrix).
-- Draws their labels at the top of the screen based on projected screen X.

local FONT    = "ConsolasBold"
local COLOR   = Color3.fromRGB(255, 220, 60)
local DIM     = Color3.fromRGB(150, 130, 35)
local WHITE   = Color3.fromRGB(255, 255, 255)
local BAR_Y   = 20
local RADIUS  = 300

local CARDINALS = {
    { label = "N", dx =  0, dz = -1 },
    { label = "E", dx =  1, dz =  0 },
    { label = "S", dx =  0, dz =  1 },
    { label = "W", dx = -1, dz =  0 },
}

cheat.register("onPaint", function()
    local cam_pos = game.CameraPosition
    if not cam_pos then return end

    local sw, _sh = cheat.GetWindowSize()
    local cx = sw * 0.5

    -- find which cardinal has screen X closest to centre (= what we're facing)
    local closest_label = nil
    local closest_dist  = math.huge

    for _, c in ipairs(CARDINALS) do
        local wx = cam_pos.X + c.dx * RADIUS
        local wy = cam_pos.Y
        local wz = cam_pos.Z + c.dz * RADIUS

        local sx, _sy, on_screen = utility.WorldToScreen(Vector3.new(wx, wy, wz))
        if on_screen then
            local dist = math.abs(sx - cx)
            if dist < closest_dist then
                closest_dist  = dist
                closest_label = c.label
            end
        end
        c._sx       = on_screen and sx or nil
        c._on_screen = on_screen
    end

    -- draw labels
    for _, c in ipairs(CARDINALS) do
        if c._on_screen then
            local tw, th = draw.GetTextSize(c.label, FONT)
            local tx = c._sx - tw * 0.5
            local is_primary = (c.label == closest_label)
            local col = is_primary and COLOR or DIM

            draw.TextOutlined(c.label, tx, BAR_Y, col, FONT)

            local tick_x = math.floor(c._sx)
            local tick_y = BAR_Y + th + 2
            draw.Line(tick_x, tick_y, tick_x, tick_y + (is_primary and 6 or 3), col, 255)
        end
    end

    -- centre marker
    local dw, _dh = draw.GetTextSize("v", FONT)
    draw.TextOutlined("v", cx - dw * 0.5, BAR_Y - 14, WHITE, FONT)
end)
