#include "formats/reader.h"

#include <cstdio>
#include <cstring>

namespace omf {

bool readFile(const std::string& path, Bytes& out) {
    FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) return false;
    std::fseek(f, 0, SEEK_END);
    long n = std::ftell(f);
    std::fseek(f, 0, SEEK_SET);
    if (n < 0) { std::fclose(f); return false; }
    out.resize(size_t(n));
    bool ok = n == 0 || std::fread(out.data(), 1, size_t(n), f) == size_t(n);
    std::fclose(f);
    return ok;
}

uint8_t Reader::u8() {
    if (p_ + 1 > n_) { ok_ = false; p_ = n_; return 0; }
    return d_[p_++];
}

uint16_t Reader::u16() {
    if (p_ + 2 > n_) { ok_ = false; p_ = n_; return 0; }
    uint16_t v = uint16_t(d_[p_] | (d_[p_ + 1] << 8));
    p_ += 2;
    return v;
}

uint32_t Reader::u32() {
    if (p_ + 4 > n_) { ok_ = false; p_ = n_; return 0; }
    uint32_t v = uint32_t(d_[p_]) | (uint32_t(d_[p_ + 1]) << 8) | (uint32_t(d_[p_ + 2]) << 16) |
                 (uint32_t(d_[p_ + 3]) << 24);
    p_ += 4;
    return v;
}

bool Reader::bytes(void* dst, size_t k) {
    if (p_ + k > n_) {
        ok_ = false;
        std::memset(dst, 0, k);
        p_ = n_;
        return false;
    }
    std::memcpy(dst, d_ + p_, k);
    p_ += k;
    return true;
}

Bytes Reader::bytes(size_t k) {
    Bytes b(k);
    if (k) bytes(b.data(), k);
    return b;
}

bool Reader::terminatedStr(std::string& out, uint16_t maxLen) {
    uint16_t len = u16();
    if (len >= maxLen || !ok_) return false;
    Bytes b = bytes(size_t(len) + 1);
    if (!ok_ || b[len] != 0) return false;
    out.assign(reinterpret_cast<const char*>(b.data()), len);
    return true;
}

bool Reader::paddedStr(std::string& out, uint16_t maxLen) {
    uint16_t len = u16();
    if (len >= maxLen || !ok_) return false;
    Bytes b = bytes(len);
    size_t k = 0;
    while (k < b.size() && b[k]) ++k;
    out.assign(reinterpret_cast<const char*>(b.data()), k);
    return ok_;
}

std::string Reader::fixedStr(size_t len) {
    Bytes b = bytes(len);
    size_t k = 0;
    while (k < b.size() && b[k]) ++k;
    return std::string(reinterpret_cast<const char*>(b.data()), k);
}

}  // namespace omf
