-- The original files the port reads, and the shared resources loaded once
-- at start (sounds, fonts, text).

local M = { ready = false }

-- What a playable copy of OMF:2097 must have (the freeware release has
-- them all). Names are matched in any case.
M.REQUIRED = {
    "INTRO.BK", "MAIN.BK", "SOUNDS.DAT", "ENGLISH.DAT", "GRAPHCHR.DAT", "CHARSMAL.DAT",
    "MENU.PSM", "ALTPALS.DAT",
}
M.SCENES = {
    intro = "INTRO.BK", menu = "MAIN.BK", arena0 = "ARENA0.BK", arena1 = "ARENA1.BK",
    arena2 = "ARENA2.BK", arena3 = "ARENA3.BK", arena4 = "ARENA4.BK", newsroom = "NEWSROOM.BK",
    ["end"] = "END.BK", end1 = "END1.BK", end2 = "END2.BK", credits = "CREDITS.BK",
    mechlab = "MECHLAB.BK", melee = "MELEE.BK", vs = "VS.BK",
}
-- HARs by fighter id (FIGHTRn.AF)
M.HARS = { [0] = "Jaguar", "Shadow", "Thorn", "Pyros", "Electra", "Katana", "Shredder", "Flail",
           "Gargoyle", "Chronos", "Nova" }

function M.check()
    local r = { ok = true, log = {}, missing = {} }
    if not fs.mounted() then
        r.ok = false
        r.log[#r.log + 1] = "game folder not found: " .. sys.data_path
        return r
    end
    for _, f in ipairs(M.REQUIRED) do
        if not fs.exists(f) then
            r.ok = false
            r.missing[#r.missing + 1] = f
            r.log[#r.log + 1] = "missing " .. f
        end
    end
    for i = 0, 10 do
        local f = "FIGHTR" .. i .. ".AF"
        if not fs.exists(f) then r.missing[#r.missing + 1] = f; r.ok = false end
    end
    if r.ok then r.log[#r.log + 1] = "One Must Fall 2097 data found" end
    return r
end

function M.init()
    if M.ready then return end
    local ok = omf.load_fonts()
    if not ok then sys.log("fonts missing") end
    local snd, err = omf.load_sounds()
    M.sounds = snd or {}
    if not snd then sys.log(err) end
    M.lang = omf.lang("ENGLISH.DAT") or {}
    audio.music_volume(70)
    M.ready = true
end

-- A string from ENGLISH.DAT by id (0-based, as the game numbers them).
function M.text(id)
    local s = M.lang[id]
    return s and s.text or ""
end

local bk_cache = {}
function M.bk(name)
    if not bk_cache[name] then
        local bk, err = omf.bk(name)
        if not bk then error(err) end
        bk_cache[name] = bk
    end
    return bk_cache[name]
end

return M
