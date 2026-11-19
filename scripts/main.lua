-- One Must Fall 2097 port: Lua entry point.
--
-- The C++ host calls game.init(), then game.update(dt) and game.draw() every
-- frame. All game data comes from the player's own copy of the game (--data),
-- read straight out of the original files at runtime.

local scenes = require("core.scenes")
local res    = require("game.res")

game = {}

function game.init()
    sys.log("data folder: " .. sys.data_path .. (fs.mounted() and "" or " (NOT FOUND)"))
    local report = res.check()
    for _, line in ipairs(report.log) do sys.log(line) end
    if not report.ok then
        scenes.switch(require("scenes.nodata"), report)
        return
    end
    res.init()

    if sys.smoke then
        scenes.switch(require("scenes.smoke"))
    elseif sys.explorer then
        scenes.switch(require("scenes.explorer"))
    elseif sys.skip_intro or os.getenv("OMF_SKIP_INTRO") then
        scenes.switch(require("scenes.menu"))
    else
        scenes.switch(require("scenes.intro"))
    end
end

function game.update(dt)
    -- F12 opens the asset explorer from anywhere (and closes it again).
    if input.pressed("f12") and res.ready then
        local top = scenes.top()
        if top == require("scenes.explorer") then
            if #scenes.stack > 1 then scenes.pop() else scenes.switch(require("scenes.menu")) end
        else
            scenes.push(require("scenes.explorer"))
        end
        return
    end
    scenes.update(dt)
end

function game.draw()
    scenes.draw()
end

function game.shutdown()
    audio.stop_all()
    audio.stop_music()
end
