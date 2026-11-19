-- Shown when the game folder is missing or incomplete. The game's own fonts
-- are in that folder, so this screen draws with a tiny built-in 3x5 font.

local M = {}

-- 3x5 glyphs, rows top to bottom, 3 bits each (4 = left column).
local G = {
    A={2,5,7,5,5}, B={6,5,6,5,6}, C={3,4,4,4,3}, D={6,5,5,5,6}, E={7,4,6,4,7}, F={7,4,6,4,4},
    G={3,4,5,5,3}, H={5,5,7,5,5}, I={7,2,2,2,7}, J={1,1,1,5,2}, K={5,5,6,5,5}, L={4,4,4,4,7},
    M={5,7,7,5,5}, N={6,5,5,5,5}, O={2,5,5,5,2}, P={6,5,6,4,4}, Q={2,5,5,6,3}, R={6,5,6,5,5},
    S={3,4,2,1,6}, T={7,2,2,2,2}, U={5,5,5,5,7}, V={5,5,5,5,2}, W={5,5,7,7,5}, X={5,5,2,5,5},
    Y={5,5,2,2,2}, Z={7,1,2,4,7},
    ["0"]={7,5,5,5,7}, ["1"]={2,6,2,2,7}, ["2"]={6,1,2,4,7}, ["3"]={6,1,2,1,6}, ["4"]={5,5,7,1,1},
    ["5"]={7,4,6,1,6}, ["6"]={3,4,7,5,7}, ["7"]={7,1,1,2,2}, ["8"]={7,5,7,5,7}, ["9"]={7,5,7,1,6},
    ["."]={0,0,0,0,2}, [":"]={0,2,0,2,0}, ["-"]={0,0,7,0,0}, ["/"]={1,1,2,4,4}, ["\\"]={4,4,2,1,1},
    ["_"]={0,0,0,0,7}, ["("]={1,2,2,2,1}, [")"]={4,2,2,2,4}, ["'"]={2,2,0,0,0}, [","]={0,0,0,2,4},
    ["<"]={1,2,4,2,1}, [">"]={4,2,1,2,4}, ["!"]={2,2,2,0,2}, ["?"]={6,1,2,0,2},
}

local function text(s, x, y, c)
    s = s:upper()
    for i = 1, #s do
        local g = G[s:sub(i, i)]
        if g then
            for row = 1, 5 do
                for col = 0, 2 do
                    if g[row] & (4 >> col) ~= 0 then gfx.pset(x + col, y + row - 1, c) end
                end
            end
        end
        x = x + 4
    end
end

function M:enter(report)
    self.report = report or { missing = {} }
    gfx.set_base(string.rep("\0\0\0", 256))
    gfx.base_color(1, 255, 255, 255)
    gfx.base_color(2, 255, 200, 60)
    gfx.base_color(3, 140, 140, 140)
    gfx.reset_palette()
end

function M:update()
    if input.pressed("escape", "return") then sys.quit() end
end

function M:draw()
    gfx.clear(0)
    local y = 20
    text("ONE MUST FALL 2097", 20, y, 2); y = y + 12
    text("THE GAME FILES WERE NOT FOUND IN:", 20, y, 1); y = y + 8
    local p = sys.data_path
    while #p > 0 do text(p:sub(1, 70), 20, y, 3); p = p:sub(71); y = y + 7 end
    y = y + 6
    if #self.report.missing > 0 then
        text("MISSING: " .. table.concat(self.report.missing, " ", 1, math.min(8, #self.report.missing)), 20, y, 1)
        y = y + 12
    end
    text("RUN WITH --DATA <YOUR OMF2097 FOLDER>", 20, y, 1); y = y + 8
    text("(THE ONE WITH FILE0001.EXE, INTRO.BK, FIGHTR0.AF ...)", 20, y, 3); y = y + 8
    text("ONE MUST FALL 2097 IS FREEWARE: SEE README.MD", 20, y, 3); y = y + 16
    text("ESC QUITS", 20, y, 2)
end

return M
