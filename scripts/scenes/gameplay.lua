-- GAMEPLAY: the fight options the pilot-select screen (scenes/melee.lua)
-- hands to the arena: the computer's level, the arena, the rounds and the
-- game speed. Reached from the main menu.
--
-- Up/Down pick a line, Left/Right change it, Esc or BACK returns.

local Stage  = require("core.stage")
local scenes = require("core.scenes")
local res    = require("game.res")
local ui     = require("ui.menu")

local M = {}

M.ARENAS = { [-1] = "RANDOM", [0] = "STADIUM", "DANGER ROOM", "POWER PLANT", "FIRE PIT", "DESERT" }
M.ROUNDS = { 1, 3, 5 }
M.DIFFICULTY = { "PUNCHING BAG", "ROOKIE", "VETERAN", "WORLD CLASS", "CHAMPION" }

-- kept for the session; arena -1 picks one at random for every fight
M.choice = { arena = -1, rounds = 2, difficulty = 3, speed = 5 }

--- What the arena needs from these settings: arena, rounds, speed, level.
function M.settings()
    local c = M.choice
    local arena = c.arena
    if arena < 0 then arena = math.random(0, 4) end
    return { arena = arena, rounds = M.ROUNDS[c.rounds], speed = c.speed, level = c.difficulty }
end

function M:enter()
    self.bk = res.bk("MAIN.BK")
    self.stage = Stage.new(self.bk, {
        startup = function(id) if id == 10 or id == 11 then return true, true end end,
    })
    if not audio.music_playing() then audio.music("MENU.PSM", true) end
    self.sel = 1
end

function M:lines()
    local c = M.choice
    local r = M.ROUNDS[c.rounds]
    return {
        { key = "difficulty", label = "LEVEL     " .. M.DIFFICULTY[c.difficulty] },
        { key = "arena", label = "ARENA     " .. M.ARENAS[c.arena] },
        { key = "rounds", label = "ROUNDS    " .. (r == 1 and "ONE ROUND" or ("BEST " .. (r // 2 + 1) .. " OF " .. r)) },
        { key = "speed", label = "SPEED     " .. string.rep("#", c.speed) .. string.rep(".", 10 - c.speed) },
        { key = "back", label = "DONE" },
    }
end

local function cycle(v, d, lo, hi) return (v - lo + d) % (hi - lo + 1) + lo end

function M:change(key, d)
    local c = M.choice
    if key == "arena" then c.arena = cycle(c.arena, d, -1, 4)
    elseif key == "rounds" then c.rounds = cycle(c.rounds, d, 1, #M.ROUNDS)
    elseif key == "difficulty" then c.difficulty = cycle(c.difficulty, d, 1, #M.DIFFICULTY)
    elseif key == "speed" then c.speed = math.max(0, math.min(10, c.speed + d)) end
end

function M:update(dt)
    local lines = self:lines()
    if input.pressed("up", "pad_up") then self.sel = (self.sel - 2) % #lines + 1 end
    if input.pressed("down", "pad_down") then self.sel = self.sel % #lines + 1 end
    local key = lines[self.sel].key
    if input.pressed("left", "pad_left") then self:change(key, -1) end
    if input.pressed("right", "pad_right") then self:change(key, 1) end
    if input.pressed("return", "space", "pad_a", "pad_start") then
        if key == "back" then scenes.switch(require("scenes.menu")); return end
        self:change(key, 1)
    end
    if input.pressed("escape", "pad_b") then scenes.switch(require("scenes.menu")); return end
    self.stage:update(dt)
end

function M:draw()
    ui.pulse(self.stage.tick // 3)
    self.stage:draw()
    local lines = self:lines()
    local x, y, w = 60, 40, 200
    local h = #lines * 11 + 14
    ui.panel(self.bk, x, y, w, h)
    gfx.text("GAMEPLAY", x + (w - gfx.text_width("GAMEPLAY", 0)) // 2, y - 10, ui.COLOR_ACTIVE, 0)
    for i, l in ipairs(lines) do
        local c = i == self.sel and ui.COLOR_ACTIVE or ui.COLOR_INACTIVE
        local tx = l.key == "back" and (x + (w - gfx.text_width(l.label, 1)) // 2) or (x + 10)
        gfx.text(l.label, tx, y + 8 + (i - 1) * 11, c, 1)
    end
    gfx.text("LEFT/RIGHT CHANGES", (320 - gfx.text_width("LEFT/RIGHT CHANGES", 1)) // 2, 190, ui.COLOR_INACTIVE, 1)
end

return M
