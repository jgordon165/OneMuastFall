#include "formats/language.h"

namespace omf {

bool loadLanguage(const Bytes& data, LanguageFile& lang, std::string* err) {
    auto fail = [&](const char* m) { if (err) *err = m; return false; };
    Reader r(data);
    const uint32_t size = uint32_t(data.size());
    std::vector<uint32_t> offs;
    std::vector<std::string> desc;
    // Entries run until an offset points past the end (the strings start
    // where the table ends, so the first string's bytes stop the loop).
    while (true) {
        size_t at = r.pos();
        uint32_t o = r.u32();
        if (!r.ok() || o >= size || at >= size) break;
        offs.push_back(o);
        desc.push_back(r.fixedStr(32));
        if (!offs.empty() && r.pos() >= offs.front()) break;
    }
    if (offs.empty()) return fail("no strings");
    offs.push_back(size);
    lang.strings.resize(desc.size());
    for (size_t i = 0; i < desc.size(); ++i) {
        lang.strings[i].description = desc[i];
        uint32_t a = offs[i], b = offs[i + 1];
        if (b <= a || b > size) continue;
        uint32_t len = b - a;
        std::string s(len, '\0');
        uint8_t key = uint8_t(len & 0xFF);
        for (uint32_t k = 0; k < len; ++k) s[k] = char(data[a + k] ^ key++);
        // strings are NUL-terminated inside their slot
        size_t nul = s.find('\0');
        if (nul != std::string::npos) s.resize(nul);
        lang.strings[i].text = std::move(s);
    }
    return true;
}

}  // namespace omf
