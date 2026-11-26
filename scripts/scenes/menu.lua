-- The main menu (MAIN.BK): the two looping animations of the background
-- (ids 10 and 11), MENU.PSM, and the menu panel on the right.
--
-- Items follow the original's main menu. The ones whose scenes aren't
-- ported yet say so when picked.

local Stage  = require("core.stage")
local scenes = require("core.scenes")
local res    = require("game.res")
local ui     = require("ui.menu")

local M = {}

local function not_yet(it)
    M.notice = it.label .. ": NOT PORTED YET"
    M.notice_ticks = 200
end

function M:enter()
    self.bk = res.bk("MAIN.BK")
    self.stage = Stage.new(self.bk, {
        startup = function(id)
            if id == 10 or id == 11 then return true, true end
        end,
    })
    if not audio.music_playing() then audio.music("MENU.PSM", true) end
    self.menu = ui.new({
        { label = "ONE PLAYER GAME", action = function() scenes.switch(require("scenes.melee"), { vs_ai = true }) end },
        { label = "TWO PLAYER GAME", action = function() scenes.switch(require("scenes.melee"), { vs_ai = false }) end },
        { label = "TOURNAMENT PLAY", action = not_yet },
        { label = "NETWORK PLAY",    action = not_yet },
        { label = "CONFIGURATION",   action = not_yet },
        { label = "GAMEPLAY",        action = function() scenes.switch(require("scenes.gameplay")) end },
        { label = "HELP",            action = not_yet },
        { label = "DEMO",            action = function() scenes.switch(require("scenes.intro")) end },
        { label = "SCOREBOARD",      action = not_yet },
        { label = "QUIT",            action = function() sys.quit() end,
          disabled = not sys.can_exit },   -- the XeLL build has nowhere to go
    }, 165, 5, 151, 119)
    M.notice, M.notice_ticks = nil, 0
end

function M:leave()
    self.stage = nil
end

function M:update(dt)
    if input.pressed("escape") and sys.can_exit then
        self.menu.sel = #self.menu.items   -- Esc goes to QUIT, as in the original
    end
    ui.update(self.menu)
    if scenes.top() ~= self then return end   -- an item switched scenes
    self.stage:update(dt)
    if M.notice_ticks > 0 then
        M.notice_ticks = M.notice_ticks - dt / 10
        if M.notice_ticks <= 0 then M.notice = nil end
    end
end

function M:draw()
    ui.pulse(self.stage.tick // 3)
    self.stage:draw()
    ui.draw(self.menu, self.bk)
    if M.notice then
        local w = gfx.text_width(M.notice, 1) + 12
        local x = (320 - w) // 2
        ui.panel(self.bk, x, 180, w, 14)
        gfx.text(M.notice, x + 6, 184, ui.COLOR_ACTIVE, 1)
    end
end

return M
