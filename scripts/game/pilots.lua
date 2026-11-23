-- The pilots of one/two player matches: power, agility and endurance (the
-- stats the HAR formulas use) and their three HAR colours, indices into
-- ALTPALS.DAT's first palette (16 colours each). Values from OpenOMF's
-- resources/pilots.c, which marks the colours as eyeballed.

local M = {
    { name = "CRYSTAL",   power = 5,  agility = 16, endurance = 9,  colors = { 5, 11, 8 },  female = true },
    { name = "STEFFAN",   power = 13, agility = 9,  endurance = 8,  colors = { 10, 15, 7 } },
    { name = "MILANO",    power = 7,  agility = 20, endurance = 4,  colors = { 11, 12, 7 } },
    { name = "CHRISTIAN", power = 9,  agility = 7,  endurance = 15, colors = { 8, 15, 6 } },
    { name = "SHIRRO",    power = 20, agility = 1,  endurance = 8,  colors = { 4, 7, 14 } },
    { name = "JEAN-PAUL", power = 9,  agility = 10, endurance = 11, colors = { 1, 7, 6 } },
    { name = "IBRAHIM",   power = 10, agility = 1,  endurance = 20, colors = { 8, 6, 14 } },
    { name = "ANGEL",     power = 7,  agility = 10, endurance = 13, colors = { 0, 15, 7 },  female = true },
    { name = "COSSETTE",  power = 14, agility = 8,  endurance = 8,  colors = { 0, 8, 2 },   female = true },
    { name = "RAVEN",     power = 14, agility = 4,  endurance = 12, colors = { 9, 10, 4 } },
}

--- Writes a player's HAR colours into the base palette: player p's HAR uses
--- indices p*48 .. p*48+47, three bands of 16 (OpenOMF
--- palette_load_altpal_player_color). `altpal` is ALTPALS.DAT palette 0.
function M.load_colors(altpal, player, pilot)
    if not altpal then return end
    for band = 0, 2 do
        local src = pilot.colors[band + 1] * 16
        local dst = player * 48 + band * 16
        gfx.set_base(altpal:sub(src * 3 + 1, (src + 16) * 3), dst)
    end
    gfx.base_color(0, 0, 0, 0)
end

return M
