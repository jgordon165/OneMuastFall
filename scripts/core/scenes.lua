-- Scene stack. A scene is a table with optional enter(args), leave(),
-- update(dt) and draw(). Only the top one updates; draw goes bottom-up from
-- the topmost scene that isn't an overlay.

local M = { stack = {} }

local function call(s, fn, ...)
    if s and s[fn] then return s[fn](s, ...) end
end

function M.top() return M.stack[#M.stack] end

function M.switch(scene, args)
    while #M.stack > 0 do call(table.remove(M.stack), "leave") end
    M.stack[1] = scene
    call(scene, "enter", args)
end

function M.push(scene, args)
    M.stack[#M.stack + 1] = scene
    call(scene, "enter", args)
end

function M.pop()
    local s = table.remove(M.stack)
    call(s, "leave")
    call(M.top(), "resume")
    return s
end

function M.update(dt) call(M.top(), "update", dt) end

function M.draw()
    local first = #M.stack
    while first > 1 and M.stack[first].overlay do first = first - 1 end
    for i = first, #M.stack do call(M.stack[i], "draw") end
end

return M
