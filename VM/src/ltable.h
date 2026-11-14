// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
#pragma once

#include "lobject.h"

#define gnode(t, i) (&(t)->node[i])
#define gkey(n) (&(n)->key)
#define gval(n) (&(n)->val)
#define gnext(n) ((n)->key.next)

#define gval2slot(t, v) int(cast_to(LuaNode*, static_cast<const TValue*>(v)) - t->node)

// reset cache of absent metamethods, cache is updated in luaT_gettm
#define invalidateTMcache(t) t->tmcache = 0

LUAI_FUNC const TValue* luaH_getnum(LuaTable* t, int key);
LUAI_FUNC TValue* luaH_setnum(lua_State* L, LuaTable* t, int key);
LUAI_FUNC const TValue* luaH_getstr(LuaTable* t, TString* key);
LUAI_FUNC TValue* luaH_setstr(lua_State* L, LuaTable* t, TString* key);
LUAI_FUNC const TValue* luaH_getp(LuaTable* t, void* key, int tag);
LUAI_FUNC TValue* luaH_setp(lua_State* L, LuaTable* t, void* key, int tag);
LUAI_FUNC const TValue* luaH_get(LuaTable* t, const TValue* key);
LUAI_FUNC TValue* luaH_set(lua_State* L, LuaTable* t, const TValue* key);
LUAI_FUNC TValue* luaH_newkey(lua_State* L, LuaTable* t, const TValue* key);
LUAI_FUNC LuaTable* luaH_new(lua_State* L, int narray, int lnhash);
LUAI_FUNC void luaH_resizearray(lua_State* L, LuaTable* t, int nasize);
LUAI_FUNC void luaH_resizehash(lua_State* L, LuaTable* t, int nhsize);
LUAI_FUNC void luaH_free(lua_State* L, LuaTable* t, struct lua_Page* page);
LUAI_FUNC int luaH_next(lua_State* L, LuaTable* t, StkId key);
LUAI_FUNC int luaH_rawfind(LuaTable* t, int startpos, StkId value);
LUAI_FUNC int luaH_getn(LuaTable* t);
LUAI_FUNC LuaTable* luaH_clone(lua_State* L, LuaTable* tt);
LUAI_FUNC void luaH_clear(LuaTable* tt);
LUAI_FUNC void luaH_setreadonly(lua_State* L, LuaTable* t, bool readonly);
LUAI_FUNC int luaH_getreadonly(LuaTable* t);

// A watched table is a table whose `readonly` byte holds WATCHED_TABLE_FLAG and nothing else: it is neither frozen nor
// foreign and holds no metamethod cache. The byte is nonzero, so every write path leaves its fast path for the one that
// checks the byte, and there the first write to a watched table since it was watched calls luaH_watchedwrite before it
// writes. That clears the mark, so every later write takes the fast path again, and enters the table in the watch list
// the host named with lua_setwatchlist. The host learns which of the tables it watches were written without reading
// any of them.
#define WATCHED_TABLE_FLAG 8
#define iswatchedtable(t) ((t)->readonly == WATCHED_TABLE_FLAG)

LUAI_FUNC void luaH_watchedwrite(lua_State* L, LuaTable* t);

// A guarded table is a table whose `readonly` byte holds GUARDED_TABLE_FLAG and nothing else: it is neither frozen,
// foreign nor watched and holds no metamethod cache. The byte is nonzero, so every write path leaves its fast path for
// the one that checks the byte, and there every write to a guarded table calls luaH_guardedwrite before it writes. That
// asks the host's `guardedwrite` callback whether the code running on L writes the table: the write goes ahead when the
// callback answers NULL, and raises the error the callback names otherwise. The mark stays, so every later write asks
// again. A table with no `guardedwrite` callback set takes every write.
#define GUARDED_TABLE_FLAG 16
#define isguardedtable(t) ((t)->readonly == GUARDED_TABLE_FLAG)
// a table whose byte refuses a write outright or hands it to the foreign host: frozen, or foreign
#define iswritelocked(t) ((t)->readonly != 0 && !isguardedtable(t))

LUAI_FUNC void luaH_guardedwrite(lua_State* L, LuaTable* t);
LUAI_FUNC const TValue* luaH_getwatchlist(lua_State* L);
LUAI_FUNC void* luaH_watchlistkey();

#define luaH_setslot(L, t, slot, key) (invalidateTMcache(t), (slot == luaO_nilobject ? luaH_newkey(L, t, key) : cast_to(TValue*, slot)))

extern const LuaNode luaH_dummynode;
