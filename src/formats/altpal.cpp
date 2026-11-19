#include "formats/altpal.h"

namespace omf {

bool loadAltPals(const Bytes& data, AltPalFile& ap, std::string* err) {
    if (data.size() < 11 * 768) {
        if (err) *err = "ALTPALS.DAT too small";
        return false;
    }
    Reader r(data);
    ap.palettes.resize(11);
    for (auto& p : ap.palettes) readPalette(r, p);
    return r.ok();
}

}  // namespace omf
