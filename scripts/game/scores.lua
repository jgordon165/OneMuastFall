-- The high scores: SCORES.DAT, as the original keeps it. 4 pages (one per
-- ROUNDS setting: one round, best 2 of 3, 3 of 5, 4 of 7) x 20 entries of
-- 24 bytes: score (u32), name (16 bytes, NUL-terminated), then a u32 with
-- the HAR in bits 0-5 and the pilot in bits 6-11.
--
-- Read from the preferences folder if this port has saved one there,
-- otherwise from the game folder; saved to the preferences folder (the
-- game folder is treated as read-only).

local M = {}

M.FILE = "SCORES.DAT"
M.PAGES, M.ENTRIES = 4, 20
local SIZE = 24

local function empty()
    local pages = {}
    for p = 1, M.PAGES do
        pages[p] = {}
        for e = 1, M.ENTRIES do pages[p][e] = { score = 0, name = "", har = 0, pilot = 0, rest = 0 } end
    end
    return pages
end

function M.parse(data)
    local pages = empty()
    if not data or #data < M.PAGES * M.ENTRIES * SIZE then return pages end
    local at = 1
    for p = 1, M.PAGES do
        for e = 1, M.ENTRIES do
            local score, name, id = string.unpack("<I4c16I4", data, at)
            at = at + SIZE
            pages[p][e] = {
                score = score, name = name:match("^[^%z]*"),
                har = id & 0x3F, pilot = (id >> 6) & 0x3F, rest = id >> 12,
            }
        end
    end
    return pages
end

function M.serialize(pages)
    local out = {}
    for p = 1, M.PAGES do
        for e = 1, M.ENTRIES do
            local it = pages[p][e]
            local name = it.name:sub(1, 15)
            out[#out + 1] = string.pack("<I4c16I4", it.score, name .. string.rep("\0", 16 - #name),
                (it.har & 0x3F) | ((it.pilot & 0x3F) << 6) | ((it.rest or 0) << 12))
        end
    end
    return table.concat(out)
end

function M.load()
    return M.parse(sys.load(M.FILE) or fs.read(M.FILE))
end

function M.save(pages)
    return sys.save(M.FILE, M.serialize(pages))
end

--- Where a score would go on a page (1..20), or nil if it doesn't make it.
function M.slot(pages, page, score)
    if score <= 0 then return nil end
    for e = 1, M.ENTRIES do
        if score > pages[page][e].score then return e end
    end
end

--- Put an entry in at `slot`, pushing the rest down.
function M.insert(pages, page, slot, entry)
    table.insert(pages[page], slot, entry)
    pages[page][M.ENTRIES + 1] = nil
end

return M
