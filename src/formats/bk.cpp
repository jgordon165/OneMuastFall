#include "formats/bk.h"

namespace omf {

namespace {
constexpr int kMaxAnims = 50;
constexpr int kMaxPalettes = 8;
}

bool loadBk(const Bytes& data, BkFile& bk, std::string* err) {
    auto fail = [&](const char* m) { if (err) *err = m; return false; };
    Reader r(data);
    bk.fileId = r.u32();
    bk.unknown = r.u8();
    uint16_t w = r.u16(), h = r.u16();
    while (true) {
        r.skip(4);                        // offset of the next animation
        uint8_t id = r.u8();
        if (id >= kMaxAnims || !r.ok()) break;
        BkAnim a;
        a.null = r.u8();
        a.chainHit = r.u8();
        a.chainNoHit = r.u8();
        a.repeat = r.u8();
        a.probability = r.u16();
        a.hazardDamage = r.u8();
        if (!r.paddedStr(a.footer, 512)) return fail("bad BK footer string");
        if (!readAnimation(r, a.ani)) return fail("bad BK animation");
        bk.anims[id] = std::move(a);
    }
    if (!r.ok()) return fail("BK truncated in animations");
    bk.background.w = w;
    bk.background.h = h;
    bk.background.px = r.bytes(size_t(w) * h);
    uint8_t pals = r.u8();
    if (pals > kMaxPalettes) return fail("too many BK palettes");
    bk.palettes.resize(pals);
    bk.remaps.resize(pals);
    for (int i = 0; i < pals; ++i) {
        readPalette(r, bk.palettes[i]);
        for (auto& t : bk.remaps[i]) r.bytes(t.data(), 256);
    }
    r.bytes(bk.soundTable.data(), 30);
    if (!r.ok()) return fail("BK truncated");

    std::vector<Animation*> all;
    for (auto& [id, a] : bk.anims) all.push_back(&a.ani);
    resolveMissingSprites(all);
    return true;
}

}  // namespace omf
