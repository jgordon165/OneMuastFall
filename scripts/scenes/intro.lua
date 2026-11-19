-- The intro (INTRO.BK), played by its own animation scripts.
--
-- As in the original only animation 25 starts by itself (on the top layer);
-- it spawns the rest through its m tags: the logo, the robots walking out,
-- the flashes, and in the end the menu music (smo2). After 25 seconds, or
-- any of Esc / Enter / Space / a pad button, the main menu takes over.

local Stage  = require("core.stage")
local scenes = require("core.scenes")
local res    = require("game.res")

local M = {}

local LENGTH_TICKS = 2500     -- OpenOMF intro.c

function M:enter()
    self.stage = Stage.new(res.bk("INTRO.BK"), {
        startup = function(id)
            if id == 25 then return true, false, Stage.LAYER_TOP end
        end,
    })
end

function M:leave()
    self.stage = nil
end

function M:update(dt)
    if input.pressed("escape", "return", "space", "pad_a", "pad_start", "pad_b") then
        scenes.switch(require("scenes.menu"))
        return
    end
    self.stage:update(dt)
    if self.stage.tick >= LENGTH_TICKS then
        scenes.switch(require("scenes.menu"))
    end
end

function M:draw()
    self.stage:draw()
end

return M
