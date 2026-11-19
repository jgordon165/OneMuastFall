// SOUNDS.DAT: every sound effect, 8-bit unsigned mono PCM. Each has a
// Sound Blaster time constant; the rate is 1000000 / (256 - key) Hz.
#pragma once
#include "formats/reader.h"

namespace omf {

struct SoundSample {
    uint8_t freqKey = 0;
    Bytes pcm;              // unsigned 8-bit
    int rate() const { return 1000000 / (256 - freqKey); }
};

struct SoundsFile {
    std::vector<SoundSample> sounds;   // by id (0-based)
};

bool loadSounds(const Bytes& data, SoundsFile& out, std::string* err = nullptr);

}  // namespace omf
