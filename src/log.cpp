#include "log.h"

#include <SDL.h>

#include <cstdio>

#ifdef OMF_XENON_LAYOUT
extern "C" {
#include "xenon_platform.h"
}
#endif

void omfLog(const std::string& line) {
    std::fprintf(stderr, "%s\n", line.c_str());
#if defined(OMF_XENON_LAYOUT) && defined(__XSDK__)
    // The .xex: xsdk keeps its own log open as onemustfall.log (named after
    // the title) beside onemustfall.xex; our lines go into it.
    xp_log(line.c_str());
#elif defined(OMF_XENON_LAYOUT)
    // XeLL and the stand-in: onemustfall.log in the port's folder.
    static std::string path;
    if (path.empty()) {
        char* b = SDL_GetBasePath();
        path = std::string(b ? b : "") + "onemustfall.log";
        SDL_free(b);
        if (FILE* f = std::fopen(path.c_str(), "w")) std::fclose(f);   // a new log each run
    }
    if (FILE* f = std::fopen(path.c_str(), "a")) {
        std::fprintf(f, "%s\n", line.c_str());
        std::fclose(f);
    }
#endif
}
