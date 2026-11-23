-- Fight controls. Every arena tick a controller gives the HAR its stick as
-- a numpad digit in screen terms (8 up, 6 right, 3 down-right... 5 none)
-- and whether punch / kick were pressed since the last tick. Presses are
-- latched per frame, since a tick is longer than a frame.
--
-- Default keys, as OpenOMF's:
--   player 1  arrows, Home/PgUp/End/PgDn diagonals, Enter punch, Right Shift kick
--             (and any game pad: d-pad / left stick, A punch, B kick)
--   player 2  W A D X, Q E Z C diagonals, Left Ctrl punch, Left Shift kick

local M = {}

M.KEYS = {
    {
        up = { "up", "pad_up" }, down = { "down", "pad_down" }, left = { "left", "pad_left" },
        right = { "right", "pad_right" },
        up_left = { "home" }, up_right = { "page up" }, down_left = { "end" }, down_right = { "page down" },
        punch = { "return", "pad_a", "pad_x" }, kick = { "right shift", "pad_b", "pad_y" },
    },
    {
        up = { "w" }, down = { "x" }, left = { "a" }, right = { "d" },
        up_left = { "q" }, up_right = { "e" }, down_left = { "z" }, down_right = { "c" },
        punch = { "left ctrl" }, kick = { "left shift" },
    },
}

local function any(list, fn)
    for _, k in ipairs(list) do if fn(k) then return true end end
    return false
end

local Keyboard = {}
Keyboard.__index = Keyboard

function M.keyboard(player)
    return setmetatable({ keys = M.KEYS[player], punch = false, kick = false }, Keyboard)
end

--- Called every frame: remember presses until the next tick.
function Keyboard:poll()
    local k = self.keys
    if any(k.punch, input.pressed) then self.punch = true end
    if any(k.kick, input.pressed) then self.kick = true end
end

local DIRS = { [-1] = { [-1] = "7", [0] = "4", [1] = "1" }, [0] = { [-1] = "8", [0] = "5", [1] = "2" },
               [1] = { [-1] = "9", [0] = "6", [1] = "3" } }
M.DIRS = DIRS

--- Called every tick: dir, punch, kick.
function Keyboard:take()
    local k, d = self.keys, input.down
    local x, y = 0, 0
    if any(k.left, d) then x = x - 1 end
    if any(k.right, d) then x = x + 1 end
    if any(k.up, d) then y = y - 1 end
    if any(k.down, d) then y = y + 1 end
    if any(k.up_left, d) then x, y = -1, -1 end
    if any(k.up_right, d) then x, y = 1, -1 end
    if any(k.down_left, d) then x, y = -1, 1 end
    if any(k.down_right, d) then x, y = 1, 1 end
    local p, kk = self.punch, self.kick
    self.punch, self.kick = false, false
    return DIRS[x][y], p, kk
end

--- A scripted controller (tests, demos): a list of {dir, punch, kick} per tick.
function M.scripted(steps)
    local c = { i = 0 }
    function c:poll() end
    function c:take()
        self.i = self.i + 1
        local s = steps[self.i] or steps[#steps] or { "5" }
        return s[1] or "5", s[2] or false, s[3] or false
    end
    return c
end

return M
