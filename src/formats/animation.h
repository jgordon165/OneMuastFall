// The animation record shared by BK (scene) and AF (fighter) files: a start
// position, collision points, a frame script (the "animation string", parsed
// in Lua: scripts/core/script.lua), extra strings and the sprites.
#pragma once
#include <string>
#include <vector>

#include "formats/sprite.h"

namespace omf {

struct CollisionCoord {
    int x = 0, y = 0;   // 10-bit signed
    int frame = 0;      // sprite (frame letter) the point belongs to
    int extra = 0;      // the 6 bits next to x, unknown
};

struct Animation {
    int16_t startX = 0, startY = 0;
    uint32_t unknown = 0;
    std::vector<CollisionCoord> coords;
    std::string script;                    // e.g. "s4bps1bpn40A1-B2-C3-..."
    std::vector<std::string> extraStrings;
    std::vector<Sprite> sprites;
};

bool readAnimation(Reader& r, Animation& a);

// Sprites marked `missing` reuse the data of the earlier sprite with the
// same index (anywhere in the file). Call once over every animation of a file.
void resolveMissingSprites(std::vector<Animation*>& anims);

}  // namespace omf
