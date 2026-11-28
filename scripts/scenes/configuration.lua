-- CONFIGURATION, from the main menu. The original's sound and control
-- pages aren't ported yet; ADVANCED SETTINGS holds this port's own options
-- (picture upscaling and smoothing, scenes/advanced.lua).

local Stage  = require("core.stage")
local scenes = require("core.scenes")
local res    = require("game.res")
local ui     = require("ui.menu")

local M = {}

M.ITEMS = {
    { label = "ADVANCED SETTINGS", open = "scenes.advanced" },
    { label = "DONE" },
}

function M:enter()
    self.bk = res.bk("MAIN.BK")
    self.stage = Stage.new(self.bk, {
        startup = function(id) if id == 10 or id == 11 then return true, true end end,
    })
    if not audio.music_playing() then audio.music("MENU.PSM", true) end
    self.sel = self.sel or 1
end

function M:update(dt)
    local n = #M.ITEMS
    if input.pressed("up", "pad_up") then self.sel = (self.sel - 2) % n + 1 end
    if input.pressed("down", "pad_down") then self.sel = self.sel % n + 1 end
    if input.pressed("return", "space", "pad_a", "pad_start") then
        local it = M.ITEMS[self.sel]
        if it.open then scenes.switch(require(it.open), { back = M }) else scenes.switch(require("scenes.menu")) end
        return
    end
    if input.pressed("escape", "pad_b") then scenes.switch(require("scenes.menu")); return end
    self.stage:update(dt)
end

function M:draw()
    ui.pulse(self.stage.tick // 3)
    self.stage:draw()
    local x, y, w = 80, 60, 160
    local h = #M.ITEMS * 11 + 14
    ui.panel(self.bk, x, y, w, h)
    local title = "CONFIGURATION"
    gfx.text(title, x + (w - gfx.text_width(title, 0)) // 2, y - 10, ui.COLOR_ACTIVE, 0)
    for i, it in ipairs(M.ITEMS) do
        local c = i == self.sel and ui.COLOR_ACTIVE or ui.COLOR_INACTIVE
        gfx.text(it.label, x + (w - gfx.text_width(it.label, 1)) // 2, y + 8 + (i - 1) * 11, c, 1)
    end
end

return M
