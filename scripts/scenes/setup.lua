-- Fight setup: pick each side's HAR and pilot, the arena and the rounds,
-- then FIGHT. Reached from ONE PLAYER GAME (player 2 is the computer) and
-- TWO PLAYER GAME. (The original's HAR-select screen, MELEE.BK, comes
-- later; this panel gets you into a fight.)
--
-- Up/Down pick a line, Left/Right change it, Enter on FIGHT starts, Esc back.

local Stage  = require("core.stage")
local scenes = require("core.scenes")
local res    = require("game.res")
local ui     = require("ui.menu")
local pilots = require("game.pilots")
local H      = require("game.har")

local M = {}

local ARENAS = { [0] = "STADIUM", "DANGER ROOM", "POWER PLANT", "FIRE PIT", "DESERT" }
local ROUNDS = { 1, 3, 5 }
local DIFFICULTY = { "PUNCHING BAG", "ROOKIE", "VETERAN", "WORLD CLASS", "CHAMPION" }

-- remembered between visits
local choice = { har = { 0, 1 }, pilot = { 1, 2 }, arena = 0, rounds = 2, difficulty = 3 }

function M:enter(args)
    self.vs_ai = args and args.vs_ai
    self.bk = res.bk("MAIN.BK")
    self.stage = Stage.new(self.bk, {
        startup = function(id) if id == 10 or id == 11 then return true, true end end,
    })
    if not audio.music_playing() then audio.music("MENU.PSM", true) end
    self.sel = 1
end

function M:lines()
    local l = {
        { key = "har1", label = "PLAYER 1  " .. H.NAMES[choice.har[1]] },
        { key = "pilot1", label = "PILOT     " .. pilots[choice.pilot[1]].name },
        { key = "har2", label = (self.vs_ai and "COMPUTER  " or "PLAYER 2  ") .. H.NAMES[choice.har[2]] },
        { key = "pilot2", label = "PILOT     " .. pilots[choice.pilot[2]].name },
    }
    if self.vs_ai then l[#l + 1] = { key = "difficulty", label = "LEVEL     " .. DIFFICULTY[choice.difficulty] } end
    l[#l + 1] = { key = "arena", label = "ARENA     " .. ARENAS[choice.arena] }
    l[#l + 1] = { key = "rounds", label = "ROUNDS    " .. (ROUNDS[choice.rounds] == 1 and "ONE ROUND" or
        ("BEST " .. (ROUNDS[choice.rounds] // 2 + 1) .. " OF " .. ROUNDS[choice.rounds])) }
    l[#l + 1] = { key = "fight", label = "FIGHT!" }
    l[#l + 1] = { key = "back", label = "BACK" }
    return l
end

local function cycle(v, d, lo, hi) return (v - lo + d) % (hi - lo + 1) + lo end

function M:change(key, d)
    if key == "har1" then choice.har[1] = cycle(choice.har[1], d, 0, 10)
    elseif key == "har2" then choice.har[2] = cycle(choice.har[2], d, 0, 10)
    elseif key == "pilot1" then choice.pilot[1] = cycle(choice.pilot[1], d, 1, #pilots)
    elseif key == "pilot2" then choice.pilot[2] = cycle(choice.pilot[2], d, 1, #pilots)
    elseif key == "arena" then choice.arena = cycle(choice.arena, d, 0, 4)
    elseif key == "rounds" then choice.rounds = cycle(choice.rounds, d, 1, #ROUNDS)
    elseif key == "difficulty" then choice.difficulty = cycle(choice.difficulty, d, 1, #DIFFICULTY) end
end

function M:fight()
    local vs_ai = self.vs_ai
    scenes.switch(require("scenes.arena"), {
        arena = choice.arena,
        rounds = ROUNDS[choice.rounds],
        players = {
            { har = choice.har[1], pilot = pilots[choice.pilot[1]] },
            { har = choice.har[2], pilot = pilots[choice.pilot[2]], ai = vs_ai and choice.difficulty or nil },
        },
        on_done = function() scenes.switch(require("scenes.setup"), { vs_ai = vs_ai }) end,
    })
end

function M:update(dt)
    local lines = self:lines()
    if input.pressed("up", "pad_up") then self.sel = (self.sel - 2) % #lines + 1 end
    if input.pressed("down", "pad_down") then self.sel = self.sel % #lines + 1 end
    local key = lines[self.sel].key
    if input.pressed("left", "pad_left") then self:change(key, -1) end
    if input.pressed("right", "pad_right") then self:change(key, 1) end
    if input.pressed("return", "space", "pad_a", "pad_start") then
        if key == "fight" then self:fight(); return
        elseif key == "back" then scenes.switch(require("scenes.menu")); return
        else self:change(key, 1) end
    end
    if input.pressed("escape", "pad_b") then scenes.switch(require("scenes.menu")); return end
    self.stage:update(dt)
end

function M:draw()
    ui.pulse(self.stage.tick // 3)
    self.stage:draw()
    local lines = self:lines()
    local x, y, w = 60, 20, 200
    local h = #lines * 11 + 14
    ui.panel(self.bk, x, y, w, h)
    gfx.text(self.vs_ai and "ONE PLAYER GAME" or "TWO PLAYER GAME", x + (w - gfx.text_width(self.vs_ai and
        "ONE PLAYER GAME" or "TWO PLAYER GAME", 0)) // 2, y - 10, ui.COLOR_ACTIVE, 0)
    for i, l in ipairs(lines) do
        local c = i == self.sel and ui.COLOR_ACTIVE or ui.COLOR_INACTIVE
        local tx = (l.key == "fight" or l.key == "back") and (x + (w - gfx.text_width(l.label, 1)) // 2) or (x + 10)
        gfx.text(l.label, tx, y + 8 + (i - 1) * 11, c, 1)
    end
    local hint = sys.platform == "xenon" and "LEFT/RIGHT CHANGES  A STARTS  BACK RETURNS"
        or "LEFT/RIGHT CHANGES  ENTER STARTS"
    gfx.text(hint, (320 - gfx.text_width(hint, 1)) // 2, 190, ui.COLOR_INACTIVE, 1)
end

return M
