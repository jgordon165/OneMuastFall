// Sound: the effects from SOUNDS.DAT (8-bit PCM, mixed on a few channels
// with volume, panning and pitch as the scripts ask) and the music, the
// game's PSM modules played by libxmp. Everything is optional: with no
// sound device the game runs silent.
#pragma once
#include <SDL.h>

#include <array>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

#include "formats/sounds.h"

class Audio {
public:
    static constexpr int kChannels = 8;

    bool init();
    void shutdown();
    bool available() const { return dev_ != 0; }

    void setSounds(omf::SoundsFile sf);
    int soundCount() const { return int(sounds_.sounds.size()); }

    struct Opts {
        int volume = 127;     // 0..127
        int pan = 0;          // -100..100
        int panEnd = 0;
        bool sweep = false;
        int pitch = 0;        // the scripts' sf value
        int channel = -1;     // -1 = any free one
        int priority = 10;
    };
    // Returns the channel used, or -1.
    int play(int id, const Opts& o);
    void stop(int channel);
    void stopAll();

    // PSM (or any module libxmp knows), from memory. loop: repeat at the end.
    bool playMusic(const omf::Bytes& module, bool loop);
    void stopMusic();
    bool musicPlaying() const;
    void setMusicVolume(int v);    // 0..100
    void setSoundVolume(int v);    // 0..100

private:
    static void callback(void* self, Uint8* stream, int len);
    void mix(int16_t* out, int frames);

    struct Voice {
        const omf::SoundSample* s = nullptr;
        double pos = 0, step = 0;
        int vol = 127, pan = 0, panEnd = 0, prio = 0;
        bool sweep = false;
        bool active = false;
    };

    SDL_AudioDeviceID dev_ = 0;
    int rate_ = 48000;
    omf::SoundsFile sounds_;
    std::array<Voice, kChannels> voices_{};
    void* xmp_ = nullptr;   // xmp_context
    bool musicOn_ = false, musicLoop_ = true;
    int musicVol_ = 70, soundVol_ = 100;
    std::vector<int16_t> musicBuf_;
    mutable std::mutex m_;
};
