// BK: a scene (intro, menu, arena, cutscene...). A 320x200 background, up to
// 50 animations with chaining info, palettes with remap tables, and the
// table that maps the scripts' sound numbers to SOUNDS.DAT.
#pragma once
#include <array>
#include <map>

#include "formats/animation.h"

namespace omf {

struct BkAnim {
    uint8_t null = 0;
    uint8_t chainHit = 0;
    uint8_t chainNoHit = 0;
    uint8_t repeat = 0;
    uint16_t probability = 0;
    uint8_t hazardDamage = 0;
    std::string footer;
    Animation ani;
};

struct BkFile {
    uint32_t fileId = 0;
    uint8_t unknown = 0;
    Image background;                      // opaque, usually 320x200
    std::map<int, BkAnim> anims;           // by id 0..49
    std::vector<Palette> palettes;
    std::vector<std::array<std::array<uint8_t, 256>, 19>> remaps;  // per palette
    std::array<uint8_t, 30> soundTable{};  // script sound n -> SOUNDS.DAT id+1
};

bool loadBk(const Bytes& data, BkFile& out, std::string* err = nullptr);

}  // namespace omf
