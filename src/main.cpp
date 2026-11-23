// One Must Fall 2097 port: C++ host. Owns the window, audio device and input,
// and runs the game written in Lua (scripts/). Every asset is read at runtime
// from the player's own copy of the game; nothing from the original is
// compiled in or shipped.
//
// Usage: onemustfall --data <OMF2097 folder> [--scale N] [--scripts <dir>]
//                    [--skip-intro] [--explorer] [--smoke]
//                    [--frames N] [--shot N file.bmp]... [--press N key]...
//                    [--keydown N key] [--keyup N key]
//                    (headless testing: run N frames, save frames, press keys)
#include <SDL.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <utility>
#include <vector>

extern "C" {
#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"
}

#include "engine.h"
#include "lua_api.h"

static bool callLua(lua_State* L, const char* fn, double arg, bool withArg) {
    lua_getglobal(L, "game");
    if (!lua_istable(L, -1)) { lua_pop(L, 1); return true; }
    lua_getfield(L, -1, fn);
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return true; }
    if (withArg) lua_pushnumber(L, arg);
    if (lua_pcall(L, withArg ? 1 : 0, 0, 0) != LUA_OK) {
        std::fprintf(stderr, "lua error in game.%s: %s\n", fn, lua_tostring(L, -1));
        lua_pop(L, 1);
        return false;
    }
    return true;
}

int main(int argc, char** argv) {
    Engine eng;
    std::string scripts;
    int scale = 3;
    long maxFrames = -1;
    bool explorer = false;
    bool smoke = false;
    bool fight = false;
    std::vector<std::pair<long, std::string>> shots;
    std::vector<std::pair<long, std::string>> presses;
    struct KeyEv { long frame; std::string key; bool down; };
    std::vector<KeyEv> keyevs;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() -> std::string { return i + 1 < argc ? argv[++i] : ""; };
        if (a == "--data") eng.dataArg = next();
        else if (a == "--scripts") scripts = next();
        else if (a == "--scale") scale = std::max(1, std::atoi(next().c_str()));
        else if (a == "--frames") maxFrames = std::atol(next().c_str());
        else if (a == "--shot") {
            long f = std::atol(next().c_str());
            shots.emplace_back(f, next());
        } else if (a == "--press") {
            long f = std::atol(next().c_str());
            presses.emplace_back(f, next());
        } else if (a == "--keydown" || a == "--keyup") {
            long f = std::atol(next().c_str());
            keyevs.push_back({f, next(), a == "--keydown"});
        } else if (a == "--screenshot") shots.emplace_back(-1, next());
        else if (a == "--skip-intro") eng.skipIntro = true;
        else if (a == "--explorer") explorer = true;
        else if (a == "--fight") fight = true;
        else if (a == "--smoke") { smoke = true; if (maxFrames < 0) maxFrames = 1; }
        else if (a == "--help" || a == "-h") {
            std::printf(
                "onemustfall --data <your One Must Fall 2097 folder> [--scale N]\n"
                "            [--skip-intro] [--explorer]\n"
                "  --skip-intro  straight to the main menu\n"
                "  --explorer    open the asset explorer (also F12 in the game)\n");
            return 0;
        }
    }
    if (scripts.empty()) {
        char* base = SDL_GetBasePath();
        scripts = (base ? std::string(base) : std::string("./")) + "scripts";
        SDL_free(base);
    }
    if (eng.dataArg.empty()) eng.dataArg = "data";
    eng.data.mount(eng.dataArg);

    const bool headless = maxFrames >= 0;
    if (headless) SDL_setenv("SDL_AUDIODRIVER", "dummy", 1);
    if (SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) std::fprintf(stderr, "audio unavailable: %s\n", SDL_GetError());
    if (SDL_Init((headless ? 0 : SDL_INIT_VIDEO) | SDL_INIT_EVENTS | SDL_INIT_GAMECONTROLLER) != 0) {
        std::fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return 1;
    }
    if (!eng.video.init(scale, headless)) return 1;
    eng.audio.init();

    lua_State* L = luaL_newstate();
    luaL_openlibs(L);
    registerLuaApi(L, eng);
    lua_getglobal(L, "sys");
    lua_pushboolean(L, explorer);
    lua_setfield(L, -2, "explorer");
    lua_pushboolean(L, smoke);
    lua_setfield(L, -2, "smoke");
    lua_pushboolean(L, fight);
    lua_setfield(L, -2, "fight");
    lua_pop(L, 1);
    lua_getglobal(L, "package");
    lua_pushstring(L, (scripts + "/?.lua;" + scripts + "/?/init.lua").c_str());
    lua_setfield(L, -2, "path");
    lua_pop(L, 1);
    const std::string mainLua = scripts + "/main.lua";
    if (luaL_dofile(L, mainLua.c_str()) != LUA_OK) {
        std::fprintf(stderr, "failed to load %s: %s\n", mainLua.c_str(), lua_tostring(L, -1));
        return 1;
    }
    if (!callLua(L, "init", 0, false)) return 1;

    Uint64 last = SDL_GetPerformanceCounter();
    const double freq = double(SDL_GetPerformanceFrequency());
    long frame = 0;
    while (!eng.quit) {
        eng.input.beginFrame();
        for (auto& [f, key] : presses)
            if (f == frame) {
                SDL_Event k{};
                k.type = SDL_KEYDOWN;
                k.key.keysym.sym = SDL_GetKeyFromName(key.c_str());
                eng.input.handle(k);
                k.type = SDL_KEYUP;
                eng.input.handle(k);
            }
        for (auto& k : keyevs)
            if (k.frame == frame) {
                SDL_Event e{};
                e.type = k.down ? SDL_KEYDOWN : SDL_KEYUP;
                e.key.keysym.sym = SDL_GetKeyFromName(k.key.c_str());
                eng.input.handle(e);
            }
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_QUIT) eng.quit = true;
            if (ev.type == SDL_KEYDOWN && !ev.key.repeat &&
                (ev.key.keysym.sym == SDLK_F11 ||
                 (ev.key.keysym.sym == SDLK_RETURN && (ev.key.keysym.mod & KMOD_ALT)))) {
                eng.video.toggleFullscreen();
                continue;
            }
            eng.input.handle(ev);
        }
        double dt;
        if (headless) {
            dt = 1000.0 / 60.0;
        } else {
            Uint64 now = SDL_GetPerformanceCounter();
            dt = std::min(100.0, double(now - last) * 1000.0 / freq);
            last = now;
        }
        if (!callLua(L, "update", dt, true)) break;
        if (!callLua(L, "draw", 0, false)) break;
        eng.video.present();
        ++frame;
        for (auto& [f, path] : shots)
            if (f == frame) eng.video.screenshot(path);
        if (headless && frame >= maxFrames) break;
        if (!headless && !eng.video.window()) break;
    }
    for (auto& [f, path] : shots)
        if (f < 0) eng.video.screenshot(path);
    int rc = 0;
    if (smoke) {   // --smoke: exit status says whether every animation ran
        lua_getglobal(L, "sys");
        lua_getfield(L, -1, "smoke_failed");
        rc = lua_toboolean(L, -1) ? 1 : 0;
        lua_pop(L, 2);
    }
    callLua(L, "shutdown", 0, false);
    lua_close(L);
    eng.audio.shutdown();
    eng.video.shutdown();
    SDL_Quit();
    return rc;
}
