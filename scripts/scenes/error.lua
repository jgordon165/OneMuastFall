-- A script error, on screen (the C++ host switches here when game.update or
-- game.draw fails), so a failure is never just a black screen. The message
-- is in the log too (stderr; onemustfall.log on the Xbox 360).

local tiny = require("ui.tinyfont")

local M = {}

function M:enter(msg)
    self.lines = tiny.wrap(tostring(msg or "unknown error"), 74)
    self.wait = 500       -- ignore buttons held from before the error
    gfx.set_base(string.rep("\0\0\0", 256))
    gfx.base_color(1, 255, 255, 255)
    gfx.base_color(2, 255, 90, 60)
    gfx.base_color(3, 160, 160, 160)
    gfx.reset_palette()
    audio.stop_all()
    audio.stop_music()
end

function M:update(dt)
    self.wait = self.wait - dt
    if self.wait <= 0 and input.pressed("escape", "return") then sys.quit() end
end

function M:draw()
    gfx.clear(0)
    tiny.text("ONEMUASTFALL STOPPED WITH A SCRIPT ERROR", 8, 8, 2)
    for i, l in ipairs(self.lines) do
        if i > 24 then break end
        tiny.text(l, 8, 20 + (i - 1) * 7, 1)
    end
    local hint = sys.platform == "xenon" and "ALSO IN ONEMUSTFALL.LOG.  START OR BACK EXITS" or "ALSO IN THE LOG.  ESC EXITS"
    tiny.text(hint, 8, 190, 3)
end

return M
