// Everything the Lua side reaches through the host.
#pragma once
#include <string>

#include "audio.h"
#include "input.h"
#include "vfs.h"
#include "video.h"

struct Engine {
    Vfs data;
    Video video;
    Audio audio;
    Input input;
    std::string dataArg;
    bool quit = false;
    bool skipIntro = false;
};
