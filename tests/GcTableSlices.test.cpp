// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#include "lua.h"
#include "lualib.h"
#include "luacode.h"

#include "lstate.h"
#include "lgc.h"
#include "ltable.h"

#include "doctest.h"

#include <cstdlib>
#include <cstring>
#include <memory>

namespace
{

struct SlicesFixture
{
    std::unique_ptr<lua_State, void (*)(lua_State*)> state;
    lua_State* L;

    SlicesFixture()
        : state(luaL_newstate(), lua_close)
        , L(state.get())
    {
        luaL_openlibs(L);
    }

    void run(const char* source)
    {
        size_t size = 0;
        char* bytecode = luau_compile(source, strlen(source), nullptr, &size);
        int loaded = luau_load(L, "=slices", bytecode, size, 0);
        free(bytecode);
        REQUIRE(loaded == 0);
        int status = lua_pcall(L, 0, 0, 0);
        INFO((status == 0 ? "" : lua_tostring(L, -1)));
        REQUIRE(status == 0);
    }

    LuaTable* global(const char* name)
    {
        lua_getglobal(L, name);
        REQUIRE(lua_istable(L, -1));
        LuaTable* t = hvalue(L->top - 1);
        lua_pop(L, 1);
        return t;
    }

    // run a full collection, then step the next cycle until the collector holds `t' part-way through its slots
    void stepInto(LuaTable* t)
    {
        lua_gc(L, LUA_GCCOLLECT, 0);

        for (int i = 0; i < 1000000 && L->global->gcpartial != t; ++i)
            lua_gc(L, LUA_GCSTEP, 1);

        REQUIRE(L->global->gcpartial == t);
        REQUIRE(L->global->gcpartialpos > 0);
    }

    // run `source' with the collector stopped, so only the change it makes to the table can end the slicing
    void runStopped(const char* source)
    {
        lua_gc(L, LUA_GCSTOP, 0);
        run(source);
        lua_gc(L, LUA_GCRESTART, 0);
    }

    // a full collection, then allocations that take the memory of every object it freed
    void collectAndReuse()
    {
        lua_gc(L, LUA_GCCOLLECT, 0);
        run("for i = 1, 16384 do local junk = { tag = 0 } end");
    }

    void finishCycle()
    {
        for (int i = 0; i < 1000000 && L->global->gcstate != GCSpause; ++i)
            lua_gc(L, LUA_GCSTEP, 64);

        REQUIRE(L->global->gcstate == GCSpause);
    }

    // every collectable value `t' holds is a live object the cycle that just ended kept
    void requireLiveEntries(LuaTable* t)
    {
        for (int i = 0; i < t->sizearray; ++i)
        {
            const TValue* v = &t->array[i];
            if (iscollectable(v))
                REQUIRE(gcvalue(v)->gch.tt == ttype(v));
        }

        if (t->node == &luaH_dummynode)
            return;

        for (int i = 0; i < sizenode(t); ++i)
        {
            LuaNode* n = gnode(t, i);
            if (ttisnil(gval(n)))
                continue;
            if (iscollectable(gval(n)))
                REQUIRE(gcvalue(gval(n))->gch.tt == ttype(gval(n)));
        }
    }
};

} // namespace

TEST_SUITE_BEGIN("GcTableSlices");

TEST_CASE_FIXTURE(SlicesFixture, "a_large_table_is_traversed_in_slices")
{
    run("big = table.create(4096) for i = 1, 4096 do big[i] = { tag = i } end");
    LuaTable* big = global("big");

    stepInto(big);
    CHECK(L->global->gcpartialpos < big->sizearray);
    CHECK(isblack(obj2gco(big)));

    int before = L->global->gcpartialpos;
    lua_gc(L, LUA_GCSTEP, 1);
    CHECK((L->global->gcpartial != big || L->global->gcpartialpos < before));

    finishCycle();
    requireLiveEntries(big);
    run("for i = 1, 4096 do assert(big[i].tag == i) end");
}

TEST_CASE_FIXTURE(SlicesFixture, "a_small_table_is_traversed_whole")
{
    run("small = table.create(256) for i = 1, 256 do small[i] = { tag = i } end");
    LuaTable* small = global("small");

    lua_gc(L, LUA_GCCOLLECT, 0);
    for (int i = 0; i < 100000 && L->global->gcstate != GCSpause; ++i)
    {
        lua_gc(L, LUA_GCSTEP, 1);
        CHECK(L->global->gcpartial != small);
    }

    requireLiveEntries(small);
}

TEST_CASE_FIXTURE(SlicesFixture, "a_sort_moving_untraversed_entries_into_traversed_slots_keeps_them")
{
    // the slots are traversed from the last one down, so reversing the array moves entries not yet marked into slots already marked
    run("big = table.create(4096) for i = 1, 4096 do big[i] = { tag = i } end");
    LuaTable* big = global("big");

    stepInto(big);
    runStopped("table.sort(big, function(a, b) return a.tag > b.tag end)");
    CHECK(L->global->gcpartial != big);

    finishCycle();
    requireLiveEntries(big);
    collectAndReuse();
    run("for i = 1, 4096 do assert(big[i].tag == 4097 - i) end");
}

TEST_CASE_FIXTURE(SlicesFixture, "a_resize_while_traversed_in_slices_keeps_every_entry")
{
    // growing the hash part moves every array slot up the traversal order, past the slots already traversed; every key and value
    // in the hash part is a number, which no barrier sees
    run("big = {} for i = 1, 4096 do big[i] = { tag = i } end for i = 1, 600 do big[i + 0.25] = i end");
    LuaTable* big = global("big");

    stepInto(big);
    int hashBefore = sizenode(big);
    runStopped("for i = 1, 3000 do big[i + 0.5] = i end");
    REQUIRE(sizenode(big) > hashBefore);
    CHECK(L->global->gcpartial != big);

    finishCycle();
    requireLiveEntries(big);
    collectAndReuse();
    run("for i = 1, 4096 do assert(big[i].tag == i) end");
}

TEST_CASE_FIXTURE(SlicesFixture, "a_hash_collision_while_traversed_in_slices_keeps_every_entry")
{
    // a new key whose main position holds a node out of its own main position moves that node into a free slot, which is taken
    // from the top of the hash part, where the traversal starts; the keys and values added are numbers, which no barrier sees
    run("dict = {} for i = 1, 2100 do dict['key' .. i] = { tag = i } end");
    LuaTable* dict = global("dict");

    stepInto(dict);
    int sizeBefore = sizenode(dict);
    runStopped("for i = 1, 500 do dict[i + 0.5] = i end");
    REQUIRE(sizenode(dict) == sizeBefore);
    CHECK(L->global->gcpartial != dict);

    finishCycle();
    requireLiveEntries(dict);
    collectAndReuse();
    run("for i = 1, 2100 do assert(dict['key' .. i].tag == i) end");
}

TEST_CASE_FIXTURE(SlicesFixture, "a_store_into_traversed_slots_keeps_the_stored_value")
{
    run("big = table.create(4096) for i = 1, 4096 do big[i] = { tag = i } end");
    LuaTable* big = global("big");

    stepInto(big);
    runStopped("big[4096] = { tag = 'stored' }");
    CHECK(L->global->gcpartial != big);

    finishCycle();
    requireLiveEntries(big);
    collectAndReuse();
    run("assert(big[4096].tag == 'stored')");
}

TEST_SUITE_END();
