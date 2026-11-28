-- A fighter's score in the arena, and the announcer's callouts: the texts
-- that appear over a HAR ("5 CONSECUTIVE HITS 6,000", "PERFECT ROUND") and
-- slide into its score under the health bars, where their points are
-- added. As the original (MASTER.DAT):
--
--   * every hit scores the move's points (AF) x the multiplier;
--   * CONSECUTIVE HITS: more than 3 hits in a row, announced when the
--     other side finally lands one; bonus = their points again;
--   * HIT COMBO: 2+ hits before the other HAR recovers; bonus = points x 4;
--   * at the end of a fight won against the computer: PERFECT ROUND (full
--     health, 2,000), VITALITY (health % x 20), and SCRAP BONUS (1,000) or
--     DESTRUCTION BONUS (2,000) for the finishing move; all x the multiplier.
--
-- The multiplier is (level + 1) x 20 against the computer (PUNCHING BAG 20
-- .. CHAMPION 100; DEADLY 150, ULTIMATE 200), 100 between two players. The
-- computer gets its callouts but no points.

local res = require("game.res")

local M = {}
M.__index = M

local TEXT, SHADOW = 0xE7, 0xF8        -- the HUD's colours
local HANG, SPACING, STEP = 25, 50, 0.01 -- ticks shown in place; between callouts; slide per tick

local LANG = { consecutive = 201, combo = 202, perfect = 203, vitality = 204, scrap = 205, destruction = 206 }

-- the original's texts; the counted ones start with a space (" HIT COMBO")
local function label(key)
    return (res.text(LANG[key]):gsub("%s+$", ""))
end

--- 1,234,567
function M.format(n)
    local s = tostring(math.floor(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

--- The points multiplier: `level` is the computer's level (1 PUNCHING
--- BAG .. 7 ULTIMATE), nil between two players.
function M.multiplier(level)
    if not level then return 100 end
    if level >= 7 then return 200 elseif level == 6 then return 150 end
    return math.max(1, level) * 20
end

--- side 1 (left) or 2 (right); human: scores points; total: carried over
--- from earlier fights.
function M.new(side, human, mult, total)
    return setmetatable({
        side = side, human = human, mult = mult,
        total = total or 0,
        cons_hits = 0, cons_points = 0,      -- hits in a row
        combo_hits = 0, combo_points = 0,    -- hits before the other HAR recovers
        texts = {},
    }, M)
end

function M:anchor()
    return self.side == 1 and 4 or 316, 32
end

-- a callout at (x, y), sliding into the score
function M:callout(text, points, x, y)
    if self.human then text = text .. " " .. M.format(points) else points = 0 end
    local w = gfx.text_width(text, 1)
    self.texts[#self.texts + 1] = {
        text = text, points = points, w = w,
        x = math.floor(x - w / 2), y = math.floor(y), pos = 1.0, age = 0,
    }
end

--- This side landed a hit worth `points` (the move's).
function M:hit(points)
    local p = self.human and points * self.mult or 0
    self.total = self.total + p
    self.cons_hits = self.cons_hits + 1
    self.cons_points = self.cons_points + p
    self.combo_hits = self.combo_hits + 1
    self.combo_points = self.combo_points + p
end

--- The other side landed one: the run of hits in a row ends.
function M:interrupted(x, y)
    if self.cons_hits > 3 then
        self:callout(self.cons_hits .. label("consecutive"), self.cons_points, x, y)
    end
    self.cons_hits, self.cons_points = 0, 0
end

--- The other HAR recovered: the combo ends.
function M:end_combo(x, y)
    if self.combo_hits > 1 then
        self:callout(self.combo_hits .. label("combo"), self.combo_points * 4, x, y)
    end
    self.combo_hits, self.combo_points = 0, 0
end

--- Won the fight with `health` % left.
function M:victory(health, x, y)
    if health >= 100 then self:callout(label("perfect"), 2000 * self.mult, x, y) end
    self:callout(label("vitality"), health * 20 * self.mult, x, y)
end

--- Finished it with a scrap ("scrap") or destruction move.
function M:finisher(kind, x, y)
    self:callout(label(kind), (kind == "destruction" and 2000 or 1000) * self.mult, x, y)
end

--- The callouts still on their way.
function M:busy() return #self.texts > 0 end

function M:tick()
    local last
    local i = 1
    while i <= #self.texts do
        local t = self.texts[i]
        -- one at a time: each waits until the one before has a head start
        if last and last - t.age < SPACING then break end
        if t.age > HANG then t.pos = t.pos - STEP end
        last = t.age
        t.age = t.age + 1
        if t.pos < 0 then
            self.total = self.total + t.points
            table.remove(self.texts, i)
        else
            i = i + 1
        end
    end
end

local function text(s, x, y)
    gfx.text(s, x, y, TEXT, 1, SHADOW)
end

function M:draw(show_total)
    local ax, ay = self:anchor()
    if show_total then
        local s = M.format(self.total)
        text(s, self.side == 1 and ax or ax - gfx.text_width(s, 1), ay)
    end
    local last
    for _, t in ipairs(self.texts) do
        if last and last - t.age < SPACING then break end
        local tx = self.side == 1 and ax or ax - t.w
        -- pos 1.0 at the start, 0.0 at the score
        text(t.text, math.floor(tx + (t.x - tx) * t.pos), math.floor(ay + (t.y - ay) * t.pos))
        last = t.age
    end
end

return M
