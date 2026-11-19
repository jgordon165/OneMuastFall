#pragma once
struct lua_State;
struct Engine;

// Registers sys, fs, omf, gfx, audio and input (see docs/lua-api.md).
void registerLuaApi(lua_State* L, Engine& e);
