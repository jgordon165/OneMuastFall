-- The animation player: runs one object's animation script tick by tick.
--
-- Every moving thing in OMF:2097 is an object playing an animation (a BK
-- scene animation, a HAR move, a projectile...). This module is the part
-- they share, after OpenOMF's game/protos/player.c and object.c:
--
--   advance(o)   move the script on one tick (follow d jumps, end/repeat)
--   apply(o)     run the frame: on entering it its tags fire once; position
--                tags, slides and the sprite timer run every tick
--   tick(o)      advance + apply, `stride` times
--
-- What an object does in the world (spawning, sounds, the enemy...) goes
-- through its `ctx`, the scene that owns it:
--   ctx:spawn(o, id, x, y, vx, vy, mp, mg)   ctx:destroy(o, id)
--   ctx:sound(o, frame)   ctx:music(n)   ctx:random(n)
--   ctx.walls (true in arenas: HAR position clamped between 20 and 300)
-- and through the object's own hooks:
--   o.on_finish(o)  o.on_bj(o, id)  o.enemy (the other HAR)

local script = require("core.script")

local P = {}

P.LEFT_WALL, P.RIGHT_WALL, P.FLOOR = 20, 300, 190

local function c6to8(v) return (v << 2) | ((v & 0x30) >> 4) end
P.c6to8 = c6to8

local function new_sprite_state()
    return { flip_x = false, flip_y = false, timer = 0, duration = 0,
             blend_start = 255, blend_finish = 255,
             pal_ref = 0, pal_start = 0, pal_count = 0, pal_begin = 0, pal_end = 0, pal_tint = false,
             ox = 0, oy = 0 }
end

--- A new object playing `anim` (a BK/AF animation table) at x, y.
function P.new(anim, x, y, ctx, opts)
    opts = opts or {}
    local o = {
        anim = anim, ctx = ctx,
        x = x, y = y, vx = 0, vy = 0, cvx = 0, cvy = 0, gravity = 0,
        dir = opts.dir or 1,
        layer = opts.layer or 0,
        pal_offset = opts.pal_offset or 0, pal_limit = opts.pal_limit or 255,
        stl = opts.stl,
        stride = 1, halt = false, finished = false,
        x_percent = 1, y_percent = 1,
    }
    P.set_animation(o, anim)
    return o
end

local function reset_reader(o)
    o.tick, o.prev = 0, nil
    o.phase = "hold"
    o.disable_d = false
    o.pending_apply = false
end

function P.reload(o, s)
    o.sc = script.get(s)
    reset_reader(o)
    o.reverse = false
    o.slide = { vx = 0, vy = 0, timer = 0 }
    o.q_counter, o.q_val, o.can_hit = 0, 0, false
    o.rs = o.rs or new_sprite_state()
end

--- Switch to another animation (OpenOMF object_set_animation).
function P.set_animation(o, anim)
    o.anim = anim
    o.custom = nil
    P.reload(o, anim.script)
    o.from_spawn = false
    o.sprite = -1
    o.rs = new_sprite_state()
end

--- Replace the script, keeping the animation's sprites (custom strings:
--- hit reactions, throws, block stun).
function P.set_custom_string(o, s)
    o.custom = s
    P.reload(o, s)
end

--- Spawned objects skip tick 0.
function P.init_spawned(o)
    o.from_spawn = true
    reset_reader(o)
    o.tick = 1
end

--- Jump the script to a tick; negative counts from the end.
function P.set_tick_pos(o, t)
    if o.halt then return end
    o.prev = o.tick
    if t < 0 then t = o.sc.total + t end
    o.tick = t
end

function P.frame(o)
    local f = script.frame_at(o.sc, o.tick)
    return f and o.sc.frames[f]
end

--- Is `tag` set on the frame playing now? (player_frame_isset)
function P.isset(o, tag)
    local f = P.frame(o)
    return f ~= nil and f.tags[tag] ~= nil
end

function P.get(o, tag)
    local f = P.frame(o)
    local v = f and f.tags[tag]
    if v == nil or v == true then return 0 end
    return v
end

function P.len_ticks(o) return o.sc.total end
function P.current_tick(o) return o.tick end

function P.last_frame_letter(o)
    local f = P.frame(o)
    return f and script.letter(f.sprite) or nil
end

local function select_sprite(o, f)
    if o.sprite_override then o.sprite = o.sprite_override; return end
    local fr = f and o.sc.frames[f]
    if not fr then o.sprite = -1; return end
    if o.anim.sprites[fr.sprite + 1] then o.sprite = fr.sprite else o.sprite = -1 end
    o.rs.flip_x, o.rs.flip_y = false, false
end

-- player_run_advance
function P.advance(o)
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
        o.tick = o.tick + (o.reverse and -1 or 1)
    end
    f = script.frame_at(sc, o.tick)
    if not f then
        if o.repeat_ then
            reset_reader(o)
            o.phase = "run"
            f = script.frame_at(o.sc, 0)
        else
            o.phase = "done"
            if o.on_finish then o.on_finish(o) end
            -- the finish hook may have started something new
            if o.phase == "done" then
                o.sprite = -1
                o.finished = true
            end
            return
        end
    end
    if not f then return end
    if script.frame_at(o.sc, o.prev) ~= f then select_sprite(o, f) end
    o.pending_apply = true
end

-- player_run_apply
function P.apply(o)
    o.pending_apply = false
    if o.phase == "done" then return end
    local sc = o.sc
    local fi = script.frame_at(sc, o.tick)
    if not fi then return end
    local fr = sc.frames[fi]
    local t = fr.tags
    local ctx = o.ctx
    local enemy = o.enemy
    local mp = t.mp or 0

    -- every tick ------------------------------------------------------------
    if t.e and enemy and not t.am then
        o.vx, o.vy = 0, 0
        o.x, o.y = enemy.x, enemy.y
        o.dir = -enemy.dir
    end
    if enemy then enemy.crossup_protection = t.ag ~= nil end
    if t.ar then o.dir = -o.dir end
    o.wall_hit = nil
    local trans_x, trans_y = 0, 0
    if t["y-"] then trans_y = -t["y-"] elseif t["y+"] then trans_y = t["y+"] end
    if t["x-"] then trans_x = -t["x-"] * o.dir elseif t["x+"] then trans_x = t["x+"] * o.dir end

    local entered = script.frame_at(sc, o.prev) ~= fi
    o.entered = entered
    if entered then
        o.rs = new_sprite_state()
        local rs = o.rs
        if t.ac then o.dir = (o.x > 160) and -1 or 1 end
        o.hit_pixels_disabled = t.n ~= nil
        if t.bj and o.on_bj then
            o.on_bj(o, t.bj)
            return
        end
        if t.bm and o.on_bm then
            local r = o.on_bm(o, t, trans_x)
            if r == "walk" then return end
            trans_x = 0
        end
    end
    if t.h then o.vx, o.vy, o.cvx, o.cvy = 0, 0, 0, 0 end
    local ab = t.ab ~= nil
    if t.g then o.vy = 0; o.y = P.FLOOR end
    if t.ad and o.on_ad then trans_x = o.on_ad(o, trans_x) end
    if trans_x ~= 0 or trans_y ~= 0 then
        local sx = (mp & 0x20 ~= 0) and -1 or 1
        if t.v then
            o.vx = trans_x * sx * (o.hvel_mod or 1)
            o.vy = trans_y * (o.hvel_mod or 1)
        else
            o.x = o.x + trans_x * sx
            if not ab and o.is_har then
                if o.x < P.LEFT_WALL then
                    if t.e and enemy then enemy.x = enemy.x + (P.LEFT_WALL - o.x) end
                    o.wall_hit = "left"
                elseif o.x > P.RIGHT_WALL then
                    if t.e and enemy then enemy.x = enemy.x - (o.x - P.RIGHT_WALL) end
                    o.wall_hit = "right"
                end
            end
            o.y = o.y + trans_y
        end
    end
    if o.slide.timer > 0 then
        o.x = o.x + o.slide.vx
        o.y = o.y + o.slide.vy
        o.slide.timer = o.slide.timer - 1
    end
    if o.is_har and enemy and not ab then
        o.x = math.max(P.LEFT_WALL, math.min(P.RIGHT_WALL, o.x))
    end
    if t.q then
        o.q_val = t.q
        if o.q_val > o.q_counter or o.q_val == 1 then o.can_hit = true end
    end

    -- on entering the frame ---------------------------------------------------
    if entered then
        local rs = o.rs
        if t.m ~= nil and mp ~= -1 and ctx and ctx.spawn then
            local mx, my, vx, vy = 0, 0, 0, 0
            if t.mx then mx = o.sx + t.mx * o.dir end
            if t.my then my = o.sy + t.my end
            if t.ma then vx, vy = math.cos(t.ma), math.sin(t.ma) end
            local mg = t.mg or 0
            for _ = 1, (t.mi or 1) do
                if t.mrx then
                    local mm = t.mm or t.mrx
                    mx = ctx:random(320 - 2 * mm) + t.mrx
                end
                if t.mry then
                    local mm = t.mm or t.mry
                    my = ctx:random(320 - 2 * mm) + t.mry
                end
                ctx:spawn(o, t.m, mx, my, vx, vy, mp, mg)
            end
        end
        if t.md and ctx and ctx.destroy then ctx:destroy(o, t.md) end
        if t.smo and ctx and ctx.music then ctx:music(t.smo) end
        if t.smf and ctx and ctx.music then ctx:music(0) end
        if t.s and ctx and ctx.sound then ctx:sound(o, fr) end

        if t.bb then o.shake_v = t.bb end
        if t.bl then o.shake_h = t.bl end
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

        if t["x="] or t["y="] then o.vx, o.vy = 0, 0 end
        for _, axis in ipairs({ "x", "y" }) do
            local key = axis .. "="
            local v = t[key]
            if v then
                local base = axis == "x" and o.sx or o.sy
                local mul = axis == "x" and o.dir or 1
                o[axis] = base + v * mul
                local nk = script.next_with(sc, key, o.tick)
                if nk then
                    local nf = sc.frames[nk]
                    local span = nf.start - o.tick
                    local target = base + nf.tags[key] * mul
                    if target ~= o[axis] and span > 0 then
                        if axis == "x" then o.slide.vx = (target - o[axis]) / span
                        else o.slide.vy = (target - o[axis]) / span end
                        o.slide.timer = span
                    end
                end
            end
        end

        select_sprite(o, fi)
        rs.duration = fr.ticks
        if t.r then rs.flip_x = not rs.flip_x end
        if t.f then rs.flip_y = not rs.flip_y end
    end

    if t.bu then
        if o.vy < 0 then o.vx = (160 - o.x) / (o.vy * -2) else o.x = 160 end
    end
    if t.cg then
        o.disable_d = o.y < P.FLOOR
        if o.y >= P.FLOOR then
            o.y, o.vy = P.FLOOR, 0
            if o.on_cg then o.on_cg(o) end
        end
    end
    if not (t.d ~= nil and not o.disable_d) then o.rs.timer = o.rs.timer + 1 end
end

-- object_dynamic_tick_advance / _apply, for objects with a stride
function P.tick_advance(o)
    if o.halt_ticks and o.halt_ticks > 0 then
        o.halt_ticks = o.halt_ticks - 1
        o.halt = o.halt_ticks > 0
    end
    if not o.halt then P.advance(o) end
end

function P.tick_apply(o)
    if o.phase == "hold" and not o.halt and not o.from_spawn then P.advance(o) end
    if o.pending_apply then
        P.apply(o)
        for _ = 2, o.stride do
            P.advance(o)
            if o.pending_apply then P.apply(o) end
        end
    end
end

function P.tick(o)
    P.tick_advance(o)
    P.tick_apply(o)
end

--- The sprite showing now, and where it's drawn: sprite, x, y, flip_x, flip_y.
function P.placement(o)
    if o.sprite < 0 then return nil end
    local sp = o.anim.sprites[o.sprite + 1]
    if not sp then return nil end
    local rs = o.rs
    local flip_x = rs.flip_x
    if o.dir < 0 then flip_x = not flip_x end
    local w, h = sp.w * o.x_percent, sp.h * o.y_percent
    local x, y
    if rs.flip_y then
        y = o.y - (sp.y - rs.oy) * o.y_percent - h
    else
        y = o.y + (sp.y + rs.oy) * o.y_percent
    end
    if flip_x then
        x = o.x - (sp.x + rs.ox) * o.x_percent - w
    else
        x = o.x + (sp.x + rs.ox) * o.x_percent
    end
    return sp, x, y, flip_x, rs.flip_y
end

function P.opacity(o)
    local rs = o.rs
    local op = rs.blend_finish
    if rs.duration > 0 then
        local m = rs.timer / rs.duration
        op = rs.blend_start + (rs.blend_finish - rs.blend_start) * m
    end
    return math.max(0, math.min(255, math.floor(op)))
end

--- Draws the object; `glow_remap` is the scene's remap table for br.
function P.draw(o, glow_remap)
    local sp, x, y, fx, fy = P.placement(o)
    if not sp then return end
    local op = P.opacity(o)
    if op <= 0 then return end
    local remap = (o.rs.glow and glow_remap) or nil
    gfx.mark(true)   -- a sprite, for the upscaler's "sprites only"
    gfx.draw(sp.img, math.floor(x), math.floor(y), fx, fy, false, remap, o.pal_offset, o.pal_limit, op)
    gfx.mark(false)
end

--- This frame's palette trick (bps/bpn/bpd/bpp/bpb/bz), applied to the
--- working palette.
function P.palette(o)
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

return P
