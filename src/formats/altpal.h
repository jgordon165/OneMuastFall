// ALTPALS.DAT: 11 full palettes (6-bit), used for HAR colour schemes.
#pragma once
#include "formats/sprite.h"

namespace omf {

struct AltPalFile {
    std::vector<Palette> palettes;
};

bool loadAltPals(const Bytes& data, AltPalFile& out, std::string* err = nullptr);

}  // namespace omf
