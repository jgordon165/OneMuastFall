// ENGLISH.DAT / GERMAN.DAT: the game's text. A table of (offset, 32-byte
// description) entries, then the strings, each XORed with a running key that
// starts at its length & 0xFF and goes up by one per byte.
#pragma once
#include <string>
#include <vector>

#include "formats/reader.h"

namespace omf {

struct LangString {
    std::string description;
    std::string text;
};

struct LanguageFile {
    std::vector<LangString> strings;
};

bool loadLanguage(const Bytes& data, LanguageFile& out, std::string* err = nullptr);

}  // namespace omf
