-- The animation string: OMF:2097's little per-frame scripting language.
--
-- Every BK and AF animation has one, e.g.
--   "bps0bpd63bpn255bpp64bpb0s1A10-bps0bpd63bpn255bpp64A10-B5000"
-- Frames are separated by '-'. A frame is any number of tags (lowercase,
-- one to three letters, some followed by a signed number) and ends with the
-- sprite letter (A = sprite 0 ... Z = 25, Z usually meaning "nothing") and
-- the frame's length in ticks.
--
-- The tag set and the parsing rules (longest tag first; a tag that takes no
-- number is skipped over if a number follows it, so "x" doesn't eat "x=")
-- come from OpenOMF's formats/script.c and tag_list.c.

local M = {}

-- tag -> true if it takes a number
M.TAGS = {
    aa=false, ab=false, ac=false, ad=false, ae=false, af=false, ag=false, ai=false, am=false,
    ao=false, as=false, at=false, aw=false, ax=false, ar=false, al=false,
    b=false, b1=false, b2=false, bb=true, be=false, bf=true, bh=false, bl=true, bm=true,
    bj=true, bs=true, bu=false, bw=false, bx=false, bpd=true, bps=true, bpn=true, bpf=false,
    bpp=true, bpb=true, bpo=false, bz=false, ba=true, bc=true, bd=false, bg=false, bi=true,
    bk=true, bn=false, bo=true, br=false, bt=false, by=false,
    cf=false, cg=false, cl=false, cp=false, cw=false, cx=true, cy=true,
    d=true, e=false, f=false, g=false, h=false, i=false,
    jf2=false, jf=false, jg=false, jh=false, jj=false, jl=false, jm=false, jp=false, jz=false, jn=true,
    k=true, l=true,
    ma=true, mc=false, md=true, mg=true, mi=true, mm=true, mn=true, mo=false, mp=true,
    mrx=true, mry=true, ms=false, mu=true, mx=true, my=true, m=true,
    n=false, ox=true, oy=true,
    pa=false, pb=true, pc=true, pd=true, pe=false, ph=false, pp=true, ps=false,
    ptd=true, ptp=true, ptr=true,
    q=true, r=false,
    s=true, sa=false, sb=true, sc=true, sd=false, se=true, sf=true, sl=true, smf=true,
    smo=true, sp=true, sw=true,
    t=false, u=false, ua=false, ub=false, uc=false, ud=false, ue=false, uf=false, ug=false,
    uh=false, uj=false, ul=false, un=false, ur=false, us=false, uz=false,
    v=false, vsx=false, vsy=false, w=false,
    ["x-"]=true, ["x+"]=true, ["x="]=true, x=true,
    ["y-"]=true, ["y+"]=true, ["y="]=true, y=true,
    zg=false, zh=false, zj=false, zl=false, zm=false, zp=false, zz=false,
}
-- Letters the original files use as lone, meaningless tags.
local INVALID = { c = true, o = true, p = true, z = true }

local byte, sub = string.byte, string.sub
local A, Z, a_, z_ = byte("A"), byte("Z"), byte("a"), byte("z")
local D0, D9, MINUS, PLUS = byte("0"), byte("9"), byte("-"), byte("+")

local function is_value_start(c) return c and ((c >= D0 and c <= D9) or c == MINUS or c == PLUS) end

-- Reads [+-]digits at i. Returns value (0 if no digits), next index.
local function read_long(s, i)
    local sign = 1
    local c = byte(s, i)
    if c == MINUS then sign = -1; i = i + 1 elseif c == PLUS then i = i + 1 end
    local v, found = 0, false
    c = byte(s, i)
    while c and c >= D0 and c <= D9 do
        v = v * 10 + (c - D0); i = i + 1; found = true
        c = byte(s, i)
    end
    v = sign * v
    if v > 32767 then v = 32767 elseif v < -32768 then v = -32768 end
    return found and v or 0, i
end

-- Parses an animation string. Returns a script:
--   { frames = { {sprite=0..25, ticks=n, start=tick, tags={name=value|true}, order={names}} },
--     total = total ticks, source = s }
function M.parse(s)
    local frames, n, i, total = {}, #s, 1, 0
    while i <= n do
        local start_i = i
        local fr = { tags = {}, order = {} }
        local ok = false
        while i <= n do
            local c = byte(s, i)
            if c >= A and c <= Z then
                fr.sprite = c - A
                fr.ticks, i = read_long(s, i + 1)
                i = i + 1                     -- the '-'
                ok = true
                break
            end
            local matched = false
            if c >= a_ and c <= z_ then
                for len = math.min(3, n - i + 1), 1, -1 do
                    local name = sub(s, i, i + len - 1)
                    local has = M.TAGS[name]
                    if has ~= nil and not (not has and is_value_start(byte(s, i + len))) then
                        i = i + len
                        local v = true
                        if has then v, i = read_long(s, i) end
                        if fr.tags[name] == nil then fr.order[#fr.order + 1] = name end
                        fr.tags[name] = v
                        matched = true
                        break
                    end
                end
                if not matched and INVALID[string.char(c)] then
                    i = i + 1
                    matched = true
                end
            end
            if not matched then
                -- unknown: skip to the end of this frame and drop it
                while i <= n and byte(s, i) ~= MINUS do i = i + 1 end
                i = i + 1
                break
            end
        end
        if ok then
            fr.start = total
            total = total + fr.ticks
            frames[#frames + 1] = fr
        end
        if i == start_i then error("animation string stuck at " .. i .. ": " .. s) end
    end
    return { frames = frames, total = total, source = s }
end

local cache = {}
function M.get(s)
    local sc = cache[s]
    if not sc then sc = M.parse(s); cache[s] = sc end
    return sc
end

-- Frame index playing at `tick`, or nil past the end.
function M.frame_at(sc, tick)
    if not tick or tick < 0 then return nil end
    local fs = sc.frames
    for k = 1, #fs do
        local f = fs[k]
        if tick >= f.start and tick < f.start + f.ticks then return k end
    end
    return nil
end

-- The next frame after `tick` that has `tag`, or nil.
function M.next_with(sc, tag, tick)
    for k, f in ipairs(sc.frames) do
        if f.start > tick and f.tags[tag] ~= nil then return k end
    end
    return nil
end

function M.letter(sprite) return string.char(A + sprite) end

return M
