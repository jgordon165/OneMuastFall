-- Shown when the game folder is missing or incomplete. The game's own fonts
-- are in that folder, so this screen draws with a tiny built-in 3x5 font.

local M = {}

local tiny = require("ui.tinyfont")
local text = tiny.text

function M:enter(report)
    self.report = report or { missing = {} }
    gfx.set_base(string.rep("\0\0\0", 256))
    gfx.base_color(1, 255, 255, 255)
    gfx.base_color(2, 255, 200, 60)
    gfx.base_color(3, 140, 140, 140)
    gfx.reset_palette()
end

function M:update()
    if input.pressed("escape", "return") then sys.quit() end
end

function M:draw()
    gfx.clear(0)
    local y = 20
    text("ONE MUST FALL 2097", 20, y, 2); y = y + 12
    text("THE GAME FILES WERE NOT FOUND IN:", 20, y, 1); y = y + 8
    local p = sys.data_path
    while #p > 0 do text(p:sub(1, 70), 20, y, 3); p = p:sub(71); y = y + 7 end
    y = y + 6
    if #self.report.missing > 0 then
        text("MISSING: " .. table.concat(self.report.missing, " ", 1, math.min(8, #self.report.missing)), 20, y, 1)
        y = y + 12
    end
    if sys.platform == "xenon" then
        text("COPY YOUR ONE MUST FALL 2097 FILES INTO", 20, y, 1); y = y + 8
        text("THE DATA FOLDER NEXT TO ONEMUSTFALL.XEX", 20, y, 1); y = y + 8
        text("(INTRO.BK, FIGHTR0.AF, SOUNDS.DAT ... ALL OF THEM)", 20, y, 3); y = y + 8
        text("ONE MUST FALL 2097 IS FREEWARE: SEE README.TXT", 20, y, 3); y = y + 16
        text(sys.can_exit and "BACK OR START EXITS" or "", 20, y, 2)
    else
        text("RUN WITH --DATA <YOUR OMF2097 FOLDER>", 20, y, 1); y = y + 8
        text("(THE ONE WITH FILE0001.EXE, INTRO.BK, FIGHTR0.AF ...)", 20, y, 3); y = y + 8
        text("ONE MUST FALL 2097 IS FREEWARE: SEE README.MD", 20, y, 3); y = y + 16
        text("ESC QUITS", 20, y, 2)
    end
end

return M
