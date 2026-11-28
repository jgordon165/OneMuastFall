-- Lua unit tests: the animation string parser and the stage's tick logic,
-- with stand-ins for the engine's gfx/audio.

local script = require("core.script")
local fails = 0
local function check(c, msg)
    if not c then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

-- ---- parser ------------------------------------------------------------------

do
    local sc = script.parse("s3l40A10-bpd63bpn255B5-Z100")
    check(#sc.frames == 3, "three frames")
    check(sc.total == 115, "total ticks")
    local f1 = sc.frames[1]
    check(f1.sprite == 0 and f1.ticks == 10, "frame 1 is A10")
    check(f1.tags.s == 3 and f1.tags.l == 40, "s and l tags")
    check(sc.frames[2].tags.bpd == 63 and sc.frames[2].tags.bpn == 255, "three-letter tags")
    check(sc.frames[3].sprite == 25, "Z is sprite 25")
end

do
    -- "x=" is its own tag (not "x" then "="), and negative values parse
    local sc = script.parse("x=-250A10-x=250B20")
    check(sc.frames[1].tags["x="] == -250, "x= negative")
    check(sc.frames[2].tags["x="] == 250, "x= positive")
    check(sc.frames[1].tags.x == nil, "no stray x tag")
end

do
    -- a tag without a number followed by a number falls back to a shorter tag
    local sc = script.parse("mp1m5A1")
    check(sc.frames[1].tags.mp == 1 and sc.frames[1].tags.m == 5, "mp then m")
    local sc2 = script.parse("brA2")
    check(sc2.frames[1].tags.br == true, "flag tag")
end

do
    -- d loops back
    local sc = script.parse("A5-B5-d1C5")
    check(sc.frames[3].tags.d == 1, "d value")
    check(script.frame_at(sc, 0) == 1 and script.frame_at(sc, 7) == 2 and script.frame_at(sc, 14) == 3, "frame_at")
    check(script.frame_at(sc, 15) == nil, "past the end")
end

do
    -- the invalid lone letters some files have are skipped
    local sc = script.parse("cA3")
    check(#sc.frames == 1 and sc.frames[1].sprite == 0, "invalid tag skipped")
end

-- ---- stage --------------------------------------------------------------------

gfx = setmetatable({}, { __index = function() return function() end end })
audio = setmetatable({ played = {} }, { __index = function() return function() end end })
function audio.sound(id) audio.played[#audio.played + 1] = id end

local Stage = require("core.stage")
do
    local bk = {
        palettes = { [0] = string.rep("\0", 768) }, remaps = {}, sound_table = { [0] = 0, [1] = 5 },
        anims = {
            [1] = { id = 1, start_x = 0, start_y = 0, probability = 0, sprites = {},
                    script = "s1A2-m2mx10my20B3" },
            [2] = { id = 2, start_x = 1, start_y = 1, probability = 0, sprites = {}, script = "A4" },
        },
    }
    local st = Stage.new(bk, { startup = function(id) return id == 1 end })
    check(#st.objects == 1, "one startup object")
    st:step()
    check(#audio.played == 1 and audio.played[1] == 4, "s1 plays sound table[1]-1")
    st:step(); st:step()        -- tick 2: frame B, spawns anim 2
    check(#st.objects == 2, "m spawned an object")
    local o = st.objects[2]
    check(o.x == 11 and o.y == 21, "spawn position is mx/my + start")
    for _ = 1, 10 do st:step() end
    check(#st.objects == 0, "finished objects are removed")
end

do
    local bk = { palettes = { [0] = string.rep("\0", 768) }, remaps = {}, sound_table = {},
                 anims = { [3] = { id = 3, start_x = 0, start_y = 0, probability = 0, sprites = {},
                                   script = "x=0A1-A9-x=100A1" } } }
    local st = Stage.new(bk, { startup = function(id) return true end })
    for _ = 1, 6 do st:step() end
    local o = st.objects[1]
    check(o.x > 40 and o.x < 70, "x= slides between frames (x=" .. tostring(o.x) .. ")")
end

-- ---- fighting ------------------------------------------------------------------------

input = { down = function() return false end, pressed = function() return false end }
do
    local AI = require("game.ai")
    -- "P6321": 1, 2, 3, 6 then punch, held on 6
    local s = AI.inputs_for("P6321", 1)
    check(#s == 6, "ai: motion + button + release")
    check(s[1][1] == "1" and s[2][1] == "2" and s[3][1] == "3" and s[4][1] == "6", "ai: motion order")
    check(s[5][1] == "6" and s[5][2] == true and not s[5][3], "ai: punch on the last direction")
    -- facing left, forward is 4
    local l = AI.inputs_for("K6", -1)
    check(l[1][1] == "4" and l[2][3] == true, "ai: mirrored for a HAR facing left")
    local b = AI.inputs_for("K", 1)
    check(b[1][1] == "5" and b[2][3] == true, "ai: plain kick")
end

do
    local H = require("game.har")
    check(H.flip_input("6", -1) == "4" and H.flip_input("3", -1) == "1" and H.flip_input("8", -1) == "8",
          "har: inputs mirror when facing left")
    check(H.flip_input("6", 1) == "6", "har: unchanged facing right")
end

do
    local control = require("game.control")
    local c = control.scripted({ { "6" }, { "6", true }, { "5", false, true } })
    local d, p, k = c:take()
    check(d == "6" and not p and not k, "scripted controller step 1")
    d, p, k = c:take()
    check(p == true, "scripted controller punch")
    d, p, k = c:take()
    check(k == true and d == "5", "scripted controller kick")
end

do
    -- the keyboard keeps the stick positions passed between two ticks
    local control = require("game.control")
    local held = {}
    input = { down = function(k) return held[k] == true end,
              pressed = function(k) return held[k] == "pressed" end }
    local kb = control.keyboard(1)
    held = { down = true }; kb:poll()                    -- 2
    held = { down = true, right = true }; kb:poll()      -- 3
    held = { right = true, ["return"] = "pressed" }; kb:poll()   -- 6 + punch
    local d, p, k, between = kb:take()
    check(d == "6" and p == true and not k, "keyboard: last stick + punch")
    check(#between == 2 and between[1] == "2" and between[2] == "3", "keyboard: 2, 3 kept for the move buffer")
    local d2, p2, _, b2 = kb:take()
    check(d2 == "6" and not p2 and #b2 == 0, "keyboard: latches cleared after a tick")
end

do
    -- OpenOMF's arena tick: 28 ms at the default speed (5 + 5), 68 ms in a KO slow-down
    local arena = require("scenes.arena")
    check(arena.tick_ms(10) == 28, "arena: 28 ms ticks at speed 5")
    check(arena.tick_ms(0) == 68, "arena: 68 ms in the slow-down")
end

do
    -- the scoreboard file: SCORES.DAT entries round-trip, and new scores
    -- find their place
    local scores = require("game.scores")
    local pages = scores.parse(nil)
    check(#pages == 4 and #pages[1] == 20 and pages[1][1].score == 0, "scores: empty board")
    scores.insert(pages, 2, 1, { score = 1250400, name = "JOEL", har = 2, pilot = 9 })
    scores.insert(pages, 2, 2, { score = 40000, name = "ANGEL", har = 5, pilot = 7 })
    local data = scores.serialize(pages)
    check(#data == 4 * 20 * 24, "scores: 1920 bytes")
    local back = scores.parse(data)
    local e = back[2][1]
    check(e.score == 1250400 and e.name == "JOEL" and e.har == 2 and e.pilot == 9, "scores: round trip")
    check(back[2][2].name == "ANGEL" and back[1][1].score == 0, "scores: other entries")
    check(scores.slot(back, 2, 500000) == 2 and scores.slot(back, 2, 0) == nil, "scores: slot")
    check(scores.slot(back, 2, 2000000) == 1, "scores: a new top score")
    scores.insert(back, 2, 2, { score = 500000, name = "ACE", har = 0, pilot = 0 })
    check(back[2][3].name == "ANGEL" and #back[2] == 20, "scores: entries move down, 20 kept")
end

do
    -- the announcer's scoring
    gfx.text_width = function(s) return #s * 6 end
    package.loaded["game.res"] = { text = function(id)
        return ({ [201] = " CONSECUTIVE HITS", [202] = " HIT COMBO", [203] = "PERFECT ROUND", [204] = "VITALITY",
                  [205] = "SCRAP BONUS", [206] = "DESTRUCTION BONUS" })[id] or ""
    end }
    package.loaded["game.score"] = nil
    local Score = require("game.score")
    check(Score.format(1234567) == "1,234,567" and Score.format(600) == "600", "score: commas")
    check(Score.multiplier(1) == 20 and Score.multiplier(5) == 100 and Score.multiplier(6) == 150
        and Score.multiplier(7) == 200 and Score.multiplier(nil) == 100, "score: multipliers")
    local s = Score.new(1, true, 100, 1000)
    for _ = 1, 5 do s:hit(6) end
    check(s.total == 1000 + 3000, "score: hits x multiplier")
    s:end_combo(100, 100)
    check(#s.texts == 1 and s.texts[1].text == "5 HIT COMBO 12,000", "score: combo callout")
    s:interrupted(100, 100)
    check(#s.texts == 2 and s.texts[2].text == "5 CONSECUTIVE HITS 3,000", "score: consecutive callout")
    s:victory(100, 100, 100)
    check(s.texts[3].text == "PERFECT ROUND 200,000" and s.texts[4].text == "VITALITY 200,000", "score: perfect")
    for _ = 1, 1000 do s:tick() end
    check(not s:busy() and s.total == 4000 + 12000 + 3000 + 400000, "score: callouts land in the total")
    local cpu = Score.new(2, false, 100)
    cpu:hit(6); cpu:hit(6); cpu:end_combo(0, 0)
    check(cpu.total == 0 and cpu.texts[1].text == "2 HIT COMBO", "score: the computer scores nothing")
    local short = Score.new(1, true, 100)
    short:hit(5); short:hit(5); short:hit(5); short:interrupted(0, 0)
    check(#short.texts == 0, "score: three in a row isn't a run")
end

if fails > 0 then error(fails .. " Lua test(s) failed") end
print("all Lua tests passed")
