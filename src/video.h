// The original's screen: a 320x200 8-bit framebuffer and a 256-colour VGA
// palette. Lua draws into it (backgrounds, sprites, text); each frame the
// host turns it into RGB through the palette and shows it at 4:3, the shape
// a DOS monitor gave mode 13h.
#pragma once
#include <SDL.h>

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "formats/font.h"
#include "formats/sprite.h"

class Video {
public:
    static constexpr int W = 320, H = 200;

    bool init(int scale, bool headless);
    void shutdown();

    // ---- drawing (indices) ----
    void clear(uint8_t c);
    void pset(int x, int y, uint8_t c);
    uint8_t pget(int x, int y) const;
    void fill(int x, int y, int w, int h, uint8_t c);
    void rect(int x, int y, int w, int h, uint8_t c);
    void line(int x0, int y0, int x1, int y1, uint8_t c);
    // Index 0 is transparent unless `opaque`. `remap`, when given, maps the
    // pixel underneath instead of drawing the sprite's own colour (the
    // original's glow / shadow tricks use the BK remap tables this way).
    void blit(const omf::Image& img, int x, int y, bool flipX, bool flipY, bool opaque,
              const uint8_t* remap = nullptr);
    // Sprite drawn as a solid colour (shadows, flashes).
    void blitColor(const omf::Image& img, int x, int y, bool flipX, bool flipY, uint8_t c);
    // Every pixel in the box goes through a remap table (the menus darken
    // what's under them with the BK's table 4).
    void remapRect(int x, int y, int w, int h, const uint8_t* remap, int rounds = 1);
    void clip(int x, int y, int w, int h);
    void unclip();

    // ---- text: the game's own fonts (GRAPHCHR 8x8, CHARSMAL 6x6) ----
    void setFont(int which, const omf::FontFile& f);   // 0 = big, 1 = small
    bool hasFont(int which) const { return fonts_[which & 1].size > 0; }
    int text(const std::string& s, int x, int y, uint8_t c, int font, int shadow = -1);
    int textWidth(const std::string& s, int font) const;

    // ---- palette ----
    // The base palette is what the scene loaded; the working palette is
    // rebuilt from it every frame (resetPalette) and then modified by the
    // scripts' palette tricks (mix/tint) before it's shown.
    void setBase(int first, int count, const uint8_t* rgb);
    void setBaseColor(int i, uint8_t r, uint8_t g, uint8_t b);
    void resetPalette() { work_ = base_; }
    void mixRange(int ref, int start, int end, int step);    // toward colour `ref`
    void tintRange(int ref, int start, int end, int step);
    void darken(int step);                                    // 0..255, whole palette
    std::array<uint8_t, 768>& work() { return work_; }
    const std::array<uint8_t, 768>& base() const { return base_; }

    // ---- output ----
    void present();
    bool screenshot(const std::string& path) const;
    void toggleFullscreen();
    bool headless() const { return headless_; }
    SDL_Window* window() const { return window_; }

private:
    std::vector<uint8_t> fb_ = std::vector<uint8_t>(W * H, 0);
    std::array<uint8_t, 768> base_{}, work_{};
    omf::FontFile fonts_[2];
    int cx0_ = 0, cy0_ = 0, cx1_ = W, cy1_ = H;
    SDL_Window* window_ = nullptr;
    SDL_Renderer* renderer_ = nullptr;
    SDL_Texture* texture_ = nullptr;
    std::vector<uint32_t> rgba_ = std::vector<uint32_t>(W * H, 0);
    bool headless_ = false;
    bool fullscreen_ = false;
};
