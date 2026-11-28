-- ADVANCED SETTINGS (CONFIGURATION > ADVANCED SETTINGS): how the picture
-- is enlarged, smoothed and sharpened (game/settings.lua). Changes show
-- at once, over the menu's own animations; they're saved when you leave.
--
-- Up/Down pick a line, Left/Right (or Enter) change it, Esc or DONE leaves.

local Stage    = require("core.stage")
local scenes   = require("core.scenes")
local res      = require("game.res")
local settings = require("game.settings")
local ui       = require("ui.menu")

local M = {}

local SCALES = { "OFF", "2X", "3X", "4X" }

local HELP = {
    upscale = { "DRAW THE PICTURE AT 2, 3 OR 4", "TIMES THE ORIGINAL 320X200" },
    smoothing = { "ROUND OFF JAGGED EDGES: THE", "FIGHTERS AND ANIMATIONS, OR ALL" },
    sharpen = { "CRISPEN DETAIL AND EDGES", "(WORKS WITH OR WITHOUT UPSCALE)" },
    soft = { "SOFT BLENDS THE PIXELS WHEN THE", "PICTURE IS STRETCHED TO THE WINDOW" },
    back = { "SAVE AND GO BACK", "" },
}

function M:enter(args)
    self.back = args and args.back or require("scenes.configuration")
    self.bk = res.bk("MAIN.BK")
    self.stage = Stage.new(self.bk, {
        startup = function(id) if id == 10 or id == 11 then return true, true end end,
    })
    if not audio.music_playing() then audio.music("MENU.PSM", true) end
    self.sel = 1
end

function M:lines()
    local v = settings.values
    local smoothing = v.upscale > 1 and settings.SMOOTHING[v.smoothing] or "NEEDS UPSCALE"
    return {
        { key = "upscale", label = "UPSCALE    " .. SCALES[v.upscale] },
        { key = "smoothing", label = "SMOOTHING  " .. smoothing },
        { key = "sharpen", label = "SHARPEN    " .. settings.SHARPEN[v.sharpen] },
        { key = "soft", label = "SCREEN     " .. (v.soft and "SOFT" or "SHARP") },
        { key = "back", label = "DONE" },
    }
end

local function cycle(v, d, lo, hi) return (v - lo + d) % (hi - lo + 1) + lo end

function M:change(key, d)
    local v = settings.values
    if key == "upscale" then v.upscale = cycle(v.upscale, d, 1, 4)
    elseif key == "smoothing" then
        if v.upscale == 1 then v.upscale = 2 end   -- smoothing needs room to draw in
        v.smoothing = cycle(v.smoothing, d, 0, 2)
    elseif key == "sharpen" then v.sharpen = cycle(v.sharpen, d, 0, 3)
    elseif key == "soft" then v.soft = not v.soft end
    settings.apply()
end

function M:close()
    settings.save()
    scenes.switch(self.back)
end

function M:update(dt)
    local lines = self:lines()
    if input.pressed("up", "pad_up") then self.sel = (self.sel - 2) % #lines + 1 end
    if input.pressed("down", "pad_down") then self.sel = self.sel % #lines + 1 end
    local key = lines[self.sel].key
    if input.pressed("left", "pad_left") then self:change(key, -1) end
    if input.pressed("right", "pad_right") then self:change(key, 1) end
    if input.pressed("return", "space", "pad_a", "pad_start") then
        if key == "back" then self:close(); return end
        self:change(key, 1)
    end
    if input.pressed("escape", "pad_b") then self:close(); return end
    self.stage:update(dt)
end

function M:draw()
    ui.pulse(self.stage.tick // 3)
    self.stage:draw()
    local lines = self:lines()
    local x, y, w = 50, 40, 220
    local h = #lines * 11 + 14
    ui.panel(self.bk, x, y, w, h)
    local title = "ADVANCED SETTINGS"
    gfx.text(title, x + (w - gfx.text_width(title, 0)) // 2, y - 10, ui.COLOR_ACTIVE, 0)
    for i, l in ipairs(lines) do
        local c = i == self.sel and ui.COLOR_ACTIVE or ui.COLOR_INACTIVE
        local tx = l.key == "back" and (x + (w - gfx.text_width(l.label, 1)) // 2) or (x + 10)
        gfx.text(l.label, tx, y + 8 + (i - 1) * 11, c, 1)
    end
    local help = HELP[lines[self.sel].key]
    for i, s in ipairs(help) do
        gfx.text(s, (320 - gfx.text_width(s, 1)) // 2, y + h + 8 + (i - 1) * 9, ui.COLOR_INACTIVE, 1)
    end
end

return M
