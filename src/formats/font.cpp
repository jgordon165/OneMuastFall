#include "formats/font.h"

namespace omf {

bool loadFont(const Bytes& data, int size, FontFile& f, std::string* err) {
    if (size < 1 || size > 8 || data.size() < size_t(224 * size)) {
        if (err) *err = "font file too small";
        return false;
    }
    f.size = size;
    f.glyphs.assign(224, {});
    for (int i = 0; i < 224; ++i)
        for (int y = 0; y < size; ++y) f.glyphs[size_t(i)][size_t(y)] = data[size_t(i * size + y)];
    return true;
}

}  // namespace omf
