#pragma once
// Upscaling for the finished 320x200 frame (ADVANCED SETTINGS).
//
// Without smoothing the frame is enlarged n times as plain blocks (with
// the SOFT screen filter that gives clean pixels at any window size).
//
// Smoothing, at 2x-4x:
//   * sprite outlines, from `mask` (one byte per pixel: drawn as a sprite):
//     the outline is traced between pixel centres, so staircases become
//     slopes, and anti-aliased against whatever is behind;
//   * colour edges, xBR-style: a pixel corner where a clear diagonal edge
//     runs across a 5x5 neighbourhood takes the neighbouring colour. On
//     the sprites (and around them), or with `everything` on every pixel.
// Shading inside the sprites is left alone.
//
// Sharpening runs last, on the enlarged frame, so its halo is one output
// pixel wide however large the picture is.

#include <cstdint>
#include <vector>

namespace upscale {

// dst gets (w*n) x (h*n) pixels, 0xAARRGGBB. n = 1..4.
void scale(const uint32_t* src, const uint8_t* mask, int w, int h, int n, bool smoothing, bool everything,
           std::vector<uint32_t>& dst);

// Sharpening (unsharp mask on the four neighbours), in place, over the
// frame as shown. amount 0..256: how much of the difference to add back.
void sharpen(std::vector<uint32_t>& img, int w, int h, int amount);

}  // namespace upscale
