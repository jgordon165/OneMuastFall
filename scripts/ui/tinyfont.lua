-- A tiny built-in 3x5 font, for screens that can't count on the game's
-- own fonts (no game data yet, a script error).

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

function M.text(s, x, y, c)
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


--- Splits text into lines of at most `cols` characters.
function M.wrap(s, cols)
    local lines = {}
    for para in (s .. "\n"):gmatch("(.-)\n") do
        while #para > cols do
            lines[#lines + 1] = para:sub(1, cols)
            para = para:sub(cols + 1)
        end
        lines[#lines + 1] = para
    end
    return lines
end

return M
