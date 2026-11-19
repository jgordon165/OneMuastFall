// Runs the Lua tests (tests/lua/main.lua) against scripts/, with no engine:
// only the pure-Lua modules (the animation string parser...) are tested here.
#include <cstdio>
#include <string>

extern "C" {
#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"
}

int main(int argc, char** argv) {
    if (argc < 3) {
        std::fprintf(stderr, "usage: omf_luatest <scripts dir> <test.lua>\n");
        return 2;
    }
    lua_State* L = luaL_newstate();
    luaL_openlibs(L);
    std::string dir = argv[1];
    lua_getglobal(L, "package");
    lua_pushstring(L, (dir + "/?.lua;" + dir + "/?/init.lua").c_str());
    lua_setfield(L, -2, "path");
    lua_pop(L, 1);
    int rc = 0;
    if (luaL_dofile(L, argv[2]) != LUA_OK) {
        std::fprintf(stderr, "%s\n", lua_tostring(L, -1));
        rc = 1;
    }
    lua_close(L);
    return rc;
}
