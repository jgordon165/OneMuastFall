#include "formats/animation.h"

#include <map>

namespace omf {

namespace {
constexpr uint16_t kMaxCoords = 256;
constexpr uint16_t kMaxScript = 1024;
constexpr uint8_t kMaxExtra = 10;
constexpr uint16_t kMaxExtraLen = 512;

int sign10(unsigned v) { return int((v & 0x3FF) ^ 0x200) - 0x200; }
}  // namespace

bool readAnimation(Reader& r, Animation& a) {
    a.startX = r.s16();
    a.startY = r.s16();
    a.unknown = r.u32();
    uint16_t coordCount = r.u16();
    uint8_t spriteCount = r.u8();
    if (coordCount > kMaxCoords) return false;
    a.coords.resize(coordCount);
    for (auto& c : a.coords) {
        uint32_t t = r.u32();
        unsigned lo = t & 0xFFFF, hi = t >> 16;
        c.x = sign10(lo);
        c.extra = int(lo >> 10);
        c.y = sign10(hi);
        c.frame = int(hi >> 10);
    }
    if (!r.terminatedStr(a.script, kMaxScript)) return false;
    uint8_t extra = r.u8();
    if (extra > kMaxExtra) return false;
    a.extraStrings.resize(extra);
    for (auto& s : a.extraStrings)
        if (!r.terminatedStr(s, kMaxExtraLen)) return false;
    a.sprites.resize(spriteCount);
    for (auto& s : a.sprites)
        if (!readSprite(r, s)) return false;
    return r.ok();
}

void resolveMissingSprites(std::vector<Animation*>& anims) {
    std::map<int, const Bytes*> table;
    for (Animation* a : anims)
        for (Sprite& s : a->sprites) {
            if (s.missing) {
                auto it = table.find(s.index);
                if (it != table.end()) s.rle = *it->second;
            } else {
                table[s.index] = &s.rle;
            }
        }
}

}  // namespace omf
