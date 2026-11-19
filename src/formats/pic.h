// PIC: pilot photos (PLAYERS.PIC, and the tournament ones). Each photo has a
// 48-colour palette (indices 0..47) and one sprite.
#pragma once
#include "formats/sprite.h"

namespace omf {

struct PicPhoto {
    bool isPlayer = false;
    uint16_t sex = 0;
    Palette pal;       // only 0..47 set
    bool hasPhoto = false;
    Sprite sprite;     // w/h already +1 (the file stores size-1)
};

struct PicFile {
    std::vector<PicPhoto> photos;
};

bool loadPic(const Bytes& data, PicFile& out, std::string* err = nullptr);

}  // namespace omf
