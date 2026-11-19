-- The game's menu look: a panel that darkens the scene under it through the
-- BK's remap table 4, a grid of dark blue lines and a blue border, with the
-- items in the big font (GRAPHCHR) in green, the selected one pulsing.
-- Colours and layout follow OpenOMF's gui (menu_background.c, button.c).

local M = {}

M.COLOR_LINE, M.COLOR_BORDER = 252, 251
M.COLOR_ACTIVE, M.COLOR_INACTIVE, M.COLOR_DISABLED = 255, 254, 250

-- The selected item's colour cycles through these (6-bit), one step a tick.
local PULSE = { {0,30,0}, {2,34,2}, {5,38,5}, {7,42,7}, {10,46,10}, {12,50,12}, {15,54,15}, {17,60,17}, {20,63,20} }
local function c6(v) return (v << 2) | ((v & 0x30) >> 4) end

function M.pulse(tick)
    local i = tick % 16
    if i > 8 then i = 16 - i end
    local c = PULSE[i + 1]
    gfx.base_color(255, c6(c[1]), c6(c[2]), c6(c[3]))
end

function M.panel(bk, x, y, w, h)
    local remap = bk and bk.remaps[0] and bk.remaps[0][4]
    if remap then gfx.remap_rect(x, y, w, h, remap) end
    for lx = x + 5, x + w - 1, 8 do gfx.line(lx, y, lx, y + h - 1, M.COLOR_LINE) end
    for ly = y + 5, y + h - 1, 8 do gfx.line(x, ly, x + w - 1, ly, M.COLOR_LINE) end
    gfx.rect(x, y, w, h, M.COLOR_BORDER)
end

-- A vertical list of items centred in a panel.
-- items: { {label=, action=fn, disabled=bool} }
function M.new(items, x, y, w, h)
    return { items = items, x = x, y = y, w = w, h = h, sel = 1, spacing = 11, top = 6 }
end

function M.update(m)
    local n = #m.items
    local function step(d)
        for _ = 1, n do
            m.sel = (m.sel - 1 + d) % n + 1
            if not m.items[m.sel].disabled then return end
        end
    end
    if input.pressed("up", "pad_up") then step(-1) end
    if input.pressed("down", "pad_down") then step(1) end
    if input.pressed("return", "space", "pad_a", "pad_start") then
        local it = m.items[m.sel]
        if it and not it.disabled and it.action then it.action(it) end
    end
end

function M.draw(m, bk)
    M.panel(bk, m.x, m.y, m.w, m.h)
    for i, it in ipairs(m.items) do
        local label = it.label
        local tw = gfx.text_width(label, 0)
        local tx = m.x + (m.w - tw) // 2
        local ty = m.y + m.top + (i - 1) * m.spacing
        local c = it.disabled and M.COLOR_DISABLED or (i == m.sel and M.COLOR_ACTIVE or M.COLOR_INACTIVE)
        gfx.text(label, tx, ty, c, 0)
    end
end

return M
