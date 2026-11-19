#include "formats/sprite.h"

namespace omf {

void readPalette(Reader& r, Palette& pal, int first, int count) {
    for (int i = first; i < first + count && i < 256; ++i) {
        pal.rgb[i * 3 + 0] = dac6to8(r.u8());
        pal.rgb[i * 3 + 1] = dac6to8(r.u8());
        pal.rgb[i * 3 + 2] = dac6to8(r.u8());
    }
}

bool readSprite(Reader& r, Sprite& s) {
    uint16_t len = r.u16();
    s.x = r.s16();
    s.y = r.s16();
    s.w = r.u16();
    s.h = r.u16();
    s.index = r.u8();
    s.missing = r.u8() != 0;
    if (!s.missing && len) s.rle = r.bytes(len);
    return r.ok();
}

Image decodeSpriteRle(const Bytes& d, int w, int h) {
    Image img;
    if (w <= 0 || h <= 0 || d.empty()) {
        img.w = img.h = 1;
        img.px.assign(1, 0);
        return img;
    }
    img.w = w;
    img.h = h;
    img.px.assign(size_t(w) * h, 0);
    size_t i = 0;
    int x = 0, y = 0;
    const size_t n = d.size();
    while (i + 1 < n) {
        unsigned c = d[i] | (d[i + 1] << 8);
        unsigned op = c & 3, v = c >> 2;
        i += 2;
        switch (op) {
            case 0: x = int(v); break;
            case 2: y = int(v); break;
            case 1:
                while (v > 0 && i < n) {
                    size_t p = size_t(y) * w + x;
                    if (x < w && y < h) img.px[p] = d[i];
                    ++i;
                    ++x;
                    --v;
                }
                x = 0;
                break;
            case 3: return img;
        }
    }
    return img;
}

Image decodeSprite(const Sprite& s) { return decodeSpriteRle(s.rle, s.w, s.h); }

}  // namespace omf
