#include "audio.h"

#include <xmp.h>

#include <algorithm>
#include <cstdio>
#include <cstring>

bool Audio::init() {
    if (!SDL_WasInit(SDL_INIT_AUDIO)) return false;
    SDL_AudioSpec want{}, have{};
    want.freq = 48000;
    want.format = AUDIO_S16SYS;
    want.channels = 2;
    want.samples = 1024;
    want.callback = &Audio::callback;
    want.userdata = this;
    dev_ = SDL_OpenAudioDevice(nullptr, 0, &want, &have, SDL_AUDIO_ALLOW_FREQUENCY_CHANGE);
    if (!dev_) {
        std::fprintf(stderr, "audio: %s (running silent)\n", SDL_GetError());
        return false;
    }
    rate_ = have.freq;
    xmp_ = xmp_create_context();
    SDL_PauseAudioDevice(dev_, 0);
    return true;
}

void Audio::shutdown() {
    if (dev_) SDL_CloseAudioDevice(dev_);
    dev_ = 0;
    if (xmp_) {
        stopMusic();
        xmp_free_context(static_cast<xmp_context>(xmp_));
        xmp_ = nullptr;
    }
}

void Audio::setSounds(omf::SoundsFile sf) {
    std::lock_guard<std::mutex> g(m_);
    for (auto& v : voices_) v.active = false;
    sounds_ = std::move(sf);
}

int Audio::play(int id, const Opts& o) {
    std::lock_guard<std::mutex> g(m_);
    if (id < 0 || id >= int(sounds_.sounds.size()) || sounds_.sounds[size_t(id)].pcm.empty()) return -1;
    int ch = o.channel;
    if (ch < 0 || ch >= kChannels) {
        ch = -1;
        for (int i = 0; i < kChannels; ++i)
            if (!voices_[size_t(i)].active) { ch = i; break; }
        if (ch < 0) {   // all busy: take the lowest priority one
            int best = 0;
            for (int i = 1; i < kChannels; ++i)
                if (voices_[size_t(i)].prio < voices_[size_t(best)].prio) best = i;
            if (voices_[size_t(best)].prio > o.priority) return -1;
            ch = best;
        }
    }
    const auto& s = sounds_.sounds[size_t(id)];
    // OpenOMF's pitched_samplerate: sf raises the rate 3% a step, lowers it 2%.
    int p = std::max(o.pitch, -20);
    int r = s.rate();
    if (p > 0) r += r * p * 3 / 100;
    else if (p < 0) r += r * p * 2 / 100;
    Voice& v = voices_[size_t(ch)];
    v.s = &s;
    v.pos = 0;
    v.step = double(r) / rate_;
    v.vol = std::clamp(o.volume, 0, 127);
    v.pan = std::clamp(o.pan, -100, 100);
    v.panEnd = std::clamp(o.panEnd, -100, 100);
    v.sweep = o.sweep;
    v.prio = o.priority;
    v.active = true;
    return ch;
}

void Audio::stop(int channel) {
    std::lock_guard<std::mutex> g(m_);
    if (channel >= 0 && channel < kChannels) voices_[size_t(channel)].active = false;
}

void Audio::stopAll() {
    std::lock_guard<std::mutex> g(m_);
    for (auto& v : voices_) v.active = false;
}

bool Audio::playMusic(const omf::Bytes& module, bool loop) {
    if (!xmp_) return false;
    std::lock_guard<std::mutex> g(m_);
    auto ctx = static_cast<xmp_context>(xmp_);
    if (musicOn_) {
        xmp_end_player(ctx);
        xmp_release_module(ctx);
        musicOn_ = false;
    }
    if (xmp_load_module_from_memory(ctx, module.data(), long(module.size())) != 0) return false;
    if (xmp_start_player(ctx, rate_, 0) != 0) {
        xmp_release_module(ctx);
        return false;
    }
    xmp_set_player(ctx, XMP_PLAYER_INTERP, XMP_INTERP_SPLINE);
    musicLoop_ = loop;
    musicOn_ = true;
    return true;
}

void Audio::stopMusic() {
    if (!xmp_) return;
    std::lock_guard<std::mutex> g(m_);
    if (!musicOn_) return;
    auto ctx = static_cast<xmp_context>(xmp_);
    xmp_end_player(ctx);
    xmp_release_module(ctx);
    musicOn_ = false;
}

bool Audio::musicPlaying() const {
    std::lock_guard<std::mutex> g(m_);
    return musicOn_;
}

void Audio::setMusicVolume(int v) { musicVol_ = std::clamp(v, 0, 100); }
void Audio::setSoundVolume(int v) { soundVol_ = std::clamp(v, 0, 100); }

void Audio::callback(void* self, Uint8* stream, int len) {
    static_cast<Audio*>(self)->mix(reinterpret_cast<int16_t*>(stream), len / 4);
}

void Audio::mix(int16_t* out, int frames) {
    std::lock_guard<std::mutex> g(m_);
    std::vector<int32_t> acc(size_t(frames) * 2, 0);
    if (musicOn_) {
        musicBuf_.resize(size_t(frames) * 2);
        auto ctx = static_cast<xmp_context>(xmp_);
        int r = xmp_play_buffer(ctx, musicBuf_.data(), frames * 4, musicLoop_ ? 0 : 1);
        if (r != 0) {
            musicOn_ = false;
            xmp_end_player(ctx);
            xmp_release_module(ctx);
        } else {
            for (size_t i = 0; i < acc.size(); ++i) acc[i] += musicBuf_[i] * musicVol_ / 100;
        }
    }
    for (auto& v : voices_) {
        if (!v.active || !v.s) continue;
        const auto& pcm = v.s->pcm;
        const double len = double(pcm.size());
        for (int f = 0; f < frames; ++f) {
            if (v.pos >= len) { v.active = false; break; }
            int pan = v.pan;
            if (v.sweep) pan = int(v.pan + (v.panEnd - v.pan) * (v.pos / len));
            size_t i = size_t(v.pos);
            int smp = (int(pcm[i]) - 128) << 8;
            int vol = v.vol * soundVol_ / 100;
            int l = smp * vol / 127 * (100 - std::max(pan, 0)) / 100;
            int rr = smp * vol / 127 * (100 + std::min(pan, 0)) / 100;
            acc[size_t(f) * 2] += l;
            acc[size_t(f) * 2 + 1] += rr;
            v.pos += v.step;
        }
    }
    for (size_t i = 0; i < acc.size(); ++i) out[i] = int16_t(std::clamp(acc[i], -32768, 32767));
}
