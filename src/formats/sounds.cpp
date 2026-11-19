#include "formats/sounds.h"

namespace omf {

bool loadSounds(const Bytes& data, SoundsFile& sf, std::string* err) {
    auto fail = [&](const char* m) { if (err) *err = m; return false; };
    Reader r(data);
    if (r.u32() != 0) return fail("not a SOUNDS.DAT");
    uint32_t header = r.u32();
    if (header < 8 || header > data.size()) return fail("bad SOUNDS.DAT header");
    int blocks = int(header / 4) - 2;
    r.skip(size_t(blocks) * 4);   // block offsets; the blocks follow in order
    sf.sounds.resize(size_t(blocks) + 1);
    for (auto& s : sf.sounds) {
        uint16_t len = r.u16();
        if (len) {
            s.freqKey = r.u8();
            s.pcm = r.bytes(len);
        }
    }
    return r.ok() || fail("SOUNDS.DAT truncated");
}

}  // namespace omf
