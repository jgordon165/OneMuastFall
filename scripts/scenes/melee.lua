-- Pilot and HAR selection (MELEE.BK), as in the original and OpenOMF's
-- game/scenes/melee.c.
--
-- First page: the ten pilot faces in a 5 x 2 grid. Each player moves a
-- blinking box over a face (red player 1, blue player 2, violet when both
-- are on the same one); the big portrait in the top corner, the pilot's
-- name, biography and POWER / AGILITY / ENDURANCE bars follow the cursor.
-- Punch or kick picks; punch + kick together takes a pick back. When every
-- player has picked, the second page shows the HARs in the same grid, the
-- picked HAR animating next to its pilot in the pilot's colours ("JAGUAR
-- VS. SHADOW" in two player games). Then the fight. Esc on the HAR page
-- goes back to the pilots, on the pilot page to the main menu.
--
-- In a one player game the computer takes a random other pilot and HAR.
-- The score carries from fight to fight while you keep winning; a loss
-- (or leaving the pilot page) ends the run, and a score that makes the
-- list goes to the SCOREBOARD for your name.
-- The level, arena, rounds and speed come from GAMEPLAY (scenes/gameplay.lua).

local Stage    = require("core.stage")
local P        = require("core.player")
local scenes   = require("core.scenes")
local res      = require("game.res")
local pilots   = require("game.pilots")
local control  = require("game.control")
local gameplay = require("scenes.gameplay")

local M = {}

local PILOT_PAGE, HAR_PAGE = 1, 2
local MAX_STAT = 20

-- palette entries the screen animates and draws with (melee.c)
local RED_CURSOR, BLUE_CURSOR, VIOLET_CURSOR = 0xF6, 0xF7, 0xF8
local TEXT_GREEN, TEXT_SHADOW_GREEN = 0xA6, 0xA2
local TEXT_BLACK, TEXT_SHADOW_BLACK = 0xD1, 0xD7
local PANEL_LINE, PANEL_BORDER1, PANEL_BORDER2 = 172, 164, 162   -- MenuBackgroundMeleeVs
local BAR = { border = 0xA2, tl = 0xA7, mid = 0xA5, br = 0xA3 }  -- PROGRESSBAR_THEME_MELEE

-- wins of each side in this session's two player games
M.wins = { 0, 0 }

-- the one player run: { score, pilot, har } (nil between runs)
M.run = nil

-- ---- images ------------------------------------------------------------------

local function table256(fn)
    local t = {}
    for i = 0, 255 do t[i + 1] = string.char(fn(i) & 0xFF) end
    return table.concat(t)
end

-- HAR sheet colours (< 0x60) to grey, as surface_convert_har_to_grayscale(8)
local GREY = table256(function(i)
    if i ~= 0 and i < 0x60 then return 0xD0 + 8 * (i % 16) // 15 end
    return i
end)
-- the sheet's background (0xD0) is the transparent colour of a picked HAR
local HAR_CUT = table256(function(i) return i == 0xD0 and 0 or i end)

-- ---- text --------------------------------------------------------------------

local FONT_SMALL, LINE_H = 1, 7

local function centred(s, x, y, w, c, shadow, shadow_dir)
    local tw = gfx.text_width(s, FONT_SMALL)
    gfx.text(s, x + (w - tw) // 2, y, c, FONT_SMALL, shadow, shadow_dir)
end
local function green(s, x, y, w) centred(s, x, y, w, TEXT_GREEN, TEXT_SHADOW_GREEN, 1) end
local function black(s, x, y, w) centred(s, x, y, w, TEXT_BLACK, TEXT_SHADOW_BLACK, -1) end

local function wrap(s, width)
    local cols = math.max(1, width // gfx.text_width("M", FONT_SMALL))
    local lines, line = {}, ""
    for word in s:gmatch("%S+") do
        if line == "" then line = word
        elseif #line + 1 + #word <= cols then line = line .. " " .. word
        else lines[#lines + 1] = line; line = word end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

-- a biography, centred in its w x h box
local function bio(s, x, y, w, h)
    local lines = wrap(s, w)
    local top = y + math.max(0, (h - #lines * LINE_H) // 2)
    for i, l in ipairs(lines) do green(l, x, top + (i - 1) * LINE_H, w) end
end

-- ---- boxes -------------------------------------------------------------------

-- the see-through grid panels behind the stats and the biography
local function panel(x, y, w, h)
    for lx = x + 5, x + w - 1, 5 do gfx.line(lx, y, lx, y + h - 1, PANEL_LINE) end
    for ly = y + 4, y + h - 1, 5 do gfx.line(x, ly, x + w - 1, ly, PANEL_LINE) end
    gfx.rect(x + 1, y + 1, w - 1, h - 1, PANEL_BORDER2)
    gfx.rect(x, y, w - 1, h - 1, PANEL_BORDER1)
end

local function stat_bar(x, y, w, h, value)
    gfx.fill(x, y, w, h, 0)
    gfx.rect(x, y, w, h, BAR.border)
    local fw = w * math.max(0, math.min(100, value * 100 // MAX_STAT)) // 100
    if fw <= 0 then return end
    gfx.fill(x, y, fw, h, BAR.mid)
    gfx.line(x, y, x + fw - 1, y, BAR.tl)
    gfx.line(x, y + h - 1, x + fw - 1, y + h - 1, BAR.br)
    gfx.line(x, y, x, y + h - 1, BAR.tl)
    if fw > 1 then gfx.line(x + fw - 1, y, x + fw - 1, y + h - 1, BAR.br) end
end

-- ---- scene -------------------------------------------------------------------

local function index(c) return c.row * 5 + c.col end

--- args: { vs_ai = bool, back = { pilot = {a, b}, har = {a, b} } }; `back`
--- returns to the HAR page after a fight with these picks.
function M:enter(args)
    args = args or {}
    self.vs_ai = args.vs_ai and true or false
    -- a new one player game from the menu starts a new run
    if self.vs_ai and not args.back then M.run = { score = 0 } end
    self.bk = res.bk("MELEE.BK")
    self.stage = Stage.new(self.bk)
    self.stage.no_music = true
    if not audio.music_playing() then audio.music("MENU.PSM", true) end
    local alt = omf.altpals()
    self.altpal = alt and alt[0]

    local a = self.bk.anims
    self.faces = a[3].sprites                       -- the faces, in colour
    self.big = a[4].sprites                         -- the big portraits
    self.misc = a[5].sprites                        -- frames and logo
    self.pilot_sheet = a[0].sprites[1]              -- all the faces, dimmed
    local sheet = a[1].sprites[1]                   -- all the HARs
    self.har_sheet = { x = sheet.x, y = sheet.y, img = sheet.img:map(GREY) }
    self.har_cells = {}
    for i = 0, 9 do
        local col, row = i % 5, i // 5
        self.har_cells[i] = { x = sheet.x + 62 * col, y = sheet.y + 42 * row,
                              img = sheet.img:crop(62 * col, 42 * row, 51, 36):map(HAR_CUT) }
    end

    self.keys = { control.KEYS[1], control.KEYS[2] }
    self.ticks, self.tickbase = 0, { 0, 0 }
    self.acc = 0
    self.cursor = { { row = 0, col = 0, done = false }, { row = 0, col = 0, done = false } }
    self.har = {}
    if args.back then
        self.pilot_id = { args.back.pilot[1], args.back.pilot[2] }
        self:restore_cursors(args.back.har[1], args.back.har[2])
        self:enter_har_page()
    else
        self.pilot_id = { 0, 4 }                    -- Crystal and Shirro, as the game starts
        self:restore_cursors(0, 4)
        self:enter_pilot_page()
    end
end

function M:leave()
    self.stage = nil
end

function M:restore_cursors(a, b)
    for i, v in ipairs({ a, b }) do
        if v > 9 then v = 7 end                     -- Nova sits where Flail is
        self.cursor[i] = { row = v // 5, col = v % 5, done = false }
    end
end

function M:selectable(p) return p == 1 or not self.vs_ai end

-- The pilot page draws the dimmed faces with colours 1..0x5F: the faces'
-- own colours (0xA1..0xFF) at half brightness (load_pilot_portraits_palette).
function M:enter_pilot_page()
    self.page = PILOT_PAGE
    self.stage:load_palette(0)
    local pal = self.bk.palettes[0]
    for idx = 1, 0x5F do
        local s = (0xA0 + idx) * 3
        gfx.base_color(idx, pal:byte(s + 1) // 2, pal:byte(s + 2) // 2, pal:byte(s + 3) // 2)
    end
end

-- The HAR page: HAR colours 0..95 become the pilots' colours.
function M:enter_har_page()
    self.page = HAR_PAGE
    self.stage:load_palette(0)
    for p = 1, 2 do
        if self:selectable(p) then pilots.load_colors(self.altpal, p - 1, pilots[self.pilot_id[p] + 1]) end
    end
    for p = 1, 2 do
        if self:selectable(p) then self:update_har(p) end
    end
end

-- the HAR next to the player's portrait: BK animation 18 + HAR, looping
function M:update_har(p)
    local id = 18 + index(self.cursor[p])
    local o = P.new(self.bk.anims[id], p == 1 and 110 or 210, 95, self.stage, {
        dir = p == 1 and 1 or -1, pal_offset = (p - 1) * 48, pal_limit = p * 48 - 1,
        stl = self.bk.sound_table,
    })
    o.repeat_ = true
    self.har[p] = o
end

function M:reset_blink(p)
    local same = self:cursors_match()
    if same or p == 1 then self.tickbase[1] = self.ticks end
    if same or p == 2 then self.tickbase[2] = self.ticks end
end

function M:cursors_match()
    local a, b = self.cursor[1], self.cursor[2]
    return a.row == b.row and a.col == b.col
end

-- ---- input -------------------------------------------------------------------

local function any(list, fn)
    for _, k in ipairs(list) do if fn(k) then return true end end
    return false
end

function M:handle(p)
    local k, c = self.keys[p], self.cursor[p]
    local punch, kick = any(k.punch, input.pressed), any(k.kick, input.pressed)
    if c.done then
        -- punch + kick takes the pick back
        if (punch or kick) and any(k.punch, input.down) and any(k.kick, input.down) then
            c.done = false
            audio.sound(20, { pan = 0 })
        end
        return
    end
    local row, col = c.row, c.col
    if any(k.left, input.pressed) then c.col = (c.col - 1) % 5; self:reset_blink(p) end
    if any(k.right, input.pressed) then c.col = (c.col + 1) % 5; self:reset_blink(p) end
    if any(k.up, input.pressed) then c.row = 0; self:reset_blink(p) end
    if any(k.down, input.pressed) then c.row = 1; self:reset_blink(p) end
    if row ~= c.row or col ~= c.col then
        audio.sound(19, { pan = c.col * 100 // 5 - 50 })
        if self.page == PILOT_PAGE then self.pilot_id[p] = index(c) else self:update_har(p) end
        return
    end
    if punch or kick then
        c.done = true
        audio.sound(20, { pan = 0 })
        self:check_done()
    end
end

function M:check_done()
    if not self.cursor[1].done or not (self.cursor[2].done or self.vs_ai) then return end
    self.cursor[1].done, self.cursor[2].done = false, false
    if self.page == PILOT_PAGE then
        self.pilot_id = { index(self.cursor[1]), index(self.cursor[2]) }
        self:enter_har_page()
    else
        self:fight()
    end
end

function M:fight()
    local vs_ai = self.vs_ai
    local a, b = self.pilot_id[1], self.pilot_id[2]
    local har_a, har_b = index(self.cursor[1]), index(self.cursor[2])
    if vs_ai then
        -- an opponent: any other pilot, any HAR
        repeat b = math.random(0, 9) until b ~= a
        har_b = math.random(0, 9)
    end
    local s = gameplay.settings()
    local picks = { pilot = { a, self.pilot_id[2] }, har = { har_a, index(self.cursor[2]) } }
    local run = vs_ai and M.run or nil
    if run then run.pilot, run.har = a, har_a end
    scenes.switch(require("scenes.arena"), {
        arena = s.arena, rounds = s.rounds, speed = s.speed,
        players = {
            { har = har_a, pilot = pilots[a + 1], score = run and run.score or nil },
            { har = har_b, pilot = pilots[b + 1], ai = vs_ai and s.level or nil },
        },
        on_done = function(winner, totals)
            if not vs_ai and winner then M.wins[winner + 1] = M.wins[winner + 1] + 1 end
            if run then
                run.score = totals and totals[1] or run.score
                if winner ~= 0 then M.end_run(); return end   -- lost: the run is over
            end
            scenes.switch(require("scenes.melee"), { vs_ai = vs_ai, back = picks })
        end,
    })
end

--- The one player run is over: to the SCOREBOARD with its score.
function M.end_run()
    local run = M.run
    M.run = nil
    scenes.switch(require("scenes.scoreboard"), {
        pending = run and run.score > 0 and { score = run.score, har = run.har or 0, pilot = run.pilot or 0 } or nil,
    })
end

function M:update(dt)
    if input.pressed("escape", "pad_back") then
        audio.sound(20, { pan = 0 })
        if self.page == HAR_PAGE then
            self:restore_cursors(self.pilot_id[1], self.pilot_id[2])
            self:enter_pilot_page()
        elseif self.vs_ai and M.run and M.run.score > 0 then
            M.end_run()
        else
            scenes.switch(require("scenes.menu"))
        end
        return
    end
    for p = 1, 2 do
        if self:selectable(p) then
            self:handle(p)
            if scenes.top() ~= self then return end   -- picked the fight
        end
    end
    -- 10 ms ticks: the cursor blink, and every tenth a HAR frame
    self.acc = self.acc + dt
    local n = 0
    while self.acc >= Stage.TICK_MS and n < 50 do
        self.acc = self.acc - Stage.TICK_MS
        n = n + 1
        if self.page == HAR_PAGE and self.ticks % 10 == 1 then
            for p = 1, 2 do if self.har[p] and self:selectable(p) then P.tick(self.har[p]) end end
        end
        self.ticks = self.ticks + 1
    end
end

-- ---- drawing -----------------------------------------------------------------

local function blink(ticks) return math.floor((math.cos(ticks / 25) + 1) * 64 + 0.5) end

function M:cursor_colors()
    local base = 120
    local a = blink(self.ticks - self.tickbase[1])
    local b = blink(self.ticks - self.tickbase[2])
    gfx.base_color(RED_CURSOR, base + (self.cursor[1].done and 64 or a), 0, 0)
    gfx.base_color(BLUE_CURSOR, 0, 0, base + (self.cursor[2].done and 64 or b))
    gfx.base_color(VIOLET_CURSOR, base + a, 0, base + a)
end

local function highlight(c, colour)
    gfx.fill(11 + 62 * c.col, 115 + 42 * c.row, 51, 36, colour)
end

function M:highlights()
    local two = not self.vs_ai
    if two and self:cursors_match() then
        highlight(self.cursor[1], VIOLET_CURSOR)
    else
        if two then highlight(self.cursor[2], BLUE_CURSOR) end
        highlight(self.cursor[1], RED_CURSOR)
    end
end

local function draw_sprite(sp, x, y, flip)
    if sp and sp.img then gfx.draw(sp.img, x, y, flip) end
end

function M:big_portrait(p)
    local sp = self.big[self.pilot_id[p] + 1]
    if not sp then return end
    if p == 1 then draw_sprite(sp, sp.x, sp.y)
    else draw_sprite(sp, 320 - sp.x - sp.w, sp.y, true) end   -- mirrored in the right corner
end

function M:face(p)
    local sp = self.faces[index(self.cursor[p]) + 1]
    draw_sprite(sp, sp.x, sp.y)
end

-- the stats panel, name, biography and bars of one side
function M:pilot_info(p)
    local pl = pilots[self.pilot_id[p] + 1]
    local id = self.pilot_id[p]
    local sx = p == 1 and 70 or 160                -- stats panel (90 x 61)
    local bx = p == 1 and 0 or 160                 -- biography panel (160 x 43)
    local tx = p == 1 and 74 or 164                -- stat labels and bars
    panel(sx, 0, 90, 61)
    panel(bx, 62, 160, 43)
    black(res.text(20 + id), p == 1 and 0 or 254, 52, 66)
    bio(res.text(135 + id), bx + 4 + 2, 66 + 2, 156 - 2, 34 - 2)
    local stats = { pl.power, pl.agility, pl.endurance }
    for s = 0, 2 do
        green(res.text(216 + s), tx, 4 + s * 18, 85)
        stat_bar(tx, 12 + s * 18, 80, 8, stats[s + 1])
    end
end

function M:draw_pilot_page()
    local two = not self.vs_ai
    self:pilot_info(1)
    draw_sprite(self.misc[two and 1 or 2], self.misc[two and 1 or 2].x, self.misc[two and 1 or 2].y)
    if two then self:pilot_info(2)
    else green(res.text(187), 160, 97, 160) end   -- CHOOSE YOUR PILOT
    draw_sprite(self.pilot_sheet, self.pilot_sheet.x, self.pilot_sheet.y)
    self:highlights()
    self:face(1)
    self:big_portrait(1)
    if two then
        self:face(2)
        self:big_portrait(2)
    end
end

function M:har_cell(p)
    local cell = self.har_cells[index(self.cursor[p])]
    gfx.draw(cell.img, cell.x, cell.y, false, false, false, nil, (p - 1) * 48, p * 48 - 1)
end

function M:draw_har_page()
    local two = not self.vs_ai
    local misc = self.misc[two and 1 or 2]
    draw_sprite(misc, misc.x, misc.y)
    gfx.draw(self.har_sheet.img, self.har_sheet.x, self.har_sheet.y)
    self:highlights()
    self:big_portrait(1)
    self:har_cell(1)
    if self.har[1] then P.draw(self.har[1]) end
    black(res.text(20 + self.pilot_id[1]), 0, 52, 66)
    local title = res.HARS[index(self.cursor[1])]
    if two then
        black(res.text(20 + self.pilot_id[2]), 254, 52, 66)
        self:big_portrait(2)
        self:har_cell(2)
        if self.har[2] then P.draw(self.har[2]) end
        title = title .. " VS. " .. res.HARS[index(self.cursor[2])]
    else
        green(res.text(186), 160, 97, 160)          -- CHOOSE YOUR ROBOT
    end
    black(title, 0, 107, 320)
end

function M:draw()
    self:cursor_colors()
    self.stage:draw()
    if self.page == PILOT_PAGE then self:draw_pilot_page() else self:draw_har_page() end
    if not self.vs_ai then
        gfx.text("Wins: " .. M.wins[1], 8, 107, TEXT_BLACK, FONT_SMALL, TEXT_SHADOW_BLACK, -1)
        local s = "Wins: " .. M.wins[2]
        gfx.text(s, 160 + 152 - gfx.text_width(s, FONT_SMALL), 107, TEXT_BLACK, FONT_SMALL, TEXT_SHADOW_BLACK, -1)
    end
end

return M
