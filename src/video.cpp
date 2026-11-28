#include "video.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>

#include "upscale.h"

bool Video::init(int scale, bool headless) {
    headless_ = headless;
    if (headless) return true;
    window_ = SDL_CreateWindow("One Must Fall 2097", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 320 * scale,
                               240 * scale, SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
    if (!window_) {
        std::fprintf(stderr, "SDL_CreateWindow: %s\n", SDL_GetError());
        return false;
    }
    renderer_ = SDL_CreateRenderer(window_, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!renderer_) renderer_ = SDL_CreateRenderer(window_, -1, 0);
    if (!renderer_) {
        std::fprintf(stderr, "SDL_CreateRenderer: %s\n", SDL_GetError());
        return false;
    }
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "0");
    texture_ = SDL_CreateTexture(renderer_, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, W, H);
    return texture_ != nullptr;
}

void Video::shutdown() {
    if (texture_) SDL_DestroyTexture(texture_);
    if (renderer_) SDL_DestroyRenderer(renderer_);
    if (window_) SDL_DestroyWindow(window_);
    texture_ = nullptr;
    renderer_ = nullptr;
    window_ = nullptr;
}

void Video::clear(uint8_t c) {
    std::fill(fb_.begin(), fb_.end(), c);
    std::fill(mask_.begin(), mask_.end(), 0);
}

void Video::pset(int x, int y, uint8_t c) {
    if (x >= cx0_ && y >= cy0_ && x < cx1_ && y < cy1_) {
        fb_[size_t(y) * W + x] = c;
        mask_[size_t(y) * W + x] = 0;
    }
}

uint8_t Video::pget(int x, int y) const {
    if (x < 0 || y < 0 || x >= W || y >= H) return 0;
    return fb_[size_t(y) * W + x];
}

void Video::fill(int x, int y, int w, int h, uint8_t c) {
    int x0 = std::max(x, cx0_), y0 = std::max(y, cy0_);
    int x1 = std::min(x + w, cx1_), y1 = std::min(y + h, cy1_);
    for (int yy = y0; yy < y1; ++yy) {
        std::fill(fb_.begin() + yy * W + x0, fb_.begin() + yy * W + std::max(x0, x1), c);
        std::fill(mask_.begin() + yy * W + x0, mask_.begin() + yy * W + std::max(x0, x1), 0);
    }
}

void Video::rect(int x, int y, int w, int h, uint8_t c) {
    fill(x, y, w, 1, c);
    fill(x, y + h - 1, w, 1, c);
    fill(x, y, 1, h, c);
    fill(x + w - 1, y, 1, h, c);
}

void Video::line(int x0, int y0, int x1, int y1, uint8_t c) {
    int dx = std::abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
    int dy = -std::abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
    int err = dx + dy;
    while (true) {
        pset(x0, y0, c);
        if (x0 == x1 && y0 == y1) break;
        int e2 = 2 * err;
        if (e2 >= dy) { err += dy; x0 += sx; }
        if (e2 <= dx) { err += dx; y0 += sy; }
    }
}

void Video::blit(const omf::Image& img, int x, int y, bool flipX, bool flipY, bool opaque, const uint8_t* remap,
                 int palOffset, int palLimit, int opacity) {
    static const uint8_t bayer[4][4] = {{0, 8, 2, 10}, {12, 4, 14, 6}, {3, 11, 1, 9}, {15, 7, 13, 5}};
    if (opacity <= 0) return;
    const bool dither = opacity < 255;
    const int level = opacity * 16 / 256;   // 0..15 pixels of 16 kept
    for (int sy = 0; sy < img.h; ++sy) {
        int dy = y + sy;
        if (dy < cy0_ || dy >= cy1_) continue;
        int ry = flipY ? img.h - 1 - sy : sy;
        const uint8_t* row = img.px.data() + size_t(ry) * img.w;
        for (int sx = 0; sx < img.w; ++sx) {
            int dx = x + sx;
            if (dx < cx0_ || dx >= cx1_) continue;
            uint8_t c = row[flipX ? img.w - 1 - sx : sx];
            if (!c && !opaque) continue;
            if (dither && bayer[dy & 3][dx & 3] >= level) continue;
            if (c && c <= palLimit) c = uint8_t(std::min(c + palOffset, palLimit));
            const size_t at = size_t(dy) * W + dx;
            uint8_t& d = fb_[at];
            d = remap ? remap[d] : c;
            if (!remap) mask_[at] = marking_;
        }
    }
}

void Video::blitColor(const omf::Image& img, int x, int y, bool flipX, bool flipY, uint8_t col) {
    for (int sy = 0; sy < img.h; ++sy) {
        int ry = flipY ? img.h - 1 - sy : sy;
        for (int sx = 0; sx < img.w; ++sx)
            if (img.px[size_t(ry) * img.w + (flipX ? img.w - 1 - sx : sx)]) pset(x + sx, y + sy, col);
    }
}

void Video::remapRect(int x, int y, int w, int h, const uint8_t* remap, int rounds) {
    int x0 = std::max(x, cx0_), y0 = std::max(y, cy0_);
    int x1 = std::min(x + w, cx1_), y1 = std::min(y + h, cy1_);
    for (int yy = y0; yy < y1; ++yy)
        for (int xx = x0; xx < x1; ++xx) {
            uint8_t& d = fb_[size_t(yy) * W + xx];
            for (int r = 0; r < rounds; ++r) d = remap[d];
        }
}

void Video::clip(int x, int y, int w, int h) {
    cx0_ = std::clamp(x, 0, W);
    cy0_ = std::clamp(y, 0, H);
    cx1_ = std::clamp(x + w, 0, W);
    cy1_ = std::clamp(y + h, 0, H);
}

void Video::unclip() {
    cx0_ = cy0_ = 0;
    cx1_ = W;
    cy1_ = H;
}

void Video::setFont(int which, const omf::FontFile& f) { fonts_[which & 1] = f; }

int Video::textWidth(const std::string& s, int font) const {
    const auto& f = fonts_[font & 1];
    return int(s.size()) * (f.size ? f.size : 8);
}

int Video::text(const std::string& s, int x, int y, uint8_t c, int font, int shadow, int shadowDir) {
    const auto& f = fonts_[font & 1];
    if (!f.size) return x;
    const int sd = shadowDir < 0 ? -1 : 1;
    // shadow first, so it never covers a neighbouring glyph pixel
    for (int pass = shadow >= 0 ? 0 : 1; pass < 2; ++pass) {
        int cx = x;
        for (unsigned char ch : s) {
            for (int gy = 0; gy < f.size; ++gy)
                for (int gx = 0; gx < f.size; ++gx)
                    if (f.pixel(ch, gx, gy)) {
                        if (pass == 0) pset(cx + gx + sd, y + gy + sd, uint8_t(shadow));
                        else pset(cx + gx, y + gy, c);
                    }
            cx += f.size;
        }
    }
    return x + int(s.size()) * f.size;
}

void Video::setBase(int first, int count, const uint8_t* rgb) {
    for (int i = 0; i < count && first + i < 256; ++i)
        for (int k = 0; k < 3; ++k) base_[size_t((first + i) * 3 + k)] = rgb[i * 3 + k];
    work_ = base_;
}

void Video::setBaseColor(int i, uint8_t r, uint8_t g, uint8_t b) {
    if (i < 0 || i > 255) return;
    base_[size_t(i * 3)] = r;
    base_[size_t(i * 3 + 1)] = g;
    base_[size_t(i * 3 + 2)] = b;
}

// Same arithmetic as OpenOMF's vga_palette_mix_range / tint_range.
void Video::mixRange(int ref, int start, int end, int step) {
    ref = std::clamp(ref, 0, 255);
    start = std::clamp(start, 0, 256);
    end = std::clamp(end, start, 256);
    step = std::clamp(step, 0, 255);
    const uint8_t rr = work_[size_t(ref * 3)], rg = work_[size_t(ref * 3 + 1)], rb = work_[size_t(ref * 3 + 2)];
    const unsigned inv = 255u - unsigned(step);
    for (int i = start; i < end; ++i) {
        uint8_t* c = &work_[size_t(i * 3)];
        c[0] = uint8_t((c[0] * inv + rr * unsigned(step)) >> 8);
        c[1] = uint8_t((c[1] * inv + rg * unsigned(step)) >> 8);
        c[2] = uint8_t((c[2] * inv + rb * unsigned(step)) >> 8);
    }
}

void Video::tintRange(int ref, int start, int end, int step) {
    ref = std::clamp(ref, 0, 255);
    start = std::clamp(start, 0, 256);
    end = std::clamp(end, start, 256);
    step = std::clamp(step, 0, 255);
    const int rr = work_[size_t(ref * 3)], rg = work_[size_t(ref * 3 + 1)], rb = work_[size_t(ref * 3 + 2)];
    for (int i = start; i < end; ++i) {
        uint8_t* c = &work_[size_t(i * 3)];
        int m = std::max({c[0], c[1], c[2]});
        int u = (step * m) >> 8;
        c[0] = uint8_t(c[0] + ((u * (rr - c[0])) >> 8));
        c[1] = uint8_t(c[1] + ((u * (rg - c[1])) >> 8));
        c[2] = uint8_t(c[2] + ((u * (rb - c[2])) >> 8));
    }
}

void Video::darken(int step) {
    step = std::clamp(step, 0, 255);
    const unsigned inv = 255u - unsigned(step);
    for (auto& c : work_) c = uint8_t((c * inv) >> 8);
}

void Video::setUpscale(int factor, int smoothing, bool soft, int sharpen) {
    factor_ = std::clamp(factor, 1, 4);
    sharpen_ = std::clamp(sharpen, 0, 3);
    smoothing_ = std::clamp(smoothing, 0, 2);
    soft_ = soft;
}

void Video::present() {
    for (size_t i = 0; i < fb_.size(); ++i) {
        const uint8_t* c = &work_[size_t(fb_[i]) * 3];
        rgba_[i] = 0xFF000000u | (uint32_t(c[0]) << 16) | (uint32_t(c[1]) << 8) | c[2];
    }
    const uint32_t* frame = rgba_.data();
    int fw = W, fh = H;
    if (factor_ > 1 || sharpen_ > 0) {
        upscale::scale(rgba_.data(), mask_.data(), W, H, factor_, smoothing_ > 0, smoothing_ == 2, big_);
        fw = W * factor_;
        fh = H * factor_;
        static const int kSharpen[4] = {0, 96, 176, 256};
        upscale::sharpen(big_, fw, fh, kSharpen[sharpen_]);
        frame = big_.data();
    }
    shown_ = frame;
    shownW_ = fw;
    shownH_ = fh;
    if (headless_) return;
    if (fw != texW_ || fh != texH_) {
        SDL_DestroyTexture(texture_);
        texture_ = SDL_CreateTexture(renderer_, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, fw, fh);
        texW_ = fw;
        texH_ = fh;
    }
    SDL_SetTextureScaleMode(texture_, soft_ ? SDL_ScaleModeLinear : SDL_ScaleModeNearest);
    SDL_UpdateTexture(texture_, nullptr, frame, fw * 4);
    int ow = 0, oh = 0;
    SDL_GetRendererOutputSize(renderer_, &ow, &oh);
    // 4:3, as mode 13h filled a DOS monitor.
    int w = ow, h = ow * 3 / 4;
    if (h > oh) { h = oh; w = oh * 4 / 3; }
    SDL_Rect dst{(ow - w) / 2, (oh - h) / 2, w, h};
    SDL_SetRenderDrawColor(renderer_, 0, 0, 0, 255);
    SDL_RenderClear(renderer_);
    SDL_RenderCopy(renderer_, texture_, nullptr, &dst);
    SDL_RenderPresent(renderer_);
}

bool Video::screenshot(const std::string& path) const {
    // what was shown: the upscaled / sharpened frame when those are on
    const bool big = shown_ && shown_ == big_.data();
    const int w = big ? shownW_ : W, h = big ? shownH_ : H;
    SDL_Surface* s = SDL_CreateRGBSurfaceWithFormatFrom(const_cast<uint32_t*>(big ? big_.data() : rgba_.data()), w,
                                                       h, 32, w * 4, SDL_PIXELFORMAT_ARGB8888);
    if (!s) return false;
    bool ok = SDL_SaveBMP(s, path.c_str()) == 0;
    SDL_FreeSurface(s);
    return ok;
}

void Video::toggleFullscreen() {
    if (!window_) return;
    fullscreen_ = !fullscreen_;
    SDL_SetWindowFullscreen(window_, fullscreen_ ? SDL_WINDOW_FULLSCREEN_DESKTOP : 0);
}
