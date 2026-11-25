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
#include "log.h"
#include "lua_api.h"

#ifdef OMF_XENON_LAYOUT
extern "C" {
#include "xenon_platform.h"
}
#endif

static std::string g_lastError;

static bool callLua(lua_State* L, const char* fn, double arg, bool withArg) {
    lua_getglobal(L, "game");
    if (!lua_istable(L, -1)) { lua_pop(L, 1); return true; }
    lua_getfield(L, -1, fn);
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return true; }
    if (withArg) lua_pushnumber(L, arg);
    if (lua_pcall(L, withArg ? 1 : 0, 0, 0) != LUA_OK) {
        std::string msg = std::string("lua error in game.") + fn + ": " + lua_tostring(L, -1);
        lua_pop(L, 1);
        omfLog(msg);
        g_lastError = msg;
        return false;
    }
    return true;
}

// After a script error: show it on screen (scenes/error.lua) instead of
// quitting to nothing, which on a console would be a black screen. Returns
// false if even that fails.
static bool showError(lua_State* L, const std::string& msg) {
    lua_getglobal(L, "game");
    if (!lua_istable(L, -1)) { lua_pop(L, 1); return false; }
    lua_getfield(L, -1, "on_error");
    lua_remove(L, -2);
    if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return false; }
    lua_pushstring(L, msg.c_str());
    if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
        omfLog(std::string("error screen failed: ") + lua_tostring(L, -1));
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
    if (eng.dataArg.empty()) {
#ifdef OMF_XENON_LAYOUT
        // The Xbox 360 starts with no arguments: the game files go in data/
        // in the port's folder (platform/xenon/README-xex.txt).
        char* base = SDL_GetBasePath();
        eng.dataArg = (base ? std::string(base) : std::string("./")) + "data";
        SDL_free(base);
#else
        eng.dataArg = "data";
#endif
    }
    eng.data.mount(eng.dataArg);
    omfLog("OneMuastFall " OMF_VERSION ": data " + eng.dataArg + ", scripts " + scripts);

    const bool headless = maxFrames >= 0;
    if (headless) SDL_setenv("SDL_AUDIODRIVER", "dummy", 1);
    if (SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) omfLog(std::string("audio unavailable: ") + SDL_GetError());
#ifdef OMF_XENON_LAYOUT
    // The Xbox 360's SDL has no threads, so no game-controller subsystem
    // (the pads arrive as keys).
    const Uint32 sdlFlags = SDL_INIT_EVENTS;
#else
    const Uint32 sdlFlags = SDL_INIT_EVENTS | SDL_INIT_GAMECONTROLLER;
#endif
    if (SDL_Init((headless ? 0 : SDL_INIT_VIDEO) | sdlFlags) != 0) {
        omfLog(std::string("SDL_Init: ") + SDL_GetError());
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
        omfLog("failed to load " + mainLua + ": " + lua_tostring(L, -1));
        return 1;
    }
    bool failed = false;
    if (!callLua(L, "init", 0, false)) {
        if (headless || !showError(L, g_lastError)) return 1;
        failed = true;
    }

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
        if (!callLua(L, "update", dt, true) || !callLua(L, "draw", 0, false)) {
            // one chance: the error screen; an error there ends the game
            if (failed || headless) { failed = true; break; }
            failed = true;
            if (!showError(L, g_lastError)) break;
            continue;
        }
        eng.video.present();
        ++frame;
        for (auto& [f, path] : shots)
            if (f == frame) eng.video.screenshot(path);
        if (headless && frame >= maxFrames) break;
        if (!headless && !eng.video.window()) break;
    }
    for (auto& [f, path] : shots)
        if (f < 0) eng.video.screenshot(path);
    int rc = (failed && headless) ? 1 : 0;
    if (smoke) {   // --smoke: exit status says whether every animation ran
        lua_getglobal(L, "sys");
        lua_getfield(L, -1, "smoke_failed");
        rc = lua_toboolean(L, -1) ? 1 : 0;
        lua_pop(L, 2);
    }
#ifdef OMF_XENON_LAYOUT
    // On the Xbox 360 the title ends here and the console goes back to its
    // dashboard (or dashboard.txt's program): a black frame, then the
    // platform stops the sound and ends the title. Not a return from main,
    // whose clean-up would run while the sound feeder is still mixing.
    if (!headless && xp_can_exit()) {
        eng.video.clear(0);
        eng.video.darken(255);
        eng.video.present();
        xp_exit_title(rc);
    }
#endif
    callLua(L, "shutdown", 0, false);
    lua_close(L);
    eng.audio.shutdown();
    eng.video.shutdown();
    SDL_Quit();
    return rc;
}
