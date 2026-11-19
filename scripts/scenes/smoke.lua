-- --smoke: runs every animation of every BK and AF in the game folder
-- through the script player for a while, drawing each tick, and quits with
-- a report. A test of the interpreter against all of the original data
-- (ctest runs it when OMF_DATA is set).

local Stage = require("core.stage")

local M = {}

local TICKS = 400

local function run_all(name, anims, base, stl)
    local n, ticks = 0, 0
    for id, a in pairs(anims) do
        local bk = { anims = anims, palettes = base.palettes, remaps = base.remaps,
                     sound_table = stl, background = base.background }
        local st = Stage.new(bk)
        st.no_music = true
        local o = st:add(a, a.start_x or 0, a.start_y or 0)
        o.repeat_ = false
        st:flush()
        for _ = 1, TICKS do
            st:step()
            if #st.objects == 0 then break end
            ticks = ticks + 1
        end
        st:draw()
        n = n + 1
    end
    return n, ticks
end

function M:enter()
    local total, errors = 0, 0
    local arena = omf.bk("ARENA0.BK")
    for _, e in ipairs(fs.list()) do
        local ext = (e.name:match("%.(%w+)$") or ""):upper()
        local ok, err = true, nil
        if ext == "BK" then
            ok, err = pcall(function()
                local bk = assert(omf.bk(e.name))
                local n, t = run_all(e.name, bk.anims, bk, bk.sound_table)
                total = total + n
                sys.log(string.format("  %-12s %3d animations, %6d ticks", e.name, n, t))
            end)
        elseif ext == "AF" then
            ok, err = pcall(function()
                local af = assert(omf.af(e.name))
                local n, t = run_all(e.name, af.moves, arena, af.sound_table)
                total = total + n
                sys.log(string.format("  %-12s %3d moves,      %6d ticks", e.name, n, t))
            end)
        end
        if not ok then
            errors = errors + 1
            sys.log("FAIL " .. e.name .. ": " .. tostring(err))
        end
    end
    audio.stop_all()
    sys.log(string.format("smoke: %d animations run, %d failures", total, errors))
    self.failed = errors > 0
    sys.smoke_failed = self.failed
    sys.quit()
end

function M:draw() end

return M
