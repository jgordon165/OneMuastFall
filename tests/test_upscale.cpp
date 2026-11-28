// The picture filters (src/upscale.cpp) over random frames and masks: every
// factor and mode gives a frame of the right size, flat areas and plain
// enlarging leave colours as they were, and nothing reads or writes out of
// bounds (run it under ASan / UBSan).
#include "upscale.h"

#include <cstdio>
#include <cstdlib>

static int fails = 0;
#define CHECK(c) do { if (!(c)) { std::printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); ++fails; } } while (0)

int main() {
    std::srand(2097);
    for (int t = 0; t < 60; ++t) {
        const int w = 3 + std::rand() % 40, h = 3 + std::rand() % 30;
        std::vector<uint32_t> src(size_t(w) * h);
        std::vector<uint8_t> mask(size_t(w) * h);
        for (auto& v : src) v = 0xFF000000u | uint32_t(std::rand() % 4) * 0x404040u;
        for (auto& v : mask) v = uint8_t(std::rand() % 2);
        for (int n = 1; n <= 4; ++n)
            for (int sm = 0; sm < 2; ++sm)
                for (int ev = 0; ev < 2; ++ev) {
                    std::vector<uint32_t> dst;
                    upscale::scale(src.data(), std::rand() % 3 ? mask.data() : nullptr, w, h, n, sm, ev, dst);
                    CHECK(dst.size() == size_t(w * n) * h * n);
                    if (!sm)
                        for (int y = 0; y < h * n; ++y)
                            for (int x = 0; x < w * n; ++x)
                                if (dst[size_t(y) * w * n + x] != src[size_t(y / n) * w + x / n]) {
                                    CHECK(!"plain enlarging changed a colour");
                                    y = h * n;
                                    break;
                                }
                    upscale::sharpen(dst, w * n, h * n, std::rand() % 257);
                }
    }
    // a flat frame stays flat through everything
    std::vector<uint32_t> flat(64 * 40, 0xFF336699u), out;
    std::vector<uint8_t> m(64 * 40, 1);
    upscale::scale(flat.data(), m.data(), 64, 40, 3, true, true, out);
    upscale::sharpen(out, 192, 120, 256);
    bool same = true;
    for (auto v : out) same = same && v == 0xFF336699u;
    CHECK(same);
    std::printf(fails ? "%d failures\n" : "upscale: ok\n", fails);
    return fails ? 1 : 0;
}
