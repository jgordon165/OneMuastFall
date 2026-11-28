-- SCOREBOARD: the top 20 of each ROUNDS setting (game/scores.lua), laid out
-- as the original draws it: the title centred at the top, then a row every
-- 8 pixels from y 30 with the name at x 20, the robot at 128, the pilot at
-- 182 and the score right-aligned to 302.
--
-- Left/Right turn the pages; Esc, Enter, punch or kick leave.
--
-- After a one player game whose score makes the list (args.pending =
-- { score, har, pilot }), the row opens for a name: type it (letters,
-- digits, space, Backspace), or on a pad pick each letter with Up/Down,
-- move with Left/Right, delete with B (kick); Enter / A keeps it, and the
-- board is saved. Esc leaves it off the board.

local Stage    = require("core.stage")
local scenes   = require("core.scenes")
local res      = require("game.res")
local scores   = require("game.scores")
local gameplay = require("scenes.gameplay")
local Score    = require("game.score")

local M = {}

local TEXT, ACTIVE, SHADOW = 0xFD, 0xFF, 0xC0
local CHARSET = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local MAX_NAME = 15
local PAGES = 3     -- the ROUNDS settings the game offers (page 4, best 4 of 7, stays in the file)

-- ENGLISH.DAT's option strings end in a stray marker letter ("ONE ROUNDa")
local function option_text(id)
    local s = res.text(id):gsub("%s+$", "")
    return (s:gsub("([%u%d])a$", "%1"):gsub("(%%i)a$", "%1"))
end

function M.page_title(page)
    local what = page == 1 and option_text(234) or option_text(293):format(page, page * 2 - 1)
    return (res.text(194):gsub("%s+$", "")) .. " " .. what
end

--- The page for the current ROUNDS setting.
function M.current_page()
    return math.min(PAGES, gameplay.choice.rounds)
end

function M:enter(args)
    args = args or {}
    self.back = args.back
    self.bk = res.bk("MAIN.BK")
    self.stage = Stage.new(self.bk, {
        startup = function(id) if id == 10 or id == 11 then return true, true end end,
    })
    -- the background's colours at a quarter, so the list stands out
    local pal = self.bk.palettes[0]
    for i = 0, 0xEF do
        local o = i * 3
        gfx.base_color(i, pal:byte(o + 1) // 4, pal:byte(o + 2) // 4, pal:byte(o + 3) // 4)
    end
    if not audio.music_playing() then audio.music("MENU.PSM", true) end
    self.pages = scores.load()
    self.page = args.page or M.current_page()
    self.ticks = 0
    self.entry = nil
    local p = args.pending
    if p and p.score > 0 then
        local slot = scores.slot(self.pages, self.page, p.score)
        if slot then
            self.entry = { slot = slot, score = p.score, har = p.har, pilot = p.pilot, name = "", cursor = 1 }
        end
    end
end

function M:leave() self.stage = nil end

function M:close()
    scenes.switch(self.back or require("scenes.menu"))
end

-- ---- the name ------------------------------------------------------------------

local KEYS = {}
for c in ("abcdefghijklmnopqrstuvwxyz0123456789"):gmatch(".") do KEYS[#KEYS + 1] = c end

function M:edit_name(e)
    -- typing
    for _, k in ipairs(KEYS) do
        if input.pressed(k) and #e.name < MAX_NAME then
            e.name = e.name:sub(1, e.cursor - 1) .. k:upper() .. e.name:sub(e.cursor + 1)
            e.cursor = math.min(MAX_NAME, e.cursor + 1)
        end
    end
    if input.pressed("space") and e.cursor <= MAX_NAME then
        e.name = e.name:sub(1, e.cursor - 1) .. " " .. e.name:sub(e.cursor + 1)
        e.cursor = math.min(MAX_NAME, e.cursor + 1)
    end
    if input.pressed("backspace", "pad_b", "right shift") and e.cursor > 1 then
        e.cursor = e.cursor - 1
        e.name = e.name:sub(1, e.cursor - 1) .. e.name:sub(e.cursor + 1)
    end
    -- the letter wheel (pads)
    local d = (input.pressed("up", "pad_up") and 1 or 0) - (input.pressed("down", "pad_down") and 1 or 0)
    if d ~= 0 then
        local ch = e.name:sub(e.cursor, e.cursor)
        if ch == "" then ch = " " end
        local i = (CHARSET:find(ch, 1, true) or 1) - 1
        i = (i + d) % #CHARSET
        local pad = e.name .. string.rep(" ", math.max(0, e.cursor - #e.name - 1))
        e.name = pad:sub(1, e.cursor - 1) .. CHARSET:sub(i + 1, i + 1) .. pad:sub(e.cursor + 1)
    end
    if input.pressed("left", "pad_left") then e.cursor = math.max(1, e.cursor - 1) end
    if input.pressed("right", "pad_right") then e.cursor = math.min(MAX_NAME, #e.name + 1, e.cursor + 1) end
    if input.pressed("return", "pad_a", "pad_start") then
        local name = e.name:gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then
            scores.insert(self.pages, self.page, e.slot, { score = e.score, name = name, har = e.har, pilot = e.pilot })
            scores.save(self.pages)
            self.entry = nil
        end
    end
    if input.pressed("escape") then self.entry = nil end   -- no name, no entry
end

function M:update(dt)
    self.ticks = self.ticks + 1
    if self.entry then
        self:edit_name(self.entry)
    else
        if input.pressed("left", "pad_left") then self.page = math.max(1, self.page - 1) end
        if input.pressed("right", "pad_right") then self.page = math.min(PAGES, self.page + 1) end
        if input.pressed("escape", "return", "space", "pad_a", "pad_b", "pad_start", "right ctrl", "right shift") then
            self:close()
            return
        end
    end
    self.stage:update(dt)
end

-- ---- drawing -------------------------------------------------------------------

local function clean(id) return (res.text(id):gsub("%s+$", "")) end

local function row(name, har, pilot, score, y, c)
    gfx.text(name, 20, y, c, 1, SHADOW)
    gfx.text(clean(31 + har), 128, y, c, 1, SHADOW)
    local s = Score.format(score)
    local sx = 302 - gfx.text_width(s, 1)
    gfx.clip(182, y - 1, sx - 4 - 182, 9)   -- a long name (MAJOR KREISSACK) stops short of the score
    gfx.text(clean(20 + pilot), 182, y, c, 1, SHADOW)
    gfx.unclip()
    gfx.text(s, sx, y, c, 1, SHADOW)
end

function M:draw()
    self.stage:draw()
    local title = M.page_title(self.page)
    gfx.text(title, (320 - gfx.text_width(title, 0)) // 2, 2, TEXT, 0, SHADOW)
    gfx.text(clean(196), 20, 20, TEXT, 1, SHADOW)
    local list, e = self.pages[self.page], self.entry
    local shown = 0
    for r = 1, scores.ENTRIES do
        local y = 30 + (r - 1) * 8
        if e and r == e.slot then
            row(e.name, e.har, e.pilot, e.score, y, ACTIVE)
            -- the cursor, blinking
            if (self.ticks // 20) % 2 == 0 then
                local cx = 20 + (e.cursor - 1) * gfx.text_width("M", 1)
                gfx.fill(cx, y + 6, gfx.text_width("M", 1) - 1, 1, ACTIVE)
            end
        else
            shown = shown + 1
            local it = list[shown]
            if it and it.score > 0 then row(it.name, it.har, it.pilot, it.score, y, TEXT) end
        end
    end
    if e then
        local s = "ENTER YOUR NAME"
        gfx.text(s, (320 - gfx.text_width(s, 1)) // 2, 192, ACTIVE, 1, SHADOW)
    end
end

return M
