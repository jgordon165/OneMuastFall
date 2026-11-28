-- A fight: two HARs in one of the five arenas (ARENA0..4.BK).
--
-- Follows OpenOMF's game/scenes/arena.c and game_state.c:
--   * a round starts dark, fades in (30 ticks), shows READY (or ROUND n),
--     FIGHT, and lets the HARs go at tick 90
--   * every tick: the scene's own work (pushing the HARs apart, the bars,
--     the round state), input, then all objects advance, move, collide and
--     apply their frames
--   * a defeat ends the round: the loser falls, the winner poses, YOU WIN /
--     YOU LOSE, a fade out, then the next round or the end of the match
--
-- The arena's tick is slower than a scene's: 8 + 60 − rate / 15 × 60 ms,
-- where rate is the speed setting (0..10, default 5) + 5, as in OpenOMF's
-- game_state: 28 ms at the default speed. A KO slows the next 12 ticks to
-- rate − 10 (68 ms).
--
-- args: { players = { {har=0..10, pilot=<pilots entry>, ai=difficulty|nil}, {...} },
--         arena = 0..4, rounds = 1|3|5, speed = 0..10, on_done = function(winner) }

local P       = require("core.player")
local Stage   = require("core.stage")
local H       = require("game.har")
local AI      = require("game.ai")
local control = require("game.control")
local pilots  = require("game.pilots")
local scenes  = require("core.scenes")
local res     = require("game.res")
local Score   = require("game.score")

local M = {}

local CROSSFADE = 30
local START_POS = { 110, 210 }
local START_DIR = { 1, -1 }
local LAYER_BOTTOM, LAYER_MIDDLE, LAYER_TOP = 0, 1, 2

-- ---- setup -------------------------------------------------------------------------

function M:enter(args)
    -- the scene table is reused fight after fight: clear the last match's end
    self.done, self.fight_at = false, nil
    self.args = args
    self.arena_id = args.arena or 0
    local bk = res.bk("ARENA" .. self.arena_id .. ".BK")
    -- the round announcements change the sound table, so use a copy
    self.bk = setmetatable({ sound_table = {} }, { __index = bk })
    for k, v in pairs(bk.sound_table) do self.bk.sound_table[k] = v end
    self.speed = args.speed or 5
    self.rate = self.speed + 5
    self.ms_per_tick = M.tick_ms(self.rate)
    self.rounds = args.rounds or 1
    self.round = 0
    self.wins = { 0, 0 }
    self.tick, self.acc = 0, 0
    self.rng = 12345
    self.objects, self.pending = {}, {}
    self.hit_pause, self.slow_ticks = 0, 0
    self.altpal = omf.altpals()
    self.altpal = self.altpal and self.altpal[0]

    self.hars, self.ctrl = {}, {}
    for i = 1, 2 do
        local pl = args.players[i]
        local af = assert(omf.af("FIGHTR" .. pl.har .. ".AF"))
        local o = H.new(self, af, i - 1, pl.pilot, START_POS[i], START_DIR[i])
        self.hars[i] = o
        if pl.controller then self.ctrl[i] = pl.controller
        elseif pl.ai then self.ctrl[i] = AI.new(self, i - 1, pl.ai)
        else self.ctrl[i] = control.keyboard(i) end
    end
    self.hars[1].enemy, self.hars[2].enemy = self.hars[2], self.hars[1]

    -- scores: carried in from earlier fights (players[i].score), points x the
    -- multiplier of the computer's level, or 100 between two players
    local p1, p2 = args.players[1], args.players[2]
    local level = (p1.ai == nil) ~= (p2.ai == nil) and (p1.ai or p2.ai) or nil
    local mult = Score.multiplier(level)
    self.scores = {
        Score.new(1, p1.ai == nil and not p1.controller, mult, p1.score),
        Score.new(2, p2.ai == nil and not p2.controller, mult, p2.score),
    }
    self.vs_computer = level ~= nil

    audio.music("ARENA" .. self.arena_id .. ".PSM", true)
    self:reset_round()
end

function M:leave()
    audio.stop_all()
    self.hars, self.objects = {}, {}
end

function M:load_palette()
    local pal = self.bk.palettes[0]
    gfx.set_base(pal)
    -- the desert changes its light round by round
    if self.bk.file_id == 128 and self.bk.palettes[self.round] then
        gfx.set_base(self.bk.palettes[self.round]:sub(0x60 * 3 + 1, 0xA0 * 3), 0x60)
    end
    for i = 1, 2 do pilots.load_colors(self.altpal, i - 1, self.args.players[i].pilot) end
    Stage.menu_colors()
    gfx.base_color(0, 0, 0, 0)
    gfx.reset_palette()
end

function M:reset_round()
    self.state, self.state_ticks = "starting", 0
    self.over, self.winner, self.win_state = false, nil, nil
    self.finisher_called, self.stunned = false, { false, false }
    for i = 1, 2 do
        local sc = self.scores[i]
        sc.cons_hits, sc.cons_points, sc.combo_hits, sc.combo_points = 0, 0, 0, 0
    end
    -- clear projectiles, scrap and announcements
    self.objects, self.pending = {}, {}
    for i = 1, 2 do H.reset(self.hars[i], START_POS[i], START_DIR[i]) end
    local stl = self.bk.sound_table
    stl[14] = 10              -- READY
    stl[15] = 16              -- ROUND
    stl[3] = 23 + self.round  -- the round number
    self:load_palette()
    -- arena 3's torches burn all the time
    if self.bk.file_id == 64 then
        for id = 1, 4 do
            local a = self.bk.anims[id]
            if a then self:add_bk(a, a.start_x, a.start_y, LAYER_BOTTOM).repeat_ = true end
        end
    end
end

function M.tick_ms(rate)
    return 8 + 60 - (math.max(rate, 0) / 15) * 60
end

-- ---- objects ------------------------------------------------------------------------

function M:random(n)
    self.rng = (self.rng * 1103515245 + 12345) & 0x7FFFFFFF
    if n <= 0 then return 0 end
    return (self.rng >> 8) % n
end

function M:add(o)
    self.pending[#self.pending + 1] = o
    return o
end

function M:add_bk(anim, x, y, layer, spawned)
    local o = P.new(anim, x, y, self, { layer = layer or LAYER_BOTTOM, stl = self.bk.sound_table })
    o.sx, o.sy = x, y
    if spawned then P.init_spawned(o) end
    return self:add(o)
end

-- An object from a HAR's move list (projectiles, effects), in its colours.
function M:add_from_har(har, id, x, y, layer)
    local m = har.h.af.moves[id]
    if not m then return nil end
    local o = P.new(m, x, y, self, { dir = har.dir, layer = layer or LAYER_MIDDLE, stl = har.stl,
                                     pal_offset = har.pal_offset, pal_limit = har.pal_limit })
    o.sx, o.sy = x, y
    o.owner = har
    o.enemy = har.enemy
    P.init_spawned(o)
    return self:add(o)
end

local function owner_har(o)
    if o.is_har then return o end
    return o.owner
end

-- the m tag (ctx of core/player.lua)
function M:spawn(parent, id, x, y, vx, vy, mp, mg)
    local har = owner_har(parent)
    if not har then
        local a = self.bk.anims[id]
        if a then self:add_bk(a, x + a.start_x, y + a.start_y, LAYER_BOTTOM, true) end
        return
    end
    if x == 0 then x = parent.x end
    if y == 0 then y = parent.y end
    if id == H.ANIM.SCRAP_METAL or id == H.ANIM.BOLT or id == H.ANIM.SCREW or id == H.ANIM.BURNING_OIL then
        for _ = 1, 3 do self:spawn_scrap(har, x, y) end
        return
    end
    local o = self:add_from_har(har, id, x, y, LAYER_MIDDLE)
    if not o then return end
    o.vx, o.vy = vx, vy
    o.gravity = mg / 100
    o.dir = parent.dir
    o.is_projectile = true
end

function M:destroy(parent, id)
    local har = owner_har(parent)
    for _, list in ipairs({ self.objects, self.pending }) do
        for _, o in ipairs(list) do
            if o.anim.id == id and owner_har(o) == har then o.finished = true end
        end
    end
end

function M:music(n)
    if n == 0 then audio.stop_music(); return end
    local song = Stage.SONGS[n]
    if song then audio.music(song, true) end
end

function M:sound(o, fr)
    local stl = o.stl or self.bk.sound_table
    local id = (stl[fr.tags.s] or 0) - 1
    if id < 0 then return end
    audio.sound(id, Stage.sound_opts(o, fr.tags))
end

-- burning oil sparks
function M:spawn_oil(har, x, y, amount)
    for _ = 1, amount do
        local o = self:add_from_har(har, H.ANIM.BURNING_OIL, x, y, LAYER_TOP)
        if not o then return end
        o.vx = (self:random(100) - 50) / 20
        o.vy = -(self:random(60) + 20) / 10
        o.gravity = 0.4
        o.is_debris = true
    end
end

function M:spawn_scrap(har, x, y)
    local id = H.ANIM.SCRAP_METAL + self:random(3)
    local o = self:add_from_har(har, id, x, y, LAYER_TOP)
    if not o then return end
    o.vx = (self:random(100) - 50) / 8
    o.vy = -(self:random(60) + 40) / 10
    o.gravity = 1
    o.is_scrap = true
    o.repeat_ = true
    o.life = 220
end

function M:spawn_effect(har, id, x, y)
    local o = self:add_from_har(har, id, x, y, LAYER_MIDDLE)
    if o then o.gravity = 0 end
end

-- dust when a HAR lands (BK animation 26) and the thud
function M:landing(o, sound)
    local a = self.bk.anims[26]
    if a then
        for i = 0, self:random(2) do
            self:add_bk(a, o.x + self:random(20) - 10 + i * 10, o.y, LAYER_MIDDLE, true)
        end
    end
    if sound then
        audio.sound(56, { volume = 38, pan = math.max(-100, math.min(100, math.floor((o.x - 160) * 100 / 160))) })
    end
end

function M:projectile_next(p, id)
    local m = p.owner.h.af.moves[id]
    if not m then return end
    P.set_animation(p, m)
    p.repeat_ = false
    p.finished = false
    p.vx, p.vy = 0, 0
    p.has_hit = false
end

function M:shake(n) self.shake_v = n end
function M:slowdown() self.slow_ticks = 12 end
function M:hars_alive() return self.hars[1].h.health > 0 and self.hars[2].h.health > 0 end
function M:match_over() return self.over end

-- HAR events
local DEBUG = os.getenv("OMF_DEBUG")
function M:event(kind, o, move)
    if DEBUG and kind ~= "jump" then
        sys.log(string.format("t%d %s p%d move %s hp %d/%d end %d/%d", self.tick, kind, o.h.player_id + 1,
            move and move.id or "-", o.h.health, o.h.health_max, o.h.endurance, o.h.endurance_max))
    end
    if kind == "hit" and move then
        -- the announcer: the attacker scores, the one hit loses their run
        local victim = o.h.player_id + 1
        local att = 3 - victim
        self.scores[att]:hit(move.points or 0)
        self.scores[victim]:interrupted(self:callout_pos(victim))
    end
    if kind == "defeat" and self.state ~= "ending" then
        self.state, self.state_ticks = "ending", 0
        self:defeat(o.h.player_id)
    end
end

function M:defeat(loser)
    local winner = 1 - loser
    local w = self.hars[winner + 1]
    local args = self.args
    local one_player = args.players[1].ai == nil and args.players[2].ai ~= nil
    if one_player then self.win_state = (loser == 1) and "win" or "lose"
    elseif args.players[1].ai and args.players[2].ai then self.win_state = "lose"
    else self.win_state = "win" end
    self.wins[winner + 1] = self.wins[winner + 1] + 1
    -- the round's streaks, then the winner's PERFECT ROUND / VITALITY
    for i = 1, 2 do
        self.scores[i]:end_combo(self:callout_pos(i))
        self.scores[i]:interrupted(self:callout_pos(i))
    end
    local ws = self.scores[winner + 1]
    if ws.human and self.vs_computer then
        ws:victory(math.max(0, math.floor(w.h.health * 100 / w.h.health_max)), self:callout_pos(winner + 1))
    end
    if self.wins[winner + 1] >= math.ceil(self.rounds / 2) then
        w.h.state = H.STATE.VICTORY
        self.over, self.winner = true, winner
    else
        w.h.state = H.STATE.DONE
    end
end

-- ---- the tick -------------------------------------------------------------------

local function defeated_at_rest(o)
    return o.anim.id == H.ANIM.DEFEAT and not H.is_airborne(o) and o.vx == 0
end

local function needs_victory_pose(o)
    local st = o.h.state
    return not H.is_airborne(o) and (st == H.STATE.DONE or st == H.STATE.VICTORY) and o.anim.id ~= H.ANIM.VICTORY
end

-- push_players: keep the HARs from standing inside each other
function M:push_players()
    local a, b = self.hars[1], self.hars[2]
    if not (a.y == P.FLOOR or b.y == P.FLOOR) or a.h.health <= 0 or b.h.health <= 0 then return end
    local clearance = (a.y < b.y) and a.h.height or b.h.height
    local guard = 0
    while math.abs(math.floor(a.x) - math.floor(b.x)) < 30 and math.abs(math.floor(a.y) - math.floor(b.y)) < clearance
        and a.h.throw_duration == 0 and b.h.throw_duration == 0 and guard < 40 do
        if a.x < b.x then a.x, b.x = a.x - 1, b.x + 1 else a.x, b.x = a.x + 1, b.x - 1 end
        a.x = math.max(P.LEFT_WALL, math.min(P.RIGHT_WALL, a.x))
        b.x = math.max(P.LEFT_WALL, math.min(P.RIGHT_WALL, b.x))
        guard = guard + 1
    end
end

function M:announce(id, sprite, on_done)
    local a = self.bk.anims[id]
    if not a then return end
    local o = self:add_bk(a, a.start_x, a.start_y, LAYER_TOP)
    o.is_announcement = true
    if sprite then o.sprite_override = sprite end
    if on_done then o.on_finish = on_done end
    return o
end

-- where a side's callouts start: over its HAR's head
function M:callout_pos(i)
    local o = self.hars[i]
    return math.max(40, math.min(280, o.x)), math.max(40, o.y - 75)
end

local STUN = { [H.STATE.RECOIL] = true, [H.STATE.STUNNED] = true, [H.STATE.WALLDAMAGE] = true,
               [H.STATE.STANDING_UP] = true }

function M:score_tick()
    for i = 1, 2 do
        local o = self.hars[i]
        local stunned = STUN[o.h.state] or false
        -- back in control: the other side's combo is over
        if self.stunned[i] and not stunned and o.h.health > 0 then
            self.scores[3 - i]:end_combo(self:callout_pos(3 - i))
        end
        self.stunned[i] = stunned
        -- the finishing move
        if not self.finisher_called and (o.h.state == H.STATE.SCRAP or o.h.state == H.STATE.DESTRUCTION) then
            self.finisher_called = true
            self.scores[i]:finisher(o.h.state == H.STATE.SCRAP and "scrap" or "destruction", self:callout_pos(i))
        end
        self.scores[i]:tick()
    end
end

function M:scene_tick()
    self:score_tick()
    self:push_players()
    self.state_ticks = self.state_ticks + 1
    local h1, h2 = self.hars[1], self.hars[2]
    if self.state == "starting" then
        if self.state_ticks == CROSSFADE then
            local function ready_done() self.fight_at = self.tick + 10 end
            if self.rounds == 1 then
                self:announce(11, nil, ready_done)
            else
                self:announce(6, nil, ready_done)
                self:announce(7, self.round)
            end
        elseif self.state_ticks == 90 then
            self.state, self.state_ticks = "fighting", 0
        end
    elseif self.state == "fighting" then
        -- a KO by a move with no hit reaction doesn't raise the event
        for _, o in ipairs({ h1, h2 }) do
            if o.h.health <= 0 and self.state == "fighting" then self:event("defeat", o) end
        end
    elseif self.state == "ending" then
        if defeated_at_rest(h1) and needs_victory_pose(h2) then
            H.face_enemy(h2, h1); H.set_ani(h2, H.ANIM.VICTORY, false)
        elseif defeated_at_rest(h2) and needs_victory_pose(h1) then
            H.face_enemy(h1, h2); H.set_ani(h1, H.ANIM.VICTORY, false)
        end
        -- win_state: "win" / "lose" until the loser lies still, then the
        -- banner once ("shown"), then "done" when it has played
        if (self.win_state == "win" or self.win_state == "lose") and (defeated_at_rest(h1) or defeated_at_rest(h2)) then
            self:announce(self.win_state == "win" and 9 or 8, nil, function() self.win_state = "done" end)
            self.win_state = "shown"
        elseif self.win_state == "shown" then
            if self.state_ticks > 50 then self.state_ticks = 50 end
        end
        -- let the announcer finish before the fade
        if self.state_ticks > 80 and (self.scores[1]:busy() or self.scores[2]:busy()) then
            self.state_ticks = 80
        end
        if self.state_ticks >= 80 + CROSSFADE then
            if self.over then
                self:finish_match()
                return
            else
                self.round = self.round + 1
                self:reset_round()
            end
        end
    end
    if self.fight_at and self.tick == self.fight_at then
        self:announce(10)
        self.fight_at = nil
    end
end

function M:finish_match()
    self.done = true
    local cb = self.args.on_done
    if cb then cb(self.winner, { self.scores[1].total, self.scores[2].total })
    else scenes.switch(require("scenes.menu")) end
end

local function move_object(o)
    if o.is_scrap or o.is_debris then
        o.x = o.x + o.vx
        o.vy = o.vy + o.gravity
        o.y = o.y + o.vy
        if o.x < P.LEFT_WALL then o.x = P.LEFT_WALL; o.vx = -o.vx * 0.4 end
        if o.x > P.RIGHT_WALL then o.x = P.RIGHT_WALL; o.vx = -o.vx * 0.4 end
        if o.y > P.FLOOR then
            o.y = P.FLOOR
            if o.is_debris then o.finished = true end
            o.vy = -o.vy * 0.4
            o.vx = o.vx * 0.4
        end
        if o.life then
            o.life = o.life - 1
            if o.life <= 0 then o.finished = true end
        end
        return
    end
    if o.is_projectile then
        o.x = o.x + o.vx + o.cvx
        o.vy = o.vy + o.gravity
        o.y = o.y + o.vy + o.cvy
        local moving = math.abs(o.vx) >= 0.1
        if not P.isset(o, "bh") and moving and (o.x < P.LEFT_WALL or o.x > P.RIGHT_WALL) then
            o.x = math.max(P.LEFT_WALL, math.min(P.RIGHT_WALL, o.x))
            o.finished = true
        end
        if o.y > P.FLOOR then
            o.y = P.FLOOR
            o.finished = true
        end
        if o.finished then
            local m = o.owner.h.af.moves[o.anim.id]
            if m and m.successor ~= 0 then
                P.set_animation(o, o.owner.h.af.moves[m.successor] or o.anim)
                o.vx, o.vy, o.finished = 0, 0, false
            end
        end
        return
    end
    -- announcements, dust, effects
    o.x = o.x + o.vx
    o.vy = o.vy + o.gravity
    o.y = o.y + o.vy
end

function M:step()
    if self.hit_pause > 0 then
        self.hit_pause = self.hit_pause - 1
        return
    end
    self.tick = self.tick + 1
    self:scene_tick()
    if self.done then return end

    for i = 1, 2 do
        local dir, punch, kick, between = self.ctrl[i]:take()
        -- stick positions passed through since the last tick go into the
        -- move buffer too, so a fast motion isn't lost between ticks
        if between then
            for _, d in ipairs(between) do H.push_input(self.hars[i], d) end
        end
        H.act(self.hars[i], dir, punch, kick)
    end

    local keep = {}
    for _, o in ipairs(self.objects) do if not o.finished then keep[#keep + 1] = o end end
    self.objects = keep
    for _, o in ipairs(self.pending) do self.objects[#self.objects + 1] = o end
    self.pending = {}

    local h1, h2 = self.hars[1], self.hars[2]
    P.tick_advance(h1); P.tick_advance(h2)
    for _, o in ipairs(self.objects) do P.tick_advance(o) end

    H.move(h1); H.move(h2)
    for _, o in ipairs(self.objects) do move_object(o) end

    H.collide(h1, h2)
    for _, o in ipairs(self.objects) do
        if o.is_projectile and not o.finished and o.owner then H.collide_projectile(o.owner.enemy, o) end
    end

    for _, o in ipairs({ h1, h2 }) do
        H.tick(o)
        P.tick_apply(o)
        if o.entered and P.isset(o, "cp") and o.should_hitpause then
            o.should_hitpause = false
            self.hit_pause = 4
        end
    end
    for _, o in ipairs(self.objects) do P.tick_apply(o) end
end

-- ---- scene interface --------------------------------------------------------------------

function M:update(dt)
    if input.pressed("escape") then
        scenes.switch(require("scenes.menu"))
        return
    end
    for i = 1, 2 do self.ctrl[i]:poll() end
    self.acc = self.acc + dt
    local n = 0
    while not self.done and n < 20 do
        local ms = self.slow_ticks > 0 and M.tick_ms(self.rate - 10) or self.ms_per_tick
        if self.acc < ms then break end
        self.acc = self.acc - ms
        if self.slow_ticks > 0 then self.slow_ticks = self.slow_ticks - 1 end
        self:step()
        n = n + 1
    end
end

-- ---- drawing -------------------------------------------------------------------------------

local function bar(x, y, w, h, pct, left_aligned, flash, endurance)
    local border_tl, border_br = 0xB9, 0xBE
    local bg = (flash and endurance) and 0xBE or 0xF9
    local tl, mid, br = 0xB7, 0xF6, 0xB4
    if endurance then tl, mid, br = 0xE2, 0xF8, 0xE0 end
    gfx.fill(x, y, w, h, bg)
    gfx.line(x, y, x + w - 1, y, border_tl); gfx.line(x, y, x, y + h - 1, border_tl)
    gfx.line(x, y + h - 1, x + w - 1, y + h - 1, border_br); gfx.line(x + w - 1, y, x + w - 1, y + h - 1, border_br)
    local fw = math.floor(w * pct / 100)
    if fw <= 0 then return end
    local fx = left_aligned and x or (x + w - fw)
    gfx.fill(fx, y, fw, h, mid)
    gfx.line(fx, y, fx + fw - 1, y, tl)
    gfx.line(fx, y + h - 1, fx + fw - 1, y + h - 1, br)
    gfx.line(fx, y, fx, y + h - 1, tl)
    if fw > 1 then gfx.line(fx + fw - 1, y, fx + fw - 1, y + h - 1, br) end
end

function M:draw_hud()
    for i = 1, 2 do
        local h = self.hars[i].h
        local hp = h.health / h.health_max * 100
        local en = 0
        if h.endurance >= 0 then
            en = math.max(0, math.min(1, (h.endurance_max - h.endurance) / h.endurance_max)) * 100
        end
        h.shown_hp = math.max(hp, (h.shown_hp or hp) - 0.5)
        local x = i == 1 and 4 or 216
        local flash = en < 50 and (self.tick // 8) % 2 == 1
        bar(x, 4, 100, 8, h.shown_hp, i == 2, false, false)
        bar(x, 13, 100, 4, en, i == 2, flash, true)
        local name = self.args.players[i].pilot.name
        local har = H.NAMES[h.id] or "?"
        if i == 1 then
            gfx.text(name, 4, 18, 0xE7, 1, 0xF8)
            gfx.text(har, 4, 25, 0xE7, 1, 0xF8)
        else
            gfx.text(name, 316 - gfx.text_width(name, 1), 18, 0xE7, 1, 0xF8)
            gfx.text(har, 316 - gfx.text_width(har, 1), 25, 0xE7, 1, 0xF8)
        end
        -- the score, and the announcer's callouts on their way to it
        self.scores[i]:draw(self.scores[i].human)
        -- round tokens (BK animation 27: sprite 1 empty, 0 won)
        local tok = self.bk.anims[27]
        if tok then
            for j = 0, math.ceil(self.rounds / 2) - 1 do
                local tx = (i == 1) and (110 + 9 * j + 3 + j) or (210 - 9 * j - 3 - j)
                local sp = tok.sprites[(j < self.wins[i] and 0 or 1) + 1]
                if sp then gfx.draw(sp.img, tx + sp.x, 9 + sp.y, false, false, false) end
            end
        end
    end
end

function M:draw()
    gfx.reset_palette()
    for _, o in ipairs(self.objects) do P.palette(o) end
    for i = 1, 2 do P.palette(self.hars[i]) end
    -- fade in at the start of a round, out at the end
    local target
    if self.state == "starting" then target = 0 elseif self.state == "ending" then target = 80 + CROSSFADE end
    if target then
        local progress = math.abs(self.state_ticks - target)
        if progress < CROSSFADE then gfx.darken(255 - progress * 255 // CROSSFADE) end
    end
    gfx.draw(self.bk.background, 0, 0, false, false, true)
    local glow = self.bk.remaps[0] and self.bk.remaps[0][3]
    for _, o in ipairs(self.objects) do if o.layer == LAYER_BOTTOM then P.draw(o, glow) end end
    -- the HAR doing something is drawn in front
    local h1, h2 = self.hars[1], self.hars[2]
    local front = (h2.h.executing_move and not h1.h.executing_move) and h2 or h1
    local backh = front == h1 and h2 or h1
    if h1.h.state == H.STATE.DEFEAT then front, backh = h1, h2 elseif h2.h.state == H.STATE.DEFEAT then front, backh = h2, h1 end
    P.draw(backh, glow)
    P.draw(front, glow)
    for _, o in ipairs(self.objects) do if o.layer == LAYER_MIDDLE then P.draw(o, glow) end end
    for _, o in ipairs(self.objects) do if o.layer == LAYER_TOP and not o.is_announcement then P.draw(o, glow) end end
    self:draw_hud()
    for _, o in ipairs(self.objects) do if o.is_announcement then P.draw(o, glow) end end
end

return M
