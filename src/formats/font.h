// GRAPHCHR.DAT (8x8, the big font) and CHARSMAL.DAT (6x6, the small one):
// 224 glyphs for characters 32..255, one byte per row, high bit on the left.
#pragma once
#include <array>
#include <vector>

#include "formats/reader.h"

namespace omf {

struct FontFile {
    int size = 0;                                   // 8 or 6
    std::vector<std::array<uint8_t, 8>> glyphs;     // 224 entries, `size` rows used
    bool pixel(int ch, int x, int y) const {
        int g = ch - 32;
        if (g < 0 || g >= int(glyphs.size()) || x < 0 || y < 0 || x >= size || y >= size) return false;
        return (glyphs[size_t(g)][size_t(y)] >> (size - 1 - x)) & 1;
    }
};

bool loadFont(const Bytes& data, int size, FontFile& out, std::string* err = nullptr);

}  // namespace omf
