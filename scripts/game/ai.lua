-- A computer opponent. Simpler than the original's (or OpenOMF's ~2,800
-- line one): it walks in, picks moves from its HAR's own move list and
-- enters them as a player would (the motion, then punch or kick), blocks
-- some of the attacks it sees coming, and jumps now and then. It plays
-- through the same input path as a human, so every move it does is a real
-- AF move with its real script.

local H = require("game.har")

local AI = {}
AI.__index = AI

local S, CAT = H.STATE, H.CAT

--- difficulty 1..5
function AI.new(arena, player, difficulty)
    return setmetatable({ arena = arena, player = player, difficulty = difficulty or 3,
                          queue = {}, cooldown = 30, block = 0 }, AI)
end

function AI:poll() end

-- Moves the AI can start from standing or crouching, by category.
local function usable_moves(o)
    if o.h._ai_moves then return o.h._ai_moves end
    local list = {}
    for id, m in pairs(o.h.af.moves) do
        local ms = m.move_string
        local c = m.category
        if id > H.ANIM.SCREW and #ms > 0 and ms:match("^[PK][1-9]*$")
            and (m.pos_constraint & 0x3) == 0
            and (c == CAT.LOW or c == CAT.MEDIUM or c == CAT.HIGH or c == CAT.CLOSE) then
            list[#list + 1] = m
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    o.h._ai_moves = list
    return list
end

-- The inputs for a move string, in screen terms for a HAR facing `dir`.
-- "P6321" = 1, 2, 3, 6 then punch (the string lists the newest first).
local function inputs_for(ms, dir)
    local button = ms:sub(1, 1)
    local motion = ms:sub(2):reverse()
    local steps = {}
    local function screen(c) return dir < 0 and (H.flip_input(c, -1)) or c end
    for i = 1, #motion do steps[#steps + 1] = { screen(motion:sub(i, i)) } end
    local last = #motion > 0 and screen(motion:sub(-1)) or "5"
    if #motion == 0 then steps[#steps + 1] = { "5" } end
    steps[#steps + 1] = { last, button == "P", button == "K" }
    steps[#steps + 1] = { last }
    return steps
end

AI.inputs_for = inputs_for

function AI:random(n) return self.arena:random(n) end

function AI:take()
    local me = self.arena.hars[self.player + 1]
    local foe = me.enemy
    if not me or not foe then return "5", false, false end
    if #self.queue > 0 then
        local s = table.remove(self.queue, 1)
        return s[1], s[2] or false, s[3] or false
    end
    local fwd = foe.x > me.x and "6" or "4"
    local back = fwd == "6" and "4" or "6"
    local dist = math.abs(foe.x - me.x)
    local d = self.difficulty

    -- block what's coming
    if self.block > 0 then
        self.block = self.block - 1
        local m = foe.h.af.moves[foe.anim.id]
        if m and m.category == CAT.LOW then return (back == "4" and "1" or "3"), false, false end
        return back, false, false
    end
    if foe.h.executing_move and dist < 110 and me.h.state ~= S.JUMPING and self:random(10) < d + 1 then
        self.block = 6 + self:random(8)
        return back, false, false
    end

    if self.cooldown > 0 then self.cooldown = self.cooldown - 1 end
    if me.h.executing_move or me.h.state == S.RECOIL or me.h.state == S.STUNNED then return "5", false, false end

    if dist > 75 then
        if self:random(100) < 2 then
            self.queue = { { fwd == "6" and "9" or "7" }, { "5" } }
            return "5", false, false
        end
        return fwd, false, false
    end
    if self.cooldown == 0 then
        local moves = usable_moves(me)
        if #moves > 0 then
            local m = moves[self:random(#moves) + 1]
            self.queue = inputs_for(m.move_string, me.dir)
            self.cooldown = 4 + self:random(30 - d * 4)
            local s = table.remove(self.queue, 1)
            return s[1], s[2] or false, s[3] or false
        end
    end
    if dist < 35 and self:random(4) == 0 then return back, false, false end
    return "5", false, false
end

return AI
