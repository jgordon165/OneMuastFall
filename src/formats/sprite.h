// VGA palettes, 8-bit images and the RLE sprites every OMF:2097 animation is
// made of. See docs/formats.md.
#pragma once
#include <array>
#include <cstdint>
#include <vector>

#include "formats/reader.h"

namespace omf {

// 256 colours, 8 bits per channel (the files store 6-bit VGA DAC values).
struct Palette {
    std::array<uint8_t, 256 * 3> rgb{};
};

// The 6-bit DAC value widened the way OpenOMF does it (c<<2 | c>>4), so
// 63 becomes 255.
inline uint8_t dac6to8(uint8_t c) { return uint8_t(((c & 0x3F) << 2) | ((c & 0x30) >> 4)); }

// Reads `count` colours starting at `first` (3 bytes each, 6-bit).
void readPalette(Reader& r, Palette& pal, int first = 0, int count = 256);

// One indexed image. Index 0 is transparent when it's drawn as a sprite.
struct Image {
    int w = 0, h = 0;
    std::vector<uint8_t> px;
};

struct Sprite {
    int16_t x = 0, y = 0;        // offset from the object's position
    uint16_t w = 0, h = 0;
    uint8_t index = 0;           // shared-sprite id within the file
    bool missing = false;        // data lives in an earlier sprite with the same index
    Bytes rle;                   // encoded data (empty when missing)
};

bool readSprite(Reader& r, Sprite& s);

// Decodes the sprite RLE: a stream of 16-bit words, low 2 bits the opcode:
//   0 = set x, 2 = set y, 1 = copy (word>>2) bytes from the stream at (x,y)
//   then x=0, 3 = end.
Image decodeSprite(const Sprite& s);
// Same, from raw RLE and a size (used by PIC photos, whose size is off by one).
Image decodeSpriteRle(const Bytes& rle, int w, int h);

}  // namespace omf
