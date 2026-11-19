#include "formats/pic.h"

namespace omf {

bool loadPic(const Bytes& data, PicFile& pic, std::string* err) {
    auto fail = [&](const char* m) { if (err) *err = m; return false; };
    if (data.size() < 200) return fail("PIC too small");
    Reader r(data);
    int32_t count = r.s32();
    if (count < 0 || count >= 256) return fail("bad PIC photo count");
    r.seek(200);
    std::vector<uint32_t> offs(static_cast<size_t>(count));
    for (auto& o : offs) o = r.u32();
    for (uint32_t o : offs) {
        r.seek(o);
        PicPhoto p;
        p.isPlayer = r.u8() != 0;
        p.sex = r.u16();
        readPalette(r, p.pal, 0, 48);
        p.hasPhoto = r.u8() != 0;
        if (!readSprite(r, p.sprite)) return fail("bad PIC sprite");
        p.sprite.w++;
        p.sprite.h++;
        pic.photos.push_back(std::move(p));
    }
    return r.ok();
}

}  // namespace omf
