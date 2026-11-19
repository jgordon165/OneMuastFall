-- Asset explorer (F12, or --explorer): every original file, decoded.
--
--   file list   Up/Down pick (or type a letter), Enter open, Esc back
--   BK          Left/Right pick an animation, Enter play it (loops), A play
--               the whole scene from its startup animation, B background
--               on/off, P next palette, S its animation string, Esc back
--   AF          Left/Right pick a move, Enter play, S strings, Esc back
--   PIC         Left/Right pick a photo (hold C: with its own 48 colours)
--   PSM         Enter plays / stops the song
--   SOUNDS.DAT  Up/Down pick, Enter play
--   ENGLISH.DAT Up/Down scroll the strings

local Stage  = require("core.stage")
local script = require("core.script")
local scenes = require("core.scenes")
local res    = require("game.res")

local M = {}

local C_TEXT, C_HI, C_DIM, C_BG = 253, 255, 254, 250
local SMALL = 1

local function upper(s) return s:upper() end
local function ext(n) return (n:match("%.([^.]+)$") or ""):upper() end

local function text(s, x, y, c) return gfx.text(upper(s), x, y, c or C_TEXT, SMALL) end

-- A neutral palette for screens with no scene palette of their own: the
-- menu's, so the menu colours (250..255) are there for the text.
local function menu_colors()
    local cols = { {0,0,42}, {0,0,60}, {0,0,22}, {0,63,0}, {0,30,0}, {20,63,20} }
    for i, c in ipairs(cols) do
        gfx.base_color(249 + i, (c[1] << 2) | (c[1] >> 4), (c[2] << 2) | (c[2] >> 4), (c[3] << 2) | (c[3] >> 4))
    end
    gfx.base_color(0, 0, 0, 0)
    gfx.reset_palette()
end

local function neutral_palette()
    gfx.set_base(res.bk("MAIN.BK").palettes[0])
    menu_colors()
end

local function sorted_ids(t)
    local ids = {}
    for id in pairs(t) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

function M:enter()
    self.files = {}
    local kinds = { BK = true, AF = true, PIC = true, PSM = true }
    for _, e in ipairs(fs.list()) do
        local k = ext(e.name)
        if kinds[k] then self.files[#self.files + 1] = { name = e.name, kind = k, size = e.size } end
    end
    self.files[#self.files + 1] = { name = "SOUNDS.DAT", kind = "SOUNDS" }
    self.files[#self.files + 1] = { name = "ENGLISH.DAT", kind = "TEXT" }
    self.sel, self.scroll = 1, 0
    self.view = nil
    self.music_was = audio.music_playing()
end

function M:leave()
    audio.stop_all()
end

-- ---- views ---------------------------------------------------------------

local function open_bk(name)
    local bk = res.bk(name)
    local v = { kind = "BK", name = name, bk = bk, ids = sorted_ids(bk.anims), sel = 1, pal = 0,
                show_bg = true, show_script = false }
    v.stage = Stage.new(bk)
    v.stage.no_music = true
    return v
end

local function play_bk_anim(v)
    local id = v.ids[v.sel]
    if not id then return end
    v.stage = Stage.new(v.bk)
    v.stage.no_music = true
    local a = v.bk.anims[id]
    local o = v.stage:add(a, a.start_x, a.start_y)
    o.repeat_ = true
    v.stage:flush()
    v.stage:load_palette(v.pal)
end

local function play_bk_scene(v)
    -- Start what the scene itself starts: the animations nothing else spawns.
    local spawned = {}
    for _, a in pairs(v.bk.anims) do
        for m in a.script:gmatch("m(%d+)") do spawned[tonumber(m)] = true end
    end
    v.stage = Stage.new(v.bk, { startup = function(id) return not spawned[id], true end })
    v.stage:load_palette(v.pal)
end

local function open_af(name)
    local af, err = omf.af(name)
    if not af then return { kind = "ERR", msg = err } end
    local v = { kind = "AF", name = name, af = af, ids = sorted_ids(af.moves), sel = 1 }
    -- an arena palette, with the HAR's 48 colours from ALTPALS.DAT
    v.arena = res.bk("ARENA0.BK")
    v.altpals = omf.altpals()
    return v
end

local function play_af_move(v)
    local id = v.ids[v.sel]
    if not id then return end
    local m = v.af.moves[id]
    -- A one-animation stage over the arena; the HAR stands at x=160 on the floor.
    v.stage = Stage.new({ anims = {}, palettes = v.arena.palettes, sound_table = v.af.sound_table,
                          background = v.arena.background, remaps = v.arena.remaps })
    v.stage.no_music = true
    local o = v.stage:add(m, 160, 190)
    o.repeat_ = true
    v.stage:flush()
end

local function open_pic(name)
    local pic, err = omf.pic(name)
    if not pic then return { kind = "ERR", msg = err } end
    local n = 0
    for _ in pairs(pic) do n = n + 1 end
    return { kind = "PIC", name = name, pic = pic, sel = 0, count = n }
end

function M:open(f)
    if f.kind == "BK" then self.view = open_bk(f.name)
    elseif f.kind == "AF" then self.view = open_af(f.name)
    elseif f.kind == "PIC" then self.view = open_pic(f.name)
    elseif f.kind == "PSM" then
        if self.playing == f.name then audio.stop_music(); self.playing = nil
        else
            if audio.music(f.name, true) then self.playing = f.name end
        end
    elseif f.kind == "SOUNDS" then self.view = { kind = "SOUNDS", sel = 0, scroll = 0 }
    elseif f.kind == "TEXT" then self.view = { kind = "TEXT", sel = 0 }
    end
end

-- ---- update --------------------------------------------------------------

function M:update(dt)
    local v = self.view
    if not v then
        local n = #self.files
        if input.pressed("up") then self.sel = (self.sel - 2) % n + 1 end
        if input.pressed("down") then self.sel = self.sel % n + 1 end
        if input.pressed("pageup") then self.sel = math.max(1, self.sel - 20) end
        if input.pressed("pagedown") then self.sel = math.min(n, self.sel + 20) end
        if input.pressed("return") then self:open(self.files[self.sel]) end
        -- a letter jumps to the next file starting with it
        local k = input.last()
        if #k == 1 and k:match("[%w]") then
            for d = 1, n do
                local i = (self.sel - 1 + d) % n + 1
                if self.files[i].name:sub(1, 1):lower() == k then self.sel = i; break end
            end
        end
        if input.pressed("escape") then
            if #scenes.stack > 1 then scenes.pop() else scenes.switch(require("scenes.menu")) end
        end
        return
    end
    if input.pressed("escape") then
        audio.stop_all()
        self.view = nil
        return
    end
    if v.kind == "BK" then
        local n = #v.ids
        if input.pressed("left") then v.sel = (v.sel - 2) % math.max(n, 1) + 1 end
        if input.pressed("right") then v.sel = v.sel % math.max(n, 1) + 1 end
        if input.pressed("return") then play_bk_anim(v) end
        if input.pressed("a") then play_bk_scene(v) end
        if input.pressed("b") then v.show_bg = not v.show_bg end
        if input.pressed("s") then v.show_script = not v.show_script end
        if input.pressed("p") then
            v.pal = (v.pal + 1) % math.max(1, v.bk.palette_count)
            v.stage:load_palette(v.pal)
        end
        v.stage:update(dt)
    elseif v.kind == "AF" then
        local n = #v.ids
        if input.pressed("left") then v.sel = (v.sel - 2) % math.max(n, 1) + 1 end
        if input.pressed("right") then v.sel = v.sel % math.max(n, 1) + 1 end
        if input.pressed("return") then play_af_move(v) end
        if input.pressed("s") then v.show_script = not v.show_script end
        if v.stage then v.stage:update(dt) end
    elseif v.kind == "PIC" then
        if input.pressed("left") then v.sel = (v.sel - 1) % v.count end
        if input.pressed("right") then v.sel = (v.sel + 1) % v.count end
    elseif v.kind == "SOUNDS" then
        local n = #res.sounds + 1
        if input.pressed("up") then v.sel = (v.sel - 1) % n end
        if input.pressed("down") then v.sel = (v.sel + 1) % n end
        if input.pressed("pageup") then v.sel = math.max(0, v.sel - 20) end
        if input.pressed("pagedown") then v.sel = math.min(n - 1, v.sel + 20) end
        if input.pressed("return") then audio.sound(v.sel, {}) end
    elseif v.kind == "TEXT" then
        local n = #res.lang + 1
        if input.pressed("up") then v.sel = (v.sel - 1) % n end
        if input.pressed("down") then v.sel = (v.sel + 1) % n end
        if input.pressed("pageup") then v.sel = math.max(0, v.sel - 10) end
        if input.pressed("pagedown") then v.sel = math.min(n - 1, v.sel + 10) end
    end
end

-- ---- draw ----------------------------------------------------------------

local function wrap(s, cols)
    local lines = {}
    s = s:gsub("\r", "")
    for para in (s .. "\n"):gmatch("(.-)\n") do
        while #para > cols do
            lines[#lines + 1] = para:sub(1, cols)
            para = para:sub(cols + 1)
        end
        lines[#lines + 1] = para
    end
    return lines
end

local function header(s, s2)
    gfx.fill(0, 0, 320, 9, C_BG)
    text(s, 2, 2, C_HI)
    if s2 then text(s2, 318 - gfx.text_width(s2, SMALL), 2, C_DIM) end
end

function M:draw_list()
    neutral_palette()
    gfx.clear(0)
    header("ASSET EXPLORER", "F12/ESC CLOSES")
    local rows = 30
    if self.sel <= self.scroll then self.scroll = self.sel - 1 end
    if self.sel > self.scroll + rows then self.scroll = self.sel - rows end
    for i = 1, rows do
        local k = self.scroll + i
        local f = self.files[k]
        if not f then break end
        local y = 12 + (i - 1) * 6
        local c = k == self.sel and C_HI or C_TEXT
        if k == self.sel then gfx.fill(0, y - 1, 320, 7, C_BG) end
        local info = f.kind
        if f.kind == "PSM" and self.playing == f.name then info = "PLAYING" end
        text(f.name, 4, y, c)
        text(info, 100, y, k == self.sel and C_HI or C_DIM)
        if f.size then text(tostring(f.size), 160, y, C_DIM) end
    end
end

function M:draw_bk(v)
    v.stage:draw(not v.show_bg)
    if not v.show_bg then end
    local id = v.ids[v.sel]
    local a = id and v.bk.anims[id]
    header(v.name .. "  ANIM " .. tostring(id) .. " (" .. v.sel .. "/" .. #v.ids .. ")",
           "PAL " .. v.pal .. "/" .. v.bk.palette_count)
    if a then
        local info = string.format("SPRITES %d  START %d,%d  CHAIN %d/%d  PROB %d", #a.sprites, a.start_x,
                                   a.start_y, a.chain_hit, a.chain_no_hit, a.probability)
        gfx.fill(0, 191, 320, 9, C_BG)
        text(info, 2, 193, C_TEXT)
        if v.show_script then
            local lines = wrap(a.script, 52)
            gfx.fill(0, 10, 320, math.min(#lines, 28) * 6 + 2, 0)
            for i, l in ipairs(lines) do
                if i > 28 then break end
                text(l, 2, 11 + (i - 1) * 6, C_TEXT)
            end
        end
    end
end

function M:draw_af(v)
    gfx.set_base(v.arena.palettes[0])
    if v.altpals and v.altpals[0] then gfx.set_base(v.altpals[0]:sub(1, 48 * 3), 0) end
    menu_colors()
    if v.stage then
        v.stage:draw()
    else
        gfx.reset_palette()
        gfx.draw(v.arena.background, 0, 0, false, false, true)
    end
    local id = v.ids[v.sel]
    local m = id and v.af.moves[id]
    local har = res.HARS[v.af.fighter_id] or "?"
    header(v.name .. " " .. har:upper() .. "  MOVE " .. tostring(id) .. " (" .. v.sel .. "/" .. #v.ids .. ")",
           "HEALTH " .. v.af.health)
    if m then
        gfx.fill(0, 191, 320, 9, C_BG)
        text(string.format("INPUT %-6s DAMAGE %d  CATEGORY %d  SPRITES %d", m.move_string, m.damage, m.category,
                           #m.sprites), 2, 193, C_TEXT)
        if v.show_script then
            local lines = wrap(m.script, 52)
            gfx.fill(0, 10, 320, math.min(#lines, 28) * 6 + 2, 0)
            for i, l in ipairs(lines) do
                if i > 28 then break end
                text(l, 2, 11 + (i - 1) * 6, C_TEXT)
            end
        end
    end
end

function M:draw_pic(v)
    neutral_palette()
    local p = v.pic[v.sel]
    gfx.clear(0)
    if p then
        -- Photos are drawn in the scene's palette (the mechlab's; their own
        -- 48 colours are the pilot's HAR colours, not the face's).
        gfx.set_base(res.bk(v.name:upper() == "PLAYERS.PIC" and "MECHLAB.BK" or "MELEE.BK").palettes[0])
        if input.down("c") then gfx.set_base(p.palette, 0) end
        menu_colors()
        local s = p.sprite
        gfx.draw(s.img, (320 - s.w) // 2, (200 - s.h) // 2, false, false, true)
    end
    header(v.name .. "  PHOTO " .. v.sel .. "/" .. (v.count - 1),
           p and ((p.is_player and "PLAYER " or "") .. (p.sex == 1 and "FEMALE" or "MALE")) or "")
end

function M:draw_sounds(v)
    neutral_palette()
    gfx.clear(0)
    header("SOUNDS.DAT  " .. #res.sounds + 1 .. " SOUNDS", "ENTER PLAYS")
    local rows = 30
    if v.sel < v.scroll then v.scroll = v.sel end
    if v.sel >= v.scroll + rows then v.scroll = v.sel - rows + 1 end
    for i = 0, rows - 1 do
        local k = v.scroll + i
        local s = res.sounds[k]
        if not s then break end
        local y = 12 + i * 6
        local c = k == v.sel and C_HI or C_TEXT
        if k == v.sel then gfx.fill(0, y - 1, 320, 7, C_BG) end
        text(string.format("%3d  %6d HZ  %6d BYTES", k, s.rate, s.length), 4, y, c)
    end
end

function M:draw_text(v)
    neutral_palette()
    gfx.clear(0)
    local s = res.lang[v.sel]
    header("ENGLISH.DAT  STRING " .. v.sel .. "/" .. #res.lang, s and s.description or "")
    if s then
        local lines = wrap(s.text, 52)
        for i, l in ipairs(lines) do
            if i > 30 then break end
            text(l, 2, 12 + (i - 1) * 6, C_TEXT)
        end
    end
end

function M:draw()
    local v = self.view
    if not v then self:draw_list()
    elseif v.kind == "BK" then self:draw_bk(v)
    elseif v.kind == "AF" then self:draw_af(v)
    elseif v.kind == "PIC" then self:draw_pic(v)
    elseif v.kind == "SOUNDS" then self:draw_sounds(v)
    elseif v.kind == "TEXT" then self:draw_text(v)
    elseif v.kind == "ERR" then
        neutral_palette(); gfx.clear(0); header("ERROR"); text(v.msg or "?", 4, 20, C_HI)
    end
end

return M
