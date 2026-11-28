#include "upscale.h"

#include <algorithm>
#include <cstdlib>

namespace upscale {
namespace {

struct Src {
    const uint32_t* px;
    const uint8_t* mask;   // sprite pixels, or null
    int w, h;
    bool all;              // the colour-edge pass on every pixel
    uint32_t at(int x, int y) const {
        x = std::clamp(x, 0, w - 1);
        y = std::clamp(y, 0, h - 1);
        return px[size_t(y) * w + x];
    }
    // the filter runs on sprite pixels and the pixels around them
    bool active(int x, int y) const {
        if (all || !mask) return true;
        auto m = [&](int xx, int yy) {
            return xx >= 0 && yy >= 0 && xx < w && yy < h && mask[size_t(yy) * w + xx];
        };
        return m(x, y) || m(x - 1, y) || m(x + 1, y) || m(x, y - 1) || m(x, y + 1);
    }
    // a sprite's edge passes through this pixel's 3x3 neighbourhood
    bool outline(int x, int y) const {
        int set = 0;
        for (int j = -1; j <= 1; ++j)
            for (int i = -1; i <= 1; ++i) {
                const int xx = std::clamp(x + i, 0, w - 1), yy = std::clamp(y + j, 0, h - 1);
                set += mask[size_t(yy) * w + xx] ? 1 : 0;
            }
        return set > 0 && set < 9;
    }
};

void block(std::vector<uint32_t>& dst, int dw, int x, int y, int n, uint32_t c) {
    for (int j = 0; j < n; ++j) std::fill_n(dst.begin() + size_t(y * n + j) * dw + size_t(x) * n, n, c);
}

// ---- xBR-style smoothing ----

// colour distance, weighted toward brightness (YUV), as xBR does
int dist(uint32_t a, uint32_t b) {
    if (a == b) return 0;
    const int dr = int((a >> 16) & 0xFF) - int((b >> 16) & 0xFF);
    const int dg = int((a >> 8) & 0xFF) - int((b >> 8) & 0xFF);
    const int db = int(a & 0xFF) - int(b & 0xFF);
    const int y = std::abs(299 * dr + 587 * dg + 114 * db);
    const int u = std::abs(-169 * dr - 331 * dg + 500 * db);
    const int v = std::abs(500 * dr - 419 * dg - 81 * db);
    return (48 * y + 7 * u + 6 * v) / 1000;
}

// below this the two sides are shades of one surface: leave them alone
constexpr int kContrast = 600;

uint32_t mix(uint32_t a, uint32_t b, int t /* 0..256: share of b */) {
    auto ch = [&](int s) {
        const int x = int((a >> s) & 0xFF), y = int((b >> s) & 0xFF);
        return uint32_t((x * (256 - t) + y * t) >> 8) << s;
    };
    return 0xFF000000u | ch(16) | ch(8) | ch(0);
}

// The sprite's outline, from the mask: the mask is sampled between pixel
// centres (bilinear), so a staircase edge becomes a slope, and the
// sub-pixel takes the sprite's colour where the sample is over the middle,
// the background's where under, blended across a narrow band.
void silhouette(const Src& s, int x, int y, int n, uint32_t* out) {
    auto m = [&](int xx, int yy) {
        xx = std::clamp(xx, 0, s.w - 1);
        yy = std::clamp(yy, 0, s.h - 1);
        return s.mask[size_t(yy) * s.w + xx] ? 1 : 0;
    };
    for (int j = 0; j < n; ++j)
        for (int i = 0; i < n; ++i) {
            // sub-pixel centre, in source pixels from this pixel's centre
            const float px = (i + 0.5f) / n - 0.5f, py = (j + 0.5f) / n - 0.5f;
            const int x0 = px < 0 ? x - 1 : x, y0 = py < 0 ? y - 1 : y;
            const float fx = px < 0 ? px + 1.0f : px, fy = py < 0 ? py + 1.0f : py;
            const int m00 = m(x0, y0), m10 = m(x0 + 1, y0), m01 = m(x0, y0 + 1), m11 = m(x0 + 1, y0 + 1);
            const int sum = m00 + m10 + m01 + m11;
            if (sum == 0 || sum == 4) continue;   // not on the outline
            const float w00 = (1 - fx) * (1 - fy), w10 = fx * (1 - fy), w01 = (1 - fx) * fy, w11 = fx * fy;
            const float v = m00 * w00 + m10 * w10 + m01 * w01 + m11 * w11;
            // the colours on each side: the nearest sprite / background pixel
            const int xs[4] = {x0, x0 + 1, x0, x0 + 1}, ys[4] = {y0, y0, y0 + 1, y0 + 1};
            const float ws[4] = {w00, w10, w01, w11};
            const int ms[4] = {m00, m10, m01, m11};
            int bi = -1, bo = -1;
            for (int k = 0; k < 4; ++k) {
                if (ms[k] && (bi < 0 || ws[k] > ws[bi])) bi = k;
                if (!ms[k] && (bo < 0 || ws[k] > ws[bo])) bo = k;
            }
            const uint32_t in = s.at(xs[bi], ys[bi]), outside = s.at(xs[bo], ys[bo]);
            // 0.5 is the outline; the band is about one output pixel wide
            const float c = std::clamp(0.5f + (v - 0.5f) * 1.6f * n, 0.0f, 1.0f);
            const int t = int(c * 256.0f + 0.5f);
            if (t >= 256) {
                if (!s.mask[size_t(y) * s.w + x]) out[j * n + i] = in;   // the sprite grows over the corner
            } else if (t <= 0) {
                if (s.mask[size_t(y) * s.w + x]) out[j * n + i] = outside;   // the corner is cut off
            } else {
                out[j * n + i] = mix(outside, in, t);
            }
        }
}

void smooth(const Src& s, int n, std::vector<uint32_t>& dst) {
    const int dw = s.w * n;
    dst.assign(size_t(dw) * s.h * n, 0);
    // the four corners: the "right" (F) and "down" (H) axes, turned
    static const int AX[4][4] = {{1, 0, 0, 1}, {0, 1, -1, 0}, {-1, 0, 0, -1}, {0, -1, 1, 0}};
    // coverage of each sub-pixel by each corner's edge (0..256)
    int cover[4][16];
    for (int k = 0; k < 4; ++k)
        for (int j = 0; j < n; ++j)
            for (int i = 0; i < n; ++i) {
                const float cx = (i + 0.5f) / n - 0.5f, cy = (j + 0.5f) / n - 0.5f;
                const float u = cx * AX[k][0] + cy * AX[k][1], v = cx * AX[k][2] + cy * AX[k][3];
                // the edge cuts the corner on the line u + v = 1/2
                const float c = std::clamp(0.5f + (u + v - 0.5f) * n, 0.0f, 1.0f);
                cover[k][j * n + i] = int(c * 256.0f + 0.5f);
            }
    uint32_t out[16];
    for (int y = 0; y < s.h; ++y)
        for (int x = 0; x < s.w; ++x) {
            const uint32_t E = s.at(x, y);
            if (!s.active(x, y)) {
                block(dst, dw, x, y, n, E);
                continue;
            }
            std::fill_n(out, n * n, E);
            for (int k = 0; k < 4; ++k) {
                const int* a = AX[k];
                auto g = [&](int p, int q) { return s.at(x + p * a[0] + q * a[2], y + p * a[1] + q * a[3]); };
                const uint32_t F = g(1, 0), H = g(0, 1);
                if (F == E || H == E) continue;
                // an edge runs between F and H: clearly so (not shading), with
                // F and H alike and both standing apart from E. Cheap tests first.
                const int ef = dist(E, F), eh = dist(E, H);
                if (std::min(ef, eh) < kContrast) continue;
                const int fh = dist(F, H);
                if (fh >= 2 * std::min(ef, eh)) continue;
                const uint32_t I = g(1, 1), B = g(0, -1), D = g(-1, 0), C = g(1, -1), G = g(-1, 1);
                const uint32_t F4 = g(2, 0), I4 = g(2, 1), H5 = g(0, 2), I5 = g(1, 2);
                const int across = dist(E, C) + dist(E, G) + dist(I, F4) + dist(I, H5) + 4 * fh;
                const int along = dist(H, D) + dist(H, I5) + dist(F, I4) + dist(F, B) + 4 * dist(E, I);
                if (across >= along) continue;
                const uint32_t to = ef <= eh ? F : H;
                for (int p = 0; p < n * n; ++p)
                    if (cover[k][p]) out[p] = mix(out[p], to, cover[k][p]);
            }
            if (s.mask && s.outline(x, y)) silhouette(s, x, y, n, out);
            for (int j = 0; j < n; ++j)
                std::copy_n(out + j * n, n, dst.begin() + size_t(y * n + j) * dw + size_t(x) * n);
        }
}

}  // namespace

void scale(const uint32_t* src, const uint8_t* mask, int w, int h, int n, bool smoothing, bool everything,
           std::vector<uint32_t>& dst) {
    n = std::clamp(n, 1, 4);
    if (n > 1 && smoothing) {
        smooth(Src{src, mask, w, h, everything}, n, dst);
        return;
    }
    const int dw = w * n;
    dst.assign(size_t(dw) * h * n, 0);
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) block(dst, dw, x, y, n, src[size_t(y) * w + x]);
}

void sharpen(std::vector<uint32_t>& img, int w, int h, int amount) {
    if (amount <= 0 || w < 3 || h < 3) return;
    // unsharp mask over the four neighbours: c + amount * (c - their average)
    std::vector<uint32_t> prev(img.begin(), img.begin() + w), cur(w);
    for (int y = 1; y < h - 1; ++y) {
        std::copy_n(img.begin() + size_t(y) * w, w, cur.begin());
        const uint32_t* below = &img[size_t(y + 1) * w];
        uint32_t* row = &img[size_t(y) * w];
        for (int x = 1; x < w - 1; ++x) {
            const uint32_t c = cur[x], n = prev[x], so = below[x], we = cur[x - 1], ea = cur[x + 1];
            if (c == n && c == so && c == we && c == ea) continue;   // flat: nothing to do
            uint32_t o = 0xFF000000u;
            for (int sh = 0; sh <= 16; sh += 8) {
                const int v = int((c >> sh) & 0xFF);
                const int sum = int((n >> sh) & 0xFF) + int((so >> sh) & 0xFF) + int((we >> sh) & 0xFF) +
                                int((ea >> sh) & 0xFF);
                const int r = v + (amount * (4 * v - sum)) / 1024;
                o |= uint32_t(std::clamp(r, 0, 255)) << sh;
            }
            row[x] = o;
        }
        prev.swap(cur);
    }
}

}  // namespace upscale
