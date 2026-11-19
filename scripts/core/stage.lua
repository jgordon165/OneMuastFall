-- A running BK scene: its background, the objects playing its animations,
-- and what their scripts do each tick (spawning and removing animations,
-- sounds, music, palette tricks, slides).
--
-- One tick is 10 ms outside the arenas (OpenOMF's STATIC_TICKS). The order
-- of a tick follows OpenOMF's game_state / player.c: every object advances
-- its script, then every object applies the frame it's on; objects spawned
-- during a tick start on the next one, at their script's tick 1.

local script = require("core.script")

local Stage = {}
Stage.__index = Stage

Stage.TICK_MS = 10
Stage.LAYER_BOTTOM, Stage.LAYER_MIDDLE, Stage.LAYER_TOP = 0, 1, 2

-- PSM songs in the order the smo tag counts them (OpenOMF's PSM_END...).
Stage.SONGS = { "END.PSM", "MENU.PSM", "ARENA0.PSM", "ARENA1.PSM", "ARENA2.PSM", "ARENA3.PSM", "ARENA4.PSM" }

-- The 6-bit palette values in bpp/bpb, widened like OpenOMF's COLOR_6TO8
-- (no masking: bpp64 gives 256, i.e. all the way).
local function c6to8(v) return (v << 2) | ((v & 0x30) >> 4) end

-- The menu colours the game sets in every scene's palette (250..255).
local MENU_COLORS = { {0,0,42}, {0,0,60}, {0,0,22}, {0,63,0}, {0,30,0}, {20,63,20} }

--- opts: { startup = function(id) -> load, repeat, layer }
function Stage.new(bk, opts)
    opts = opts or {}
    local self = setmetatable({
        bk = bk, objects = {}, pending = {}, tick = 0, acc = 0, next_id = 1,
        opts = opts, rng = opts.seed or 1,
    }, Stage)
    self:load_palette(0)
    for id, a in pairs(bk.anims) do
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

function Stage:load_palette(n)
    local pal = self.bk.palettes[n] or self.bk.palettes[0]
    if pal then gfx.set_base(pal) end
    for i, c in ipairs(MENU_COLORS) do
        gfx.base_color(249 + i, c6to8(c[1]), c6to8(c[2]), c6to8(c[3]))
    end
    gfx.base_color(0, 0, 0, 0)
    gfx.reset_palette()
end

-- Deterministic random numbers (the scripts' mrx/mry).
function Stage:random(n)
    self.rng = (self.rng * 1103515245 + 12345) & 0x7FFFFFFF
    if n <= 0 then return 0 end
    return (self.rng >> 8) % n
end

local function new_sprite_state()
    return { flip_x = false, flip_y = false, timer = 0, duration = 0,
             blend_start = 255, blend_finish = 255,
             pal_ref = 0, pal_start = 0, pal_count = 0, pal_begin = 0, pal_end = 0, pal_tint = false,
             ox = 0, oy = 0 }
end

function Stage:add(anim, x, y, layer, spawned)
    local o = {
        id = self.next_id, anim = anim, sc = script.get(anim.script),
        x = x, y = y, sx = x, sy = y,           -- position and start position
        tick = 0, prev = nil, phase = "hold", repeat_ = false,
        sprite = -1, rs = new_sprite_state(),
        slide = { vx = 0, vy = 0, timer = 0 },
        layer = layer or Stage.LAYER_BOTTOM, entered = false,
    }
    self.next_id = self.next_id + 1
    if spawned then o.tick = 1; o.from_spawn = true end
    self.pending[#self.pending + 1] = o
    return o
end

function Stage:flush()
    for _, o in ipairs(self.pending) do self.objects[#self.objects + 1] = o end
    self.pending = {}
end

function Stage:remove_anim(id)
    for k, o in ipairs(self.objects) do
        if o.anim.id == id then table.remove(self.objects, k); return end
    end
end

function Stage:find(id)
    for _, o in ipairs(self.objects) do if o.anim.id == id then return o end end
end

local function select_sprite(o, f)
    local fr = o.sc.frames[f]
    o.sprite = fr and fr.sprite or -1
end

-- OpenOMF player_run_advance
local function advance(o)
    o.pending_apply = false
    if o.phase == "done" then return end
    local sc = o.sc
    if o.phase == "hold" then
        o.phase = "run"
        select_sprite(o, script.frame_at(sc, o.tick))
        o.pending_apply = true
        return
    end
    local f = script.frame_at(sc, o.tick)
    o.prev = o.tick
    local fr = f and sc.frames[f]
    if fr and fr.tags.d ~= nil and not o.disable_d then
        local v = fr.tags.d
        if v >= 0 then o.tick = v + 1; o.looping = true else o.tick = sc.total + v end
    else
        o.tick = o.tick + 1
    end
    f = script.frame_at(sc, o.tick)
    if not f then
        if o.repeat_ then
            o.tick, o.prev = 0, nil
            o.phase = "run"
            f = script.frame_at(sc, 0)
        else
            o.phase = "done"
            o.sprite = -1
            return
        end
    end
    if not f then return end
    if script.frame_at(sc, o.prev) ~= f then select_sprite(o, f) end
    o.pending_apply = true
end

function Stage:play_sound(o, fr)
    local t = fr.tags
    local n = t.s
    local stl = self.bk.sound_table
    local id = (stl[n] or 0) - 1
    if id < 0 then return end
    local opts = { priority = t.sp or 10 }
    if t.l then opts.volume = math.max(0, math.min(127, t.l * 2)) end
    if t.sb then opts.pan = math.max(-100, math.min(100, t.sb))
    else opts.pan = math.max(-100, math.min(100, (o.x - 160) * 100 // 160)) end
    if t.sf then opts.pitch = t.sf end
    if t.sc and t.sc ~= 0 then opts.channel = math.min(t.sc - 1, 7) end
    if t.sl then opts.pan_end = t.sl elseif t.se then opts.pan_end = t.se end
    if self.on_sound then self.on_sound(id, opts) end
    audio.sound(id, opts)
end

-- OpenOMF player_run_apply (the parts scenes use).
function Stage:apply(o)
    o.pending_apply = false
    if o.phase == "done" then return end
    local sc = o.sc
    local f = script.frame_at(sc, o.tick)
    if not f then return end
    local fr, t = sc.frames[f], sc.frames[f].tags
    local entered = script.frame_at(sc, o.prev) ~= f
    o.entered = entered

    if entered then
        o.rs = new_sprite_state()
        local rs = o.rs
        local mp = t.mp or 0
        if t.m ~= nil and mp ~= -1 then
            local mx, my = 0, 0
            if t.mx then mx = o.sx + t.mx end
            if t.my then my = o.sy + t.my end
            for _ = 1, (t.mi or 1) do
                if t.mrx then
                    local mm = t.mm or t.mrx
                    mx = self:random(320 - 2 * mm) + t.mrx
                end
                if t.mry then
                    local mm = t.mm or t.mry
                    my = self:random(320 - 2 * mm) + t.mry
                end
                self:spawn(t.m, mx, my, mp)
            end
        end
        if t.md then self:remove_anim(t.md) end
        if t.smo then
            if t.smo == 0 then audio.stop_music()
            else
                local song = Stage.SONGS[t.smo]
                if song and not self.no_music then audio.music(song, true) end
            end
        end
        if t.smf then audio.stop_music() end
        if t.s then self:play_sound(o, fr) end

        if t.bs then rs.blend_start = t.bs end
        if t.bf then rs.blend_finish = t.bf end
        if t.bpd then rs.pal_ref = t.bpd end
        if t.bpn then rs.pal_count = t.bpn end
        if t.bps then rs.pal_start = t.bps end
        if t.bpp then rs.pal_begin = c6to8(t.bpp); rs.pal_end = rs.pal_begin end
        if t.bpb then rs.pal_begin = c6to8(t.bpb) end
        if t.bz then rs.pal_tint = true end
        rs.ox, rs.oy = t.ox or 0, t.oy or 0
        rs.glow = t.br ~= nil
        rs.translucent = t.bt ~= nil
        if t.y and t.y ~= true then o.y_percent = t.y / 100 end

        -- slides: x= / y= set the position relative to the start, and if a
        -- later frame sets it again, move there evenly in between.
        for _, axis in ipairs({ "x", "y" }) do
            local key = axis .. "="
            local v = t[key]
            if v then
                o.slide.vx, o.slide.vy = (axis == "x") and 0 or o.slide.vx, (axis == "y") and 0 or o.slide.vy
                local base = axis == "x" and o.sx or o.sy
                o[axis] = base + v
                local nk = script.next_with(sc, key, o.tick)
                if nk then
                    local nf = sc.frames[nk]
                    local span = nf.start - o.tick
                    local target = base + nf.tags[key]
                    if target ~= o[axis] and span > 0 then
                        if axis == "x" then o.slide.vx = (target - o[axis]) / span
                        else o.slide.vy = (target - o[axis]) / span end
                        o.slide.timer = span
                    end
                end
            end
        end
        if t["x+"] then o.x = o.x + t["x+"] elseif t["x-"] then o.x = o.x - t["x-"] end
        if t["y+"] then o.y = o.y + t["y+"] elseif t["y-"] then o.y = o.y - t["y-"] end

        select_sprite(o, f)
        rs.duration = fr.ticks
        if t.r then rs.flip_x = not rs.flip_x end
        if t.f then rs.flip_y = not rs.flip_y end
    end

    if o.slide.timer > 0 then
        o.x = o.x + o.slide.vx
        o.y = o.y + o.slide.vy
        o.slide.timer = o.slide.timer - 1
    end
    if not (t.d ~= nil and not o.disable_d) then o.rs.timer = o.rs.timer + 1 end
end

function Stage:spawn(id, x, y, mp)
    local a = self.bk.anims[id]
    if not a then return end
    local o = self:add(a, x + a.start_x, y + a.start_y, Stage.LAYER_BOTTOM, true)
    if a.probability == 1 then o.repeat_ = true end
    if self.on_spawn then self.on_spawn(o) end
    return o
end

-- One 10 ms tick.
function Stage:step()
    self.tick = self.tick + 1
    for _, o in ipairs(self.objects) do advance(o) end
    for _, o in ipairs(self.objects) do
        if o.phase == "hold" and not o.from_spawn then advance(o) end
        if o.pending_apply then self:apply(o) end
    end
    -- drop finished objects, then add the ones spawned this tick
    local keep = {}
    for _, o in ipairs(self.objects) do if o.phase ~= "done" then keep[#keep + 1] = o end end
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

-- Builds this frame's palette: the base, then each object's palette trick.
function Stage:palette()
    gfx.reset_palette()
    for _, o in ipairs(self.objects) do
        local rs = o.rs
        if rs.pal_count > 0 and rs.duration > 0 then
            local step = rs.timer / rs.duration
            local bp = math.floor(rs.pal_begin + (rs.pal_end - rs.pal_begin) * step)
            bp = math.max(0, math.min(255, bp))
            local s = rs.pal_start
            local e = math.min(256, s + rs.pal_count)
            if rs.pal_tint then gfx.tint(rs.pal_ref, s, e, bp) else gfx.mix(rs.pal_ref, s, e, bp) end
        end
    end
end

function Stage:draw_object(o)
    if o.sprite < 0 then return end
    local sp = o.anim.sprites[o.sprite + 1]
    if not sp then return end
    local rs = o.rs
    local fx, fy = rs.flip_x, rs.flip_y
    local x, y
    if fx then x = o.x - (sp.x + rs.ox) - sp.w else x = o.x + sp.x + rs.ox end
    if fy then y = o.y - (sp.y - rs.oy) - sp.h else y = o.y + sp.y + rs.oy end
    -- Fully faded-out frames (bs/bf both 0) aren't drawn; partial blends
    -- are drawn solid for now (docs/formats.md, "not done yet").
    if rs.blend_start == 0 and rs.blend_finish == 0 then return end
    gfx.draw(sp.img, math.floor(x), math.floor(y), fx, fy, false)
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
