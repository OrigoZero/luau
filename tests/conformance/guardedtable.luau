-- This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
print('testing guarded tables')

-- guard(t) guards t and answers whether it is guarded; isguarded(t) reads the mark; unguard(t) ends the guard;
-- refusing(on) sets whether the host's guardedwrite callback refuses; asked() answers how many writes asked it

-- run `write` on a guarded table built by `make`: refused, it raises the host's message and leaves the table as it
-- was; allowed, it lands, asks the host once and keeps the guard
local function guards(label, make, write, check, unchanged)
    local t = make()
    assert(guard(t), label .. ": the table is guarded")
    assert(isguarded(t), label .. ": the mark reads guarded")
    assert(not table.isfrozen(t), label .. ": a guarded table reads as not frozen")

    refusing(true)
    local before = asked()
    local ok, err = pcall(write, t)
    assert(not ok, label .. ": a refused write raises")
    assert(string.find(tostring(err), "the host refuses this write", 1, true), label .. ": the error is the host's: " .. tostring(err))
    assert(asked() == before + 1, label .. ": the refused write asked the host once")
    unchanged(t)
    assert(isguarded(t), label .. ": a refused write keeps the guard")

    refusing(false)
    before = asked()
    write(t)
    assert(asked() >= before + 1, label .. ": the allowed write asked the host")
    check(t)
    assert(isguarded(t), label .. ": an allowed write keeps the guard")

    before = asked()
    write(t)
    assert(asked() >= before + 1, label .. ": every later write asks again")
end

local function same(x) return function(t) assert(t.x == x, "unchanged") end end

guards("field assignment", function() return { x = 1 } end, function(t) t.x = 2 end, function(t) assert(t.x == 2) end, same(1))
guards("new field", function() return { x = 1 } end, function(t) t.y = 3 end, function(t) assert(t.y == 3) end, function(t) assert(t.y == nil) end)
guards("computed string key", function() return { x = 1, k = 0 } end, function(t)
    local key = "k"
    t[key] = 5
end, function(t) assert(t.k == 5) end, function(t) assert(t.k == 0) end)
guards("constant index", function() return { 1, 2, 3 } end, function(t) t[2] = 20 end, function(t) assert(t[2] == 20) end, function(t) assert(t[2] == 2) end)
guards("computed index", function() return { 1, 2, 3 } end, function(t)
    local i = 3
    t[i] = 30
end, function(t) assert(t[3] == 30) end, function(t) assert(t[3] == 3) end)
guards("function field", function() return { x = 1, f = function() return 1 end } end, function(t)
    t.f = function() return 2 end
end, function(t) assert(t.f() == 2) end, function(t) assert(t.f() == 1) end)
guards("rawset", function() return { x = 1 } end, function(t) rawset(t, "x", 9) end, function(t) assert(t.x == 9) end, same(1))
guards("table.insert at the end", function() return { 1, 2 } end, function(t) table.insert(t, 3) end, function(t) assert(t[#t] == 3) end, function(t) assert(#t == 2) end)
guards("table.insert at a position", function() return { 1, 2 } end, function(t) table.insert(t, 1, 0) end, function(t) assert(t[1] == 0) end, function(t) assert(t[1] == 1 and #t == 2) end)
guards("table.remove", function() return { 1, 2, 3, 4, 5, 6 } end, function(t) table.remove(t, 1) end, function(t) assert(t[1] ~= 1) end, function(t) assert(t[1] == 1 and #t == 6) end)
guards("table.move into", function() return { 1, 2, 3 } end, function(t) table.move({ 7, 8 }, 1, 2, 1, t) end, function(t) assert(t[1] == 7) end, function(t) assert(t[1] == 1) end)
guards("table.sort", function() return { 3, 1, 2 } end, function(t) table.sort(t) end, function(t) assert(t[1] == 1) end, function(t) assert(t[1] == 3) end)
guards("setmetatable", function() return { x = 1 } end, function(t) setmetatable(t, nil) end, function(t) assert(getmetatable(t) == nil) end, function(t) assert(getmetatable(t) == nil) end)

-- table.clear empties the table, so its allowed run is checked on its own
do
    local t = { x = 1, 2 }
    assert(guard(t))
    refusing(true)
    assert(not pcall(table.clear, t), "a refused clear raises")
    assert(t.x == 1, "a refused clear leaves the entries")
    refusing(false)
    table.clear(t)
    assert(next(t) == nil, "an allowed clear empties the table")
    assert(isguarded(t), "an allowed clear keeps the guard")
end

-- freezing a guarded table asks the host; a frozen table is no longer guarded and refuses every write
do
    local t = { x = 1 }
    assert(guard(t))
    refusing(true)
    assert(not pcall(table.freeze, t), "a refused freeze raises")
    assert(not table.isfrozen(t), "a refused freeze leaves the table writable to the host")
    assert(isguarded(t), "a refused freeze keeps the guard")
    refusing(false)
    table.freeze(t)
    assert(table.isfrozen(t), "an allowed freeze freezes")
    assert(not isguarded(t), "a frozen table is not guarded")
    assert(not pcall(function() t.x = 2 end), "a frozen table refuses a write")
    assert(not guard(t), "a frozen table cannot be guarded")
end

-- reads, iteration and length are untouched by the guard
do
    local t = { a = 1, b = 2, 10, 20 }
    assert(guard(t))
    refusing(true)
    local before = asked()
    local n = 0
    for _ in pairs(t) do
        n += 1
    end
    assert(n == 4, "iteration sees every entry")
    assert(t.a == 1 and t[2] == 20 and #t == 2 and rawget(t, "b") == 2, "reads see every entry")
    assert(asked() == before, "a read asks nothing")
    refusing(false)
end

-- a clone is a table of its own and is not guarded; the guard ends with unguard
do
    local t = { x = 1 }
    assert(guard(t))
    local c = table.clone(t)
    assert(not isguarded(c), "a clone is not guarded")
    refusing(true)
    c.x = 2
    assert(c.x == 2, "a clone takes writes")
    unguard(t)
    assert(not isguarded(t), "unguard ends the guard")
    t.x = 3
    assert(t.x == 3, "an unguarded table takes writes")
    refusing(false)
end

-- a table that is frozen or watched cannot be guarded, and a guarded table cannot be watched
do
    assert(not guard(table.freeze({})), "a frozen table cannot be guarded")
    local t = {}
    assert(guard(t))
    assert(guard(t), "guarding a guarded table answers that it is guarded")
end

-- a write that misses into __newindex leaves the table alone and does not ask
do
    local seen = nil
    local t = setmetatable({}, { __newindex = function(_, k, v) seen = v end })
    assert(guard(t))
    refusing(true)
    local before = asked()
    t.y = 5
    assert(seen == 5 and rawget(t, "y") == nil, "__newindex took the write")
    assert(asked() == before, "a write __newindex takes asks nothing")
    refusing(false)
end

return 'OK'
