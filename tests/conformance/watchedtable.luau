-- This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
print('testing watched tables')

-- watch(t) watches t and answers whether it is watched; iswatched(t) reads the mark;
-- unwatch(t) ends the watch; setwatchlist(list) names the list a write reports into

local function count(t)
    local n = 0
    for _ in pairs(t) do
        n += 1
    end
    return n
end

-- run `write` on a watched table built by `make` and check that the write is reported once, lands, and ends the watch
local function reports(label, make, write, check)
    local list = {}
    setwatchlist(list)
    local t = make()
    assert(watch(t), label .. ": the table is watched")
    assert(iswatched(t), label .. ": the mark reads watched")
    write(t)
    assert(list[t] == true, label .. ": the write reports the table")
    assert(count(list) == 1, label .. ": the write reports it alone")
    assert(not iswatched(t), label .. ": the write ends the watch")
    check(t)
    -- the next write takes the fast path and reports nothing
    table.clear(list)
    write(t)
    assert(next(list) == nil, label .. ": a write after the reported one reports nothing")
    setwatchlist(nil)
end

reports("field assignment", function() return { x = 1 } end, function(t) t.x = 2 end, function(t) assert(t.x == 2) end)
reports("new field", function() return {} end, function(t) t.y = 3 end, function(t) assert(t.y == 3) end)
reports("computed string key", function() return { k = 0 } end, function(t)
    local key = "k"
    t[key] = 5
end, function(t) assert(t.k == 5) end)
reports("constant index", function() return { 1, 2, 3 } end, function(t) t[2] = 20 end, function(t) assert(t[2] == 20) end)
reports("variable index", function() return { 1, 2, 3 } end, function(t)
    local i = 3
    t[i] = 30
end, function(t) assert(t[3] == 30) end)
reports("append", function() return { 1, 2 } end, function(t) t[#t + 1] = 9 end, function(t) assert(t[3] == 9 or t[4] == 9) end)
reports("rawset", function() return {} end, function(t) rawset(t, "r", 1) end, function(t) assert(t.r == 1) end)
reports("table.insert", function() return { 1 } end, function(t) table.insert(t, 2) end, function(t) assert(t[2] == 2) end)
reports("table.insert at", function() return { 1, 2 } end, function(t) table.insert(t, 1, 0) end, function(t) assert(t[1] == 0) end)
reports("table.remove", function() return { 1, 2, 3, 4, 5, 6 } end, function(t) table.remove(t) end, function(t) assert(#t <= 5) end)
reports("table.move", function() return { 0, 0 } end, function(t) table.move({ 7, 8 }, 1, 2, 1, t) end, function(t) assert(t[1] == 7 and t[2] == 8) end)
reports("table.sort", function() return { 3, 1, 2 } end, function(t) table.sort(t) end, function(t) assert(t[1] <= t[2] and t[2] <= t[3]) end)
reports("table.clear", function() return { 1, a = 2 } end, function(t) table.clear(t) end, function(t) assert(next(t) == nil) end)
reports("setmetatable", function() return {} end, function(t) setmetatable(t, { __index = function() return 1 end }) end, function(t)
    assert(getmetatable(t) ~= nil)
end)

-- a write in a loop that runs often enough to take every fast path is reported on its first run
do
    local list = {}
    setwatchlist(list)
    local t = { n = 0, 0, 0, 0 }
    for round = 1, 3 do
        assert(watch(t))
        for i = 1, 1000 do
            t.n += 1
            t[1 + i % 3] = i
        end
        assert(list[t] == true, "a hot loop reports its table")
        table.clear(list)
    end
    assert(t.n == 3000)
    setwatchlist(nil)
end

-- reads report nothing and keep the watch
do
    local list = {}
    setwatchlist(list)
    local t = { a = 1, 2, 3 }
    assert(watch(t))
    local sum = t.a + t[1] + #t
    for _, v in pairs(t) do
        sum += v
    end
    for _, v in ipairs(t) do
        sum += v
    end
    assert(sum == 1 + 2 + 2 + 6 + 5)
    assert(next(list) == nil, "a read reports nothing")
    assert(iswatched(t), "a read keeps the watch")
    unwatch(t)
    assert(not iswatched(t))
    t.a = 2
    assert(next(list) == nil, "a write after the watch ended reports nothing")
    setwatchlist(nil)
end

-- a watched table is not frozen, freezes, and a frozen table cannot be watched
do
    local t = { 1 }
    assert(watch(t))
    assert(not table.isfrozen(t), "a watched table reads as not frozen")
    table.freeze(t)
    assert(table.isfrozen(t))
    assert(not iswatched(t), "freezing ends the watch")
    assert(not watch(t), "a frozen table cannot be watched")
    assert(not pcall(function() t[1] = 2 end), "a frozen table still refuses a write")
end

-- the watch list cannot watch itself, and with no list a write ends the watch and lands
do
    local list = {}
    setwatchlist(list)
    assert(not watch(list), "the watch list cannot be watched")
    setwatchlist(nil)
    local t = {}
    assert(watch(t))
    t.a = 1
    assert(t.a == 1 and not iswatched(t))
end

-- the list holds the tables it records until the host takes them out
do
    local list = {}
    setwatchlist(list)
    do
        local t = {}
        assert(watch(t))
        t.a = 1
    end
    collectgarbage()
    local held = next(list)
    assert(type(held) == "table" and held.a == 1, "the list keeps a reported table alive")
    setwatchlist(nil)
end

return 'OK'
