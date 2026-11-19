// Little-endian reader over a byte buffer. Every OMF:2097 file is read
// through this; reading past the end sets ok() false and returns zeros, so a
// truncated file fails cleanly instead of crashing.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace omf {

using Bytes = std::vector<uint8_t>;

bool readFile(const std::string& path, Bytes& out);

class Reader {
public:
    explicit Reader(const Bytes& b) : d_(b.data()), n_(b.size()) {}
    Reader(const uint8_t* d, size_t n) : d_(d), n_(n) {}

    bool ok() const { return ok_; }
    bool eof() const { return p_ >= n_; }
    size_t pos() const { return p_; }
    size_t size() const { return n_; }
    void seek(size_t p) { if (p > n_) { ok_ = false; p_ = n_; } else p_ = p; }
    void skip(size_t k) { seek(p_ + k); }

    uint8_t  u8();
    int8_t   s8() { return int8_t(u8()); }
    uint16_t u16();
    int16_t  s16() { return int16_t(u16()); }
    uint32_t u32();
    int32_t  s32() { return int32_t(u32()); }
    bool     bytes(void* dst, size_t k);
    Bytes    bytes(size_t k);

    // u16 length, then that many bytes, then a NUL that the length doesn't count.
    bool terminatedStr(std::string& out, uint16_t maxLen);
    // u16 length, then that many bytes (no NUL).
    bool paddedStr(std::string& out, uint16_t maxLen);
    // A fixed-size field, NUL-padded.
    std::string fixedStr(size_t len);

private:
    const uint8_t* d_;
    size_t n_;
    size_t p_ = 0;
    bool ok_ = true;
};

}  // namespace omf
