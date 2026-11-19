#include "vfs.h"

#include <algorithm>
#include <cctype>
#include <filesystem>

namespace fs = std::filesystem;

static std::string upper(std::string s) {
    for (auto& c : s) c = char(std::toupper(static_cast<unsigned char>(c)));
    return s;
}

bool Vfs::mount(const std::string& dir) {
    root_ = dir;
    entries_.clear();
    std::error_code ec;
    mounted_ = fs::is_directory(fs::path(dir), ec);
    if (!mounted_) return false;
    for (auto& e : fs::directory_iterator(fs::path(dir), ec)) {
        if (!e.is_regular_file(ec)) continue;
        entries_.push_back({e.path().filename().string(), uint64_t(e.file_size(ec))});
    }
    std::sort(entries_.begin(), entries_.end(),
              [](const Entry& a, const Entry& b) { return upper(a.name) < upper(b.name); });
    return true;
}

std::string Vfs::resolve(const std::string& name) const {
    if (!mounted_) return {};
    const std::string want = upper(name);
    for (const auto& e : entries_)
        if (upper(e.name) == want) return (fs::path(root_) / fs::path(e.name)).string();
    return {};
}

bool Vfs::read(const std::string& name, omf::Bytes& out) const {
    std::string p = resolve(name);
    return !p.empty() && omf::readFile(p, out);
}
