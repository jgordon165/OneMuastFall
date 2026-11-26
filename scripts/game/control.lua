-- Fight controls. Every arena tick a controller gives the HAR its stick as
-- a numpad digit in screen terms (8 up, 6 right, 3 down-right... 5 none)
-- and whether punch / kick were pressed since the last tick. Presses are
-- latched per frame, since a tick is longer than a frame, and so are the
-- stick positions passed through on the way (a quarter circle can take less
-- than a tick).
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
    return setmetatable({ keys = M.KEYS[player], punch = false, kick = false, seen = {} }, Keyboard)
end

local DIRS = { [-1] = { [-1] = "7", [0] = "4", [1] = "1" }, [0] = { [-1] = "8", [0] = "5", [1] = "2" },
               [1] = { [-1] = "9", [0] = "6", [1] = "3" } }
M.DIRS = DIRS

function Keyboard:stick()
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
    return DIRS[x][y]
end

--- Called every frame: remember presses and stick positions until the
--- next tick.
function Keyboard:poll()
    local k = self.keys
    if any(k.punch, input.pressed) then self.punch = true end
    if any(k.kick, input.pressed) then self.kick = true end
    local s = self:stick()
    if s ~= self.seen[#self.seen] then self.seen[#self.seen + 1] = s end
end

--- Called every tick: dir, punch, kick, and the stick positions passed
--- through since the last tick (oldest first, not counting `dir`).
function Keyboard:take()
    local dir = self:stick()
    local between = self.seen
    if between[#between] == dir then between[#between] = nil end
    self.seen = {}
    local p, kk = self.punch, self.kick
    self.punch, self.kick = false, false
    return dir, p, kk, between
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
