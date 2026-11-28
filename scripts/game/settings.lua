-- ADVANCED SETTINGS: upscaling, smoothing and sharpening of the picture.
-- Kept in the preferences folder as advanced.cfg ("key=value" lines) and
-- applied at start-up. OMF_UPSCALE="factor,smoothing,soft,sharpen"
-- overrides them (testing).

local M = {}

M.FILE = "advanced.cfg"

M.SMOOTHING = { [0] = "OFF", "SPRITES", "EVERYTHING" }
M.SHARPEN = { [0] = "OFF", "LOW", "MEDIUM", "HIGH" }

-- the original look by default
M.values = { upscale = 1, smoothing = 0, soft = false, sharpen = 0 }

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function M.load()
    local s = sys.load(M.FILE)
    if s then
        for k, v in s:gmatch("([%w_]+)%s*=%s*([%w_]+)") do
            if k == "upscale" then M.values.upscale = clamp(tonumber(v) or 1, 1, 4)
            elseif k == "smoothing" then M.values.smoothing = clamp(tonumber(v) or 0, 0, 2)
            elseif k == "soft" then M.values.soft = v == "1" or v == "true"
            elseif k == "sharpen" then M.values.sharpen = clamp(tonumber(v) or 0, 0, 3) end
        end
    end
    local env = os.getenv("OMF_UPSCALE")
    if env then
        local f, sm, so, sh = env:match("(%d+),?(%d*),?(%d*),?(%d*)")
        M.values.upscale = clamp(tonumber(f) or 1, 1, 4)
        M.values.smoothing = clamp(tonumber(sm) or 0, 0, 2)
        M.values.soft = so == "1"
        M.values.sharpen = clamp(tonumber(sh) or 0, 0, 3)
    end
    M.apply()
end

function M.save()
    local v = M.values
    sys.save(M.FILE, string.format("upscale=%d\nsmoothing=%d\nsoft=%d\nsharpen=%d\n", v.upscale, v.smoothing,
        v.soft and 1 or 0, v.sharpen))
end

function M.apply()
    local v = M.values
    gfx.upscale(v.upscale, v.upscale > 1 and v.smoothing or 0, v.soft, v.sharpen)
end

return M
