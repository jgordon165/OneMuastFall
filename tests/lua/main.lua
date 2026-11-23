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

if fails > 0 then error(fails .. " Lua test(s) failed") end
print("all Lua tests passed")
