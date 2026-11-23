-- A running BK scene: its background, the objects playing its animations,
-- and what their scripts do in the world (spawning and removing
-- animations, sounds, music, palette tricks). The per-object script work is
-- core/player.lua.
--
-- One tick is 10 ms outside the arenas (OpenOMF's STATIC_TICKS). The order
-- of a tick follows OpenOMF's game_state: every object advances its script,
-- then every object applies the frame it's on; objects spawned during a tick
-- start on the next one, at their script's tick 1.

local P = require("core.player")

local Stage = {}
Stage.__index = Stage

Stage.TICK_MS = 10
Stage.LAYER_BOTTOM, Stage.LAYER_MIDDLE, Stage.LAYER_TOP = 0, 1, 2

-- PSM songs in the order the smo tag counts them (OpenOMF's PSM_END...).
Stage.SONGS = { "END.PSM", "MENU.PSM", "ARENA0.PSM", "ARENA1.PSM", "ARENA2.PSM", "ARENA3.PSM", "ARENA4.PSM" }

local c6to8 = P.c6to8

-- The menu colours the game sets in every scene's palette (250..255).
local MENU_COLORS = { {0,0,42}, {0,0,60}, {0,0,22}, {0,63,0}, {0,30,0}, {20,63,20} }

--- opts: { startup = function(id, anim) -> load, repeat, layer; seed }
function Stage.new(bk, opts)
    opts = opts or {}
    local self = setmetatable({
        bk = bk, objects = {}, pending = {}, tick = 0, acc = 0, next_id = 1,
        opts = opts, rng = opts.seed or 1,
    }, Stage)
    self:load_palette(0)
    local ids = {}
    for id in pairs(bk.anims) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local a = bk.anims[id]
        local load, rep, layer = false, false, nil
        if opts.startup then load, rep, layer = opts.startup(id, a) end
        if load then
            local o = self:add(a, a.start_x, a.start_y, layer)
            o.repeat_ = rep and true or false
        end
    end
    self:flush()
    return self
end

function Stage.menu_colors()
    for i, c in ipairs(MENU_COLORS) do
        gfx.base_color(249 + i, c6to8(c[1]), c6to8(c[2]), c6to8(c[3]))
    end
end

function Stage:load_palette(n)
    local pal = self.bk.palettes[n] or self.bk.palettes[0]
    if pal then gfx.set_base(pal) end
    Stage.menu_colors()
    gfx.base_color(0, 0, 0, 0)
    gfx.reset_palette()
end

-- Deterministic random numbers (the scripts' mrx/mry, hazards).
function Stage:random(n)
    self.rng = (self.rng * 1103515245 + 12345) & 0x7FFFFFFF
    if n <= 0 then return 0 end
    return (self.rng >> 8) % n
end

function Stage:add(anim, x, y, layer, spawned)
    local o = P.new(anim, x, y, self, { layer = layer or Stage.LAYER_BOTTOM, stl = self.bk.sound_table })
    o.sx, o.sy = x, y
    o.id = self.next_id
    self.next_id = self.next_id + 1
    if spawned then P.init_spawned(o) end
    self.pending[#self.pending + 1] = o
    return o
end

function Stage:flush()
    for _, o in ipairs(self.pending) do self.objects[#self.objects + 1] = o end
    self.pending = {}
end

function Stage:find(id)
    for _, o in ipairs(self.objects) do if o.anim.id == id then return o end end
end

-- ---- what scripts do in the world (the ctx of core/player.lua) ---------------

function Stage:spawn(parent, id, x, y, vx, vy, mp, mg)
    local a = self.bk.anims[id]
    if not a then return end
    local o = self:add(a, x + a.start_x, y + a.start_y, Stage.LAYER_BOTTOM, true)
    if a.probability == 1 then o.repeat_ = true end
    if self.on_spawn then self.on_spawn(o) end
    return o
end

function Stage:destroy(parent, id)
    for k, o in ipairs(self.objects) do
        if o.anim.id == id then table.remove(self.objects, k); return end
    end
end
Stage.remove_anim = function(self, id) return self:destroy(nil, id) end

function Stage:music(n)
    if n == 0 then audio.stop_music(); return end
    local song = Stage.SONGS[n]
    if song and not self.no_music then audio.music(song, true) end
end

-- The s tag: the object's sound table entry n − 1 in SOUNDS.DAT, with the
-- frame's volume, panning, pitch and channel (player.c).
function Stage.sound_opts(o, t)
    local opts = { priority = t.sp or 10 }
    if t.l then opts.volume = math.max(0, math.min(127, t.l * 2)) end
    if t.sb then opts.pan = math.max(-100, math.min(100, t.sb))
    else opts.pan = math.max(-100, math.min(100, math.floor((o.x - 160) * 100 / 160))) end
    if t.sf then opts.pitch = t.sf end
    if t.sc and t.sc ~= 0 then opts.channel = math.min(t.sc - 1, 7) end
    if t.sl then opts.pan_end = t.sl elseif t.se then opts.pan_end = t.se end
    return opts
end

function Stage:sound(o, fr)
    local stl = o.stl or self.bk.sound_table
    local id = (stl[fr.tags.s] or 0) - 1
    if id < 0 then return end
    local opts = Stage.sound_opts(o, fr.tags)
    if self.on_sound then self.on_sound(id, opts) end
    audio.sound(id, opts)
end

-- ---- ticking -----------------------------------------------------------------

function Stage:step()
    self.tick = self.tick + 1
    for _, o in ipairs(self.objects) do P.tick_advance(o) end
    for _, o in ipairs(self.objects) do P.tick_apply(o) end
    local keep = {}
    for _, o in ipairs(self.objects) do if not o.finished then keep[#keep + 1] = o end end
    self.objects = keep
    self:flush()
end

-- Runs as many ticks as `dt` milliseconds hold.
function Stage:update(dt)
    self.acc = self.acc + dt
    local n = 0
    while self.acc >= Stage.TICK_MS and n < 50 do
        self.acc = self.acc - Stage.TICK_MS
        self:step()
        n = n + 1
    end
end

-- This frame's palette: the base, then each object's palette trick.
function Stage:palette()
    gfx.reset_palette()
    for _, o in ipairs(self.objects) do P.palette(o) end
end

function Stage:glow_remap()
    local r = self.bk.remaps and self.bk.remaps[0]
    return r and r[3]
end

function Stage:draw_object(o)
    P.draw(o, self:glow_remap())
end

function Stage:draw(no_background)
    self:palette()
    if not no_background then gfx.draw(self.bk.background, 0, 0, false, false, true) end
    for layer = Stage.LAYER_BOTTOM, Stage.LAYER_TOP do
        for _, o in ipairs(self.objects) do
            if o.layer == layer then self:draw_object(o) end
        end
    end
end

return Stage
