-- HARs: the fighting robots. One per player, built from a FIGHTRn.AF.
--
-- The logic follows OpenOMF's game/objects/har.c (itself matched against
-- MASTER.DAT): the state machine, walking/jumping physics, the input buffer
-- that turns joystick motions into the AF move strings, hit detection by
-- the moves' collision points against the opponent's sprite pixels,
-- blocking, damage and stun ("endurance"), knock-downs, defeat and victory.
--
-- A HAR is a core/player.lua object (it plays one AF move at a time) with
-- its fighting state in `o.h`. The arena (scenes/arena.lua) calls, every
-- tick: act (input), move (physics), collide, tick (before the frame is
-- applied).

local P = require("core.player")

local H = {}

-- Moves every HAR has (OpenOMF resources/animation.h)
H.ANIM = {
    JUMPING = 1, STANDUP = 2, STUNNED = 3, CROUCHING = 4, STANDING_BLOCK = 5, CROUCHING_BLOCK = 6,
    BURNING_OIL = 7, BLOCKING_SCRAPE = 8, DAMAGE = 9, WALKING = 10, IDLE = 11,
    SCRAP_METAL = 12, BOLT = 13, SCREW = 14, VICTORY = 48, DEFEAT = 49,
}
local A = H.ANIM

-- Move categories (the AF's category byte)
H.CAT = { MISC = 0, CLOSE = 2, LOW = 4, MEDIUM = 5, HIGH = 6, JUMPING = 7, PROJECTILE = 8, BASIC = 9,
          BK_HAZARD = 10, VICTORY = 11, SCRAP = 12, DESTRUCTION = 13 }
local CAT = H.CAT

-- States, ordered as in OpenOMF (the comparisons depend on the order).
H.STATE = { NONE = 0, STANDING = 1, WALKTO = 2, WALKFROM = 3, CROUCHING = 4, CROUCHBLOCK = 5,
            JUMPING = 6, RECOIL = 7, STANDING_UP = 8, STUNNED = 9, BLOCKSTUN = 10, VICTORY = 11,
            DEFEAT = 12, SCRAP = 13, DESTRUCTION = 14, WALLDAMAGE = 15, DONE = 16 }
local S = H.STATE

local HEIGHT_STANDING, HEIGHT_CROUCHING = 55, 30
local INPUT_BUFFER_TICKS = 3
local STUN_RECOVERY = 256 * 18 // 250
local STUN_RECOVERY_BLOCKING = 256 * 27 // 250
local FLOOR, LEFT_WALL, RIGHT_WALL = P.FLOOR, P.LEFT_WALL, P.RIGHT_WALL

local NAMES = { [0] = "JAGUAR", "SHADOW", "THORN", "PYROS", "ELECTRA", "KATANA", "SHREDDER", "FLAIL",
                "GARGOYLE", "CHRONOS", "NOVA" }
H.NAMES = NAMES

local function is_airborne(o) return o.y < FLOOR end
H.is_airborne = is_airborne

local function move_of(o, id) return o.h.af.moves[id] end
local function cur_id(o) return o.anim.id end

-- ---- creation ------------------------------------------------------------------

-- Pick each move's script the way a one/two player match does: the first
-- extra string ("normal" mode) when there is one, except for the moves
-- whose extra strings are arm/leg speeds; "A1" scripts disable the move.
local function prepare_moves(af)
    for _, m in pairs(af.moves) do
        local sel = m.extra_string_selector or 0
        if #m.extra > 0 and sel ~= 1 and sel ~= 2 then
            local s = m.extra[1]
            if s and #s > 0 and s ~= "!" then m.script = s end
        end
        if m.script == "A1" then m.move_string = "!" end
    end
end

--- af: an omf.af() table (owned by this HAR); pilot: game/pilots.lua entry.
function H.new(arena, af, player_id, pilot, x, dir)
    prepare_moves(af)
    local idle = af.moves[A.IDLE]
    local o = P.new(idle, x, FLOOR, arena, {
        dir = dir, layer = 1, stl = af.sound_table,
        pal_offset = player_id * 48, pal_limit = (player_id + 1) * 48 - 1,
    })
    o.is_har = true
    o.sx, o.sy = x, FLOOR
    local ag, en = pilot.agility, pilot.endurance
    local h = {
        af = af, id = af.fighter_id, player_id = player_id, pilot = pilot,
        state = S.STANDING, executing_move = false,
        damage_done = false, damage_received = false, air_attacked = false,
        is_wallhugging = false, is_grabbed = false, jump_delay = 0,
        last_damage_value = 0, last_stun_value = 0,
        punch_valid = 0, kick_valid = 0,
        throw_duration = 0, block_duration = 0, in_stasis_ticks = 0,
        inputs = "5555555555", input_change_tick = 0, last_input = "5",
        rehits = {}, rehit_combo = false,
        stun_timer = 0, height = HEIGHT_STANDING, close = false,
        disabled = {},
    }
    o.h = h
    -- stats (OpenOMF har_create, one/two player formulas)
    h.endurance_max = af.endurance * 36 * (en + 16) // 23 // 10
    h.stun_factor = 192 * (en + 30) // 25
    h.health_max = math.floor((af.health * (en + 25) // 35) * 1.1)
    h.health = h.health_max
    h.endurance = 0
    local hmod, vmod = (ag + 35) / 45, (ag + 20) / 30
    o.hvel_mod, o.vvel_mod = hmod, vmod
    h.jump_speed = hmod * (af.jump_speed / 256) * (216 / 256)
    h.superjump_speed = hmod * (af.jump_speed / 256) * (266 / 256)
    h.fall_speed = vmod * (af.fall_speed / 256)
    h.fwd_speed = vmod * (af.forward_speed / 256)
    h.back_speed = vmod * (af.reverse_speed / 256)
    h.stride = math.max(1, (ag + 20) // 30)
    o.gravity = h.fall_speed

    o.on_finish = H.finished
    o.on_bj = function(obj, id)
        H.set_ani(obj, id, false)
        if id == A.STANDUP and obj.enemy then H.face_enemy(obj, obj.enemy) end
    end
    o.on_cg = function(obj) obj.h.state = S.STANDING end
    o.on_ad = function(obj, trans_x)
        local c = obj.h.inputs:sub(1, 1)
        local nd = obj.dir
        if c == "4" or c == "7" or c == "1" then nd = -1 elseif c == "6" or c == "9" or c == "3" then nd = 1 end
        if nd ~= obj.dir then obj.dir = nd; obj.vx = -obj.vx; return -trans_x end
        return trans_x
    end
    H.set_ani(o, A.IDLE, true)
    o.stride = h.stride
    return o
end

--- Back to the start of a round (har_reset).
function H.reset(o, x, dir)
    local h = o.h
    o.gravity = h.fall_speed
    h.close = false
    h.state = S.STANDING
    h.executing_move = false
    h.air_attacked = false
    h.is_wallhugging = false
    h.is_grabbed = false
    h.jump_delay = 0
    h.health = h.health_max
    h.endurance = 0
    h.in_stasis_ticks = 0
    h.throw_duration = 0
    h.block_duration = 0
    h.rehits, h.rehit_combo = {}, false
    o.x, o.y, o.sx, o.sy, o.vx, o.vy = x, FLOOR, x, FLOOR, 0, 0
    o.dir = dir
    o.halt, o.halt_ticks = false, 0
    H.set_ani(o, A.IDLE, true)
    o.stride = h.stride
end

-- ---- animation helpers -------------------------------------------------------------

function H.set_ani(o, id, rep)
    local h = o.h
    if cur_id(o) == A.WALKING and id == A.WALKING and o.phase ~= "done" then return end
    local m = move_of(o, id)
    if not m then return end
    P.set_animation(o, m)
    if m.category == CAT.JUMPING and h.state < S.VICTORY then h.state = S.JUMPING end
    if m.category == CAT.LOW or id == A.CROUCHING or id == A.CROUCHING_BLOCK then
        h.height = HEIGHT_CROUCHING
    else
        h.height = HEIGHT_STANDING
    end
    o.repeat_ = rep and true or false
    o.stride = 1
    o.finished = false
    P.tick(o)
    o.sx, o.sy = o.x, o.y
    h.damage_done = false
    h.damage_received = false
    h.executing_move = false
end

function H.face_enemy(o, e)
    if o.h.in_stasis_ticks > 0 then return end
    o.dir = (o.x > e.x) and -1 or 1
end

local FLIP = { ["7"] = "9", ["4"] = "6", ["1"] = "3", ["9"] = "7", ["6"] = "4", ["3"] = "1" }
local function flip_input(c, dir)
    if dir < 0 then return FLIP[c] or c end
    return c
end
local function flip_inputs(s, dir)
    if dir > 0 then return s end
    return (s:gsub(".", function(c) return FLIP[c] or c end))
end
H.flip_input = flip_input

local function last_input(o) return flip_input(o.h.inputs:sub(1, 1), o.dir) end

function H.is_idle_grounded(o)
    local id = cur_id(o)
    return (id == A.IDLE or id == A.CROUCHING or id == A.WALKING) and o.ctx:hars_alive()
end
local is_idle_grounded = H.is_idle_grounded

local function is_idle_air(o) return cur_id(o) == A.JUMPING and o.ctx:hars_alive() end

function H.is_crouching(h) return h.state == S.CROUCHING or h.state == S.CROUCHBLOCK end
function H.is_walking(h) return h.state == S.WALKTO or h.state == S.WALKFROM end

function H.is_blocking(o, move)
    local id = cur_id(o)
    if not is_idle_grounded(o) and id ~= A.STANDING_BLOCK and id ~= A.CROUCHING_BLOCK then return false end
    local h = o.h
    if h.in_stasis_ticks > 0 then return false end
    local li = h.last_input
    if o.crossup_protection then
        if li == "6" then li = "4" elseif li == "3" then li = "1" end
    end
    if move.category == CAT.CLOSE then return false end
    if move.category == CAT.LOW then return li == "1" end
    if move.category == CAT.JUMPING then return li == "4" end
    return li == "1" or li == "4"
end

local function in_range(o, e, move)
    local check = move
    if move.play_if_hit ~= 0 then
        local nm = move_of(o, move.play_if_hit)
        if nm and nm.category == CAT.CLOSE then check = nm end
    end
    if check.successor ~= 0 then
        -- throws use the successor field as their reach (throw range 100%)
        if math.abs(o.x - e.x) > check.successor then return false end
    end
    return true
end

function H.is_invincible(o, move)
    if P.isset(o, "zz") then return true end
    local c, id = move.category, cur_id(o)
    if c == CAT.CLOSE then
        return P.isset(o, "zg") or id == A.DAMAGE or id == A.STANDING_BLOCK or id == A.CROUCHING_BLOCK
            or id == A.STANDUP
    elseif c == CAT.LOW then return P.isset(o, "zl")
    elseif c == CAT.MEDIUM then return P.isset(o, "zm")
    elseif c == CAT.HIGH then return P.isset(o, "zh")
    elseif c == CAT.JUMPING then return P.isset(o, "zj")
    elseif c == CAT.PROJECTILE then return P.isset(o, "zp")
    end
    return false
end

-- ---- input and moves ------------------------------------------------------------------

local function add_input(h, c)
    if h.inputs:sub(1, 1) == c then return false end
    h.inputs = (c .. h.inputs):sub(1, 10)
    return true
end

local function chain_allowed(o, move)
    local h = o.h
    local allowed_idle = (move.pos_constraint & 0x2) == 0     -- POS_CANNOT_PERFORM
    if h.disabled[move.id] then return false end
    if not h.is_wallhugging and (move.pos_constraint & 0x1) ~= 0 then return false end   -- POS_WALL
    if P.isset(o, "jn") and move.id == P.get(o, "jn") then return true end
    local c = move.category
    local ok = false
    if c == CAT.JUMPING then
        ok = P.isset(o, "jz") or P.isset(o, "jj") or (is_idle_air(o) and allowed_idle and not h.air_attacked)
    elseif c == CAT.CLOSE then
        if P.isset(o, "jg") or (is_idle_grounded(o) and allowed_idle) then
            local e = o.enemy
            ok = e and e.y == FLOOR and not H.is_invincible(e, move) and in_range(o, e, move)
        end
    elseif c == CAT.LOW then ok = P.isset(o, "jl") or (is_idle_grounded(o) and allowed_idle)
    elseif c == CAT.MEDIUM then ok = P.isset(o, "jm") or (is_idle_grounded(o) and allowed_idle)
    elseif c == CAT.HIGH then ok = P.isset(o, "jh") or (is_idle_grounded(o) and allowed_idle)
    elseif c == CAT.SCRAP then ok = P.isset(o, "jf") and h.state ~= S.DONE and allowed_idle
        and o.ctx:match_over()
    elseif c == CAT.DESTRUCTION then ok = P.isset(o, "jf2") and allowed_idle and o.ctx:match_over()
    end
    return ok
end

-- The AF's move list in id order, so the earliest matching move wins.
local function move_ids(af)
    if not af._ids then
        local ids = {}
        for id in pairs(af.moves) do if id > A.SCREW then ids[#ids + 1] = id end end
        table.sort(ids)
        af._ids = ids
    end
    return af._ids
end

local function match_prefix(o, prefix, inputs)
    local h = o.h
    for _, id in ipairs(move_ids(h.af)) do
        local m = h.af.moves[id]
        local ms = m.move_string
        if #ms > 0 and ms:sub(1, 1) == prefix and (#ms == 1 or inputs:sub(1, #ms - 1) == ms:sub(2)) then
            if chain_allowed(o, m) then
                if #ms > 1 then h.inputs = "" end
                return m
            end
        end
    end
    return nil
end

local function match_move(o, inputs)
    local h = o.h
    local m
    if h.punch_valid > 0 then m = match_prefix(o, "P", inputs) end
    if not m and h.kick_valid > 0 then m = match_prefix(o, "K", inputs) end
    if m then h.punch_valid, h.kick_valid = 0, 0 end
    return m
end

local function change_state(old, can_jump, c)
    local st
    if c == "1" then st = S.CROUCHBLOCK
    elseif c == "2" or c == "3" then st = S.CROUCHING
    elseif c == "5" then st = S.STANDING
    elseif c == "4" then st = S.WALKFROM
    elseif c == "6" then st = S.WALKTO
    elseif c == "7" or c == "8" or c == "9" then st = can_jump and S.JUMPING or nil
    else st = S.STANDING end
    if st and st ~= old then return st end
    return nil
end

--- A stick position the controller saw between ticks: into the move
--- buffer only (no walking or jumping from it).
function H.push_input(o, dir)
    local h = o.h
    if add_input(h, dir) then
        h.input_change_tick = o.ctx.tick
        h.last_input = flip_input(h.inputs:sub(1, 1), o.dir)
    end
end

--- One tick of input. `dir` is the stick as a numpad digit in screen terms
--- ("6" = right, "5" = nothing); punch/kick: pressed this tick.
function H.act(o, dir, punch, kick)
    local h, e, ctx = o.h, o.enemy, o.ctx
    if is_idle_grounded(o) and math.abs(o.x - e.x) > 4 then H.face_enemy(o, e) end
    local changed = add_input(h, dir)
    local staleness = ctx.tick - h.input_change_tick
    if changed then
        h.input_change_tick = ctx.tick
        h.last_input = flip_input(h.inputs:sub(1, 1), o.dir)
    end
    if h.jump_delay > 0 then
        h.jump_delay = h.jump_delay - 1
        h.input_change_tick = ctx.tick
    end
    if o.halt then return end
    if ctx.state == "starting" then return end
    if kick then h.kick_valid = INPUT_BUFFER_TICKS elseif punch then h.punch_valid = INPUT_BUFFER_TICKS end

    if h.endurance < 0 then
        -- stunned: mash to recover faster
        if h.kick_valid > 0 or h.punch_valid > 0 then
            h.endurance = h.endurance + 512
            h.kick_valid, h.punch_valid = 0, 0
        end
        return
    end

    -- you have 9 ticks between inputs to complete a motion
    local inputs
    if staleness > 9 then inputs = flip_input(h.inputs:sub(1, 1), o.dir)
    else inputs = flip_inputs(h.inputs, o.dir) end
    local m = match_move(o, inputs)
    if P.isset(o, "jn") and P.isset(o, "cw") and e.h.state == S.WALLDAMAGE then
        m = move_of(o, P.get(o, "jn"))
    end

    if m then
        h.rehits = {}
        if H.is_walking(h) then h.state = S.STANDING end
        H.set_ani(o, m.id, false)
        h.executing_move = true
        if m.category == CAT.SCRAP then h.state = S.SCRAP
        elseif m.category == CAT.DESTRUCTION then h.state = S.DESTRUCTION
        else
            if is_airborne(o) then h.air_attacked = true end
        end
        if h.state == S.NONE then
            if m.category == CAT.HIGH or m.category == CAT.MEDIUM or m.category == CAT.CLOSE then
                h.state = S.STANDING
            elseif m.category == CAT.LOW then
                h.state = S.CROUCHING
            end
        end
        ctx:event("attack", o, m)
        return
    end

    if h.executing_move then
        if o.y < FLOOR and h.state < S.JUMPING then h.state = S.JUMPING end
        return
    end

    local li = last_input(o)
    if is_airborne(o) then
        if h.state == S.NONE then h.state = S.JUMPING end
        if is_idle_air(o) and (li == "4" or li == "6" or li == "1" or li == "3") then
            if (o.x > e.x and o.dir ~= -1) or (o.x <= e.x and o.dir ~= 1) then H.face_enemy(o, e) end
        end
        return
    end
    if not (is_idle_grounded(o) or is_idle_air(o)) then return end

    local ns = change_state(h.state, h.jump_delay == 0, li)
    if not ns then return end
    h.state = ns
    if ns == S.CROUCHBLOCK or ns == S.CROUCHING then
        H.set_ani(o, A.CROUCHING, true)
        o.vx, o.vy = 0, 0
    elseif ns == S.STANDING then
        H.set_ani(o, A.IDLE, true)
        o.stride = h.stride
        o.vx, o.vy = 0, 0
    elseif ns == S.WALKTO or ns == S.WALKFROM then
        H.set_ani(o, A.WALKING, true)
        o.stride = h.stride
    elseif ns == S.JUMPING then
        H.set_ani(o, A.JUMPING, false)
        local vx, vy = 0, h.jump_speed
        if li == "9" then
            vx = h.fwd_speed * o.dir
            P.set_tick_pos(o, 110)
            o.stride = 7
        elseif li == "7" then
            o.reverse = true
            P.set_tick_pos(o, -110)
            vx = -h.back_speed * o.dir
            o.stride = 7
        elseif li == "8" then
            P.set_tick_pos(o, 110)
            if h.id == 8 then o.stride = 7 end   -- Gargoyle
        end
        local prev = h.inputs:sub(2, 2)
        if staleness <= 6 and (prev == "1" or prev == "2" or prev == "3") then
            vy = h.superjump_speed     -- jumping out of a crouch goes higher
        end
        o.vx, o.vy = vx, vy
        ctx:event("jump", o)
    end
end

-- ---- physics ---------------------------------------------------------------------------

local function apply_controllable_velocity(o, li)
    if P.isset(o, "cx") then
        local cx = P.get(o, "cx") / 10 * (o.hvel_mod or 1)
        if li == "4" then o.cvx = o.cvx - cx
        elseif li == "6" then o.cvx = o.cvx + cx
        elseif li == "3" or li == "9" then o.cvx = o.cvx + cx * 0.7
        elseif li == "1" or li == "7" then o.cvx = o.cvx - cx * 0.7 end
    else
        o.cvx, o.cvy = 0, 0
    end
end

local function friction(o)
    if o.vx > 0 then o.vx = (o.vx <= 1) and 0 or o.vx - 1
    elseif o.vx < 0 then o.vx = (o.vx >= -1) and 0 or o.vx + 1 end
end

function H.move(o)
    local h, ctx, e = o.h, o.ctx, o.enemy
    if h.is_grabbed or h.in_stasis_ticks > 0 then return end
    local li = last_input(o)
    apply_controllable_velocity(o, li)
    o.x = o.x + o.vx + o.cvx
    o.y = o.y + o.vy + o.cvy

    h.is_wallhugging = o.x <= LEFT_WALL or o.x >= RIGHT_WALL
    if h.is_wallhugging and P.isset(o, "cw") and P.isset(o, "d") then o.disable_d = true end

    if o.y >= FLOOR and not P.isset(o, "ax") then
        o.y = FLOOR
        if o.vy > 0 or is_idle_grounded(o) then h.rehits = {} end
        if P.isset(o, "cl") then
            local m = move_of(o, cur_id(o))
            o.vx, o.vy = 0, 0
            H.set_ani(o, m.play_if_hit, false)
            o.stride = 1
        elseif (h.state == S.SCRAP or h.state == S.DESTRUCTION) and o.vy > 0 then
            o.vx, o.vy = 0, 0
            H.finished(o)
            ctx:landing(o, true)
        elseif h.state == S.VICTORY and o.vy > 0 then
            o.vx, o.vy = 0, 0
            H.set_ani(o, A.IDLE, true)
            o.stride = h.stride
            ctx:landing(o, true)
        elseif h.state == S.JUMPING and not e.h.is_grabbed and not P.isset(o, "cg") then
            o.vx, o.vy = 0, 0
            if li == "6" then
                h.state = S.WALKTO
                H.set_ani(o, A.WALKING, true)
            elseif li == "4" then
                h.state = S.WALKFROM
                H.set_ani(o, A.WALKING, true)
            else
                h.state = S.STANDING
                H.set_ani(o, A.IDLE, true)
            end
            o.stride = h.stride
            h.jump_delay = 3
            ctx:landing(o, true)
        elseif h.state == S.RECOIL then
            if o.vy > 6 then
                -- bounce off the floor
                ctx:landing(o, false)
                o.vy = -3
                o.vx = o.vx / 2
                if h.id ~= 10 then
                    P.set_custom_string(o, "l20s4sp13zzN3-zzM100")
                    ctx:shake(5)
                else
                    P.set_custom_string(o, "l40s4sp13zzN3-zzM100")
                    ctx:shake(15)
                end
            end
            if o.vy >= 0 and o.tick > 5 and o.sprite == 12 and not h.is_grabbed then o.vy = 1 end
            if o.vy > 0 then
                o.vy, o.vx = 0, 0
                H.finished(o)
            end
        end
        if h.state ~= S.SCRAP then friction(o) end
        if h.state == S.WALKTO then
            H.face_enemy(o, e)
            o.x = o.x + h.fwd_speed * o.dir
        elseif h.state == S.WALKFROM then
            H.face_enemy(o, e)
            o.x = o.x - h.back_speed * o.dir
        end
    else
        if ctx:hars_alive() then o.vy = o.vy + o.gravity else o.vy = o.vy + 230 / 256 end
        if o.vy > 13 then o.vy = 13 end
    end
end

-- ---- stun -------------------------------------------------------------------------------

local function hpfactor(ratio, hmax, hp) return (hmax * ratio + hp) / hmax end

local function handle_stun(o)
    local h = o.h
    local id = cur_id(o)
    if h.health <= 0 then
        h.endurance = h.endurance_max - 2
    elseif h.endurance < h.endurance_max then
        if h.endurance < 1 then
            if id == A.STUNNED then h.endurance = h.endurance + h.stun_factor * 7 // 5 end
        else
            local sf = h.stun_factor * (h.endurance / h.endurance_max)
            local ratio, const
            if id == A.IDLE or id == A.CROUCHING or id == A.VICTORY then ratio, const = 0x8e / 256, STUN_RECOVERY
            elseif id == A.CROUCHING_BLOCK or id == A.STANDING_BLOCK then ratio, const = 0xed / 256, STUN_RECOVERY_BLOCKING
            elseif id == A.JUMPING then ratio, const = 0x4f / 256, STUN_RECOVERY
            elseif id < (A.SCREW | A.JUMPING) then ratio, const = 0x2f / 256, STUN_RECOVERY end
            if ratio then
                h.endurance = h.endurance - (math.floor(hpfactor(ratio, h.health_max, h.health) * sf) + const)
            end
            if h.endurance < 0 then h.endurance = 0 end
        end
    end
    if h.state == S.STUNNED then
        h.stun_timer = h.stun_timer + 1
        if h.stun_timer % 10 == 0 then o.ctx:spawn_oil(o, o.x, o.y - 60, 5) end
        if h.endurance >= 0 then
            h.endurance = 0
            h.state = S.STANDING
            H.set_ani(o, A.IDLE, true)
        end
    end
end

local function apply_stun_damage(o, amount)
    local h = o.h
    if h.endurance < 0 then
        if h.state == S.STUNNED then h.endurance = 0 end
    else
        if h.state == S.RECOIL and is_airborne(o) then amount = amount // 2 end
        h.endurance = h.endurance + (amount * 2 + 12) * 256
    end
end

--- har_tick: runs before the frame is applied.
function H.tick(o)
    local h, ctx = o.h, o.ctx
    if h.punch_valid > 0 then h.punch_valid = h.punch_valid - 1 end
    if h.kick_valid > 0 then h.kick_valid = h.kick_valid - 1 end
    if h.in_stasis_ticks == 0 and h.throw_duration == 0 then handle_stun(o) end
    if h.in_stasis_ticks > 0 then
        h.in_stasis_ticks = h.in_stasis_ticks - 1
        o.halt = h.in_stasis_ticks > 0
    end
    h.is_grabbed = h.throw_duration > 0
    if h.throw_duration > 0 then
        h.throw_duration = h.throw_duration - 1
        if h.throw_duration == 0 then
            -- a throw's damage lands when it ends
            h.health = h.health - h.last_damage_value
            h.rehit_combo = true
            if h.endurance < 0 then h.endurance = 0 else apply_stun_damage(o, h.last_stun_value) end
            if h.health <= 0 then
                h.health = 0
                ctx:event("defeat", o)
            end
        end
    end
    if P.isset(o, "aa") then h.air_attacked = false end

    -- keep inside the walls
    if not P.isset(o, "ab") then
        local left, right = LEFT_WALL, RIGHT_WALL
        if o.y ~= FLOOR then right = RIGHT_WALL - 1 end
        local wall
        if o.x < left then wall = "left"; o.x = left
        elseif o.x > right then wall = "right"; o.x = right end
        wall = wall or o.wall_hit
        if wall then
            local m = move_of(o, cur_id(o))
            if P.isset(o, "aw") and m and m.play_if_hit ~= 0 then
                H.set_ani(o, m.play_if_hit, false)
                h.executing_move = true
            end
            o.wall_hit = nil
        end
    end
    if h.state == S.WALLDAMAGE and not is_airborne(o) then h.state = S.RECOIL end
    if not is_airborne(o) and h.air_attacked then h.air_attacked = false end
    for id, n in pairs(h.disabled) do
        if n <= 1 then h.disabled[id] = nil else h.disabled[id] = n - 1 end
    end
end

-- ---- end of an animation (har_finished) ---------------------------------------------------

function H.finished(o)
    local h, ctx = o.h, o.ctx
    h.executing_move = false
    if h.block_duration > 0 and (h.state == S.BLOCKSTUN or h.state == S.CROUCHBLOCK) then
        P.set_custom_string(o, "A1")
        o.finished = false
        P.tick(o)
        h.block_duration = h.block_duration - 1
    elseif h.state == S.SCRAP or h.state == S.DESTRUCTION then
        h.state = S.DONE
        H.set_ani(o, A.VICTORY, false)
    elseif h.state == S.VICTORY or h.state == S.DONE then
        -- hold the last sprite
        o.phase = "run"
        o.finished = false
        o.tick = math.max(0, o.sc.total - 1)
        if cur_id(o) ~= A.VICTORY then H.set_ani(o, A.IDLE, true) end
        return
    elseif h.state == S.RECOIL and h.health <= 0 then
        h.state = S.DEFEAT
        H.set_ani(o, A.DEFEAT, false)
    elseif h.state == S.RECOIL and P.last_frame_letter(o) == "M" then
        h.state = S.STANDING_UP
        P.set_custom_string(o, "zzO7-bj2zzO2")
        o.finished = false
        P.tick(o)
    elseif (h.state == S.RECOIL or h.state == S.STANDING_UP)
        and (h.endurance >= h.endurance_max or h.endurance < 0) then
        if h.endurance >= h.endurance_max then
            -- dizzy for longer the further over the limit
            h.endurance = (((h.endurance_max - h.endurance) // 256) * 5 // 2 - 60) * 256
        end
        h.state = S.STUNNED
        H.set_ani(o, A.STUNNED, true)
    elseif h.state ~= S.CROUCHING and h.state ~= S.CROUCHBLOCK then
        if is_airborne(o) and h.state == S.RECOIL then
            if h.health <= 0 or h.endurance <= 0 then
                -- hold the last frame until they land
                o.phase = "run"
                o.finished = false
                o.tick = math.max(0, o.sc.total - 1)
            else
                h.state = S.JUMPING
                H.set_ani(o, A.JUMPING, false)
            end
        elseif h.state == S.RECOIL then
            h.state = S.STANDING
            H.set_ani(o, A.IDLE, true)
            H.act(o, "5", false, false)
        elseif is_airborne(o) then
            h.state = S.JUMPING
            H.set_ani(o, A.JUMPING, false)
        elseif h.health <= 0 then
            h.state = S.DEFEAT
            H.set_ani(o, A.DEFEAT, false)
        else
            h.air_attacked = false
            h.state = S.NONE
            H.set_ani(o, A.IDLE, true)
            H.act(o, "5", false, false)
        end
    else
        h.state = S.NONE
        H.set_ani(o, A.CROUCHING, true)
        H.act(o, "5", false, false)
    end
    if h.state == S.NONE then h.state = S.STANDING end
end

-- ---- damage ---------------------------------------------------------------------------------

local function calc_damage(attacker, move)
    local multiplier = 100
    if attacker.is_har and P.isset(attacker, "k") then multiplier = P.get(attacker, "k") + 10 end
    local dmg = move.damage * multiplier // 100
    if multiplier < 100 then dmg = dmg + 1 end
    local power = attacker.h and attacker.h.pilot.power or 10
    local stun = dmg
    dmg = dmg * (20 + power) // 30 + 1
    return dmg, stun
end

function H.take_damage(o, move, attacker)
    local h, ctx = o.h, o.ctx
    if h.state == S.VICTORY or h.state == S.DONE then return end
    h.in_stasis_ticks = 1
    local dmg, stun = calc_damage(attacker, move)
    if h.rehit_combo then dmg = 10 * dmg // 6 end
    h.last_damage_value = dmg
    h.last_stun_value = stun
    h.executing_move = false

    if h.throw_duration == 0 then
        h.health = h.health - dmg
        apply_stun_damage(o, stun)
    end
    if h.health <= 0 then
        h.health = 0
        ctx:slowdown()
    end

    local s = move.footer or ""
    if #s == 0 then return end
    h.state = S.RECOIL
    P.set_animation(o, move_of(o, A.DAMAGE))
    o.repeat_ = false
    o.finished = false
    if h.health <= 0 then ctx:event("defeat", o) end

    local custom
    if h.throw_duration > 0 then
        o.stride = 1
    elseif attacker.is_har and P.isset(attacker, "ai") and move.category ~= CAT.PROJECTILE then
        custom = "A1-s01l50B2-C2-L5-M400"      -- launched off the ground
        o.vx = -5 * o.dir
        o.vy = -9
        o.stride = 1
    elseif is_airborne(o) then
        if h.endurance >= h.endurance_max or h.health <= 0 then
            custom = s .. "-L3-M5000"
        else
            custom = s .. "-L2-M5-L2"
        end
        o.vy = (o.vvel_mod or 1) * -(((30 - move.damage) * 0.133333) + 6.5)
        o.vx = ((move.damage * 0.16666666) + 2) * -o.dir * (o.hvel_mod or 1)
        o.stride = 1
    elseif h.health <= 0 or h.endurance >= h.endurance_max or h.endurance < 0 then
        -- knocked down (string from MASTER.DAT, via OpenOMF)
        local last = s:match(".*()%-")
        local head = last and s:sub(1, last - 1) or ""
        custom = head .. "-x-20ox-20L1-ox-20L2-x-20zzs4l25sp13M1-zzM2"
    end
    P.set_custom_string(o, custom or s)
    if not is_airborne(o) then
        local ticks = P.len_ticks(o)
        if ticks < 20 then
            local push = (ticks - 3) * 20 / 29 + 0.5
            if push < 7 then push = 7 end
            o.vx = push * -o.dir
        end
    end
    local f1 = o.sc.frames[1]
    if f1 and f1.tags.k ~= nil then
        o.vx = -5 * o.dir
        o.vy = -8
    end
end

function H.block(o, hx, hy, block_stun)
    local h = o.h
    if h.last_input == "1" or h.last_input == "3" then
        P.set_animation(o, move_of(o, A.CROUCHING_BLOCK))
    else
        P.set_animation(o, move_of(o, A.STANDING_BLOCK))
    end
    P.set_custom_string(o, "A1")
    o.repeat_ = false
    o.finished = false
    P.tick(o)
    h.block_duration = block_stun
    h.state = S.BLOCKSTUN
    o.ctx:spawn_effect(o, A.BLOCKING_SCRAPE, hx, hy)
    audio.sound(3, { volume = 89, pan = 50 })
    h.damage_received = true
end

-- ---- hit detection (OpenOMF game/protos/intersect.c) ----------------------------------

local function sprite_of(o)
    if o.sprite < 0 then return nil end
    return o.anim.sprites[o.sprite + 1]
end

--- Does one of `a`'s collision points for its current sprite land on a
--- solid pixel of `b`'s sprite? Returns the hit position or nil.
function H.intersect(a, b, is_har)
    local sa, sb = sprite_of(a), sprite_of(b)
    if not sa or not sb then return nil end
    local coords = a.anim.coords
    if not coords or #coords == 0 then return nil end
    local ax, ay = a.x + sa.x, a.y + sa.y
    local bx, by = b.x + sb.x, b.y + sb.y
    local adir = ((a.dir < 0) ~= P.isset(a, "r")) and -1 or 1
    local bdir = ((b.dir < 0) ~= P.isset(b, "r")) and -1 or 1
    if adir < 0 then ax = a.x - sa.x - sa.w end
    if bdir < 0 then bx = b.x - sb.x - sb.w end
    for _, cc in ipairs(coords) do
        if cc.frame == a.sprite then
            local t
            if adir > 0 then t = ax + cc.x - sa.x else t = ax + (sa.w - cc.x) + sa.x end
            local xc = math.floor(t - bx)
            local yc = math.floor((ay + sa.h + cc.y) - by - (sa.y + sa.h))
            if xc >= 0 and xc < sb.w and yc >= 0 and yc < sb.h then
                local px = bdir < 0 and (sb.w - xc) or xc
                if px < sb.w then
                    local v = sb.img:pixel(px, yc)
                    if v ~= 0 and (v < 96 or not is_har) then
                        return xc + bx, yc + by
                    end
                end
            end
        end
    end
    return nil
end

local function spawn_scrap(o, x, y, amount)
    o.ctx:spawn_oil(o, x, y, amount // 3)
    local n = 0
    if amount > 11 and amount < 14 then n = 1 elseif amount > 13 and amount < 16 then n = 2
    elseif amount > 15 then n = 3 end
    for _ = 1, n do o.ctx:spawn_scrap(o, x, y) end
end

-- har_collide_with_har: does `a` hit `b`? Returns true for priority (throw).
local function collide_with_har(a, b, loop)
    local ha, hb, ctx = a.h, b.h, a.ctx
    local move = move_of(a, cur_id(a))
    if not move or ha.in_stasis_ticks > 0 or a.hit_pixels_disabled then return false end
    local air_hit = is_airborne(b) or P.isset(a, "ai")
    if not P.isset(b, "uh") then
        if hb.state == S.WALLDAMAGE or hb.state >= S.VICTORY or hb.state == S.STANDING_UP then return false end
        if hb.rehit_combo and hb.in_stasis_ticks == 0 then
            if hb.endurance >= hb.endurance_max then return false end
            if hb.rehits[move.id] then return false end
        end
        if H.is_invincible(b, move) then return false end
    end
    if not in_range(a, b, move) then return false end
    if a.can_hit then
        ha.damage_done = false
        a.can_hit = false
    elseif (cur_id(b) == A.STANDING_BLOCK or cur_id(b) == A.CROUCHING_BLOCK) and P.isset(a, "ur") then
        hb.block_duration = move.block_stun
    end
    if ha.damage_done then return false end
    local hx, hy = H.intersect(a, b, true)
    if not (hx or move.category == CAT.CLOSE or (P.isset(a, "ue") and not is_airborne(b))) then return false end
    hx, hy = hx or b.x, hy or (b.y - 40)

    a.q_counter = a.q_val
    a.should_hitpause = true
    if H.is_blocking(b, move) and not P.isset(a, "bn") then
        ha.damage_done = true
        H.block(b, hx, hy, move.block_stun)
        if P.isset(a, "i") and move.play_if_hit ~= 0 then H.set_ani(a, move.play_if_hit, false) end
        local bv = math.max(move.block_stun, 2)
        b.vx = -b.dir * (bv * (20 / 27) + 1)
        ctx:event("block", b, move)
        return false
    end
    if move.category ~= CAT.CLOSE and not hb.damage_done and loop == 0 and H.intersect(b, a, true) then
        -- both hit at once
        if collide_with_har(b, a, 1) then return false end
        if hb.state == S.RECOIL or hb.state == S.STANDING_UP or hb.state == S.WALLDAMAGE or hb.health <= 0
            or hb.state >= S.VICTORY then
            return false
        end
    end
    if (hb.state == S.STUNNED or hb.state == S.RECOIL) and a.dir == b.dir then b.dir = -a.dir end
    if is_airborne(a) and is_airborne(b) then a.vx = a.vx * 0.7 end
    hb.throw_duration = move.throw_duration
    b.dir = -a.dir
    H.take_damage(b, move, a)
    ctx:event("hit", b, move)
    if hb.rehit_combo then b.vy = b.vy - 3 end
    if move.damage ~= 0 then spawn_scrap(b, hx, hy, move.block_stun) end
    if air_hit then hb.rehits[move.id] = true end
    hb.rehit_combo = air_hit
    if move.play_if_hit ~= 0 then
        H.set_ani(a, move.play_if_hit, false)
        ha.executing_move = true
        local prio = move.category == CAT.CLOSE
        if loop == 0 then prio = collide_with_har(a, b, 1) or prio end
        return prio
    end
    ha.damage_done = true
    hb.damage_received = true
    return move.category == CAT.CLOSE
end

local function is_throwing(o)
    local m = move_of(o, cur_id(o))
    return m and m.category == CAT.CLOSE and o.enemy.h.throw_duration > 0
end

function H.collide(a, b)
    if is_throwing(a) or is_throwing(b) then return end
    if not collide_with_har(a, b, 0) then collide_with_har(b, a, 0) end
end

--- A projectile (or anything spawned from a move) against a HAR.
function H.collide_projectile(o, p)
    local h, ctx = o.h, o.ctx
    if p.hit_pixels_disabled or p.has_hit then return end
    if h.state == S.STANDING_UP or h.state == S.WALLDAMAGE or h.state >= S.VICTORY then return end
    local air_hit = is_airborne(o)
    local move = p.owner.h.af.moves[p.anim.id]
    if not move then return end
    if h.rehit_combo and h.rehits[move.id] then return end
    if p.can_hit then p.has_hit = false; p.can_hit = false end
    local hx, hy = H.intersect(p, o, true)
    if not hx then return end
    p.q_counter = p.q_val
    if H.is_blocking(o, move) and not P.isset(p, "bn") then
        p.has_hit = true
        p.finished = true
        if move.successor ~= 0 and move.category ~= CAT.CLOSE then ctx:projectile_next(p, move.successor) end
        h.damage_received = false
        H.block(o, hx, hy, move.block_stun)
        local bv = math.max(move.block_stun, 2)
        o.vx = -o.dir * (bv * (20 / 27) + 1)
        return
    end
    if H.is_invincible(o, move) then return end
    if move.play_if_hit ~= 0 then
        ctx:projectile_next(p, move.play_if_hit)
        return
    end
    if P.isset(p, "af") then
        h.in_stasis_ticks = move.damage     -- Chronos' time freeze
    elseif move.damage > 0 then
        o.dir = -p.dir
        H.take_damage(o, move, p.owner)
        if air_hit then o.vy = o.vy - 3 end
    elseif move.category == CAT.CLOSE then
        h.throw_duration = move.throw_duration
    end
    p.has_hit = true
    ctx:event("hit", o, move)
    spawn_scrap(o, hx, hy, move.block_stun)
    h.damage_received = true
    h.rehit_combo = air_hit
    h.rehits[move.id] = true
    if move.successor ~= 0 and move.category ~= CAT.CLOSE then ctx:projectile_next(p, move.successor) end
end

return H
