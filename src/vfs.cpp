#include "vfs.h"

#include <algorithm>
#include <cctype>

#ifndef XENON
#include <filesystem>
namespace fs = std::filesystem;
#else
#include <dirent.h>
#include <sys/stat.h>
#endif

static std::string upper(std::string s) {
    for (auto& c : s) c = char(std::toupper(static_cast<unsigned char>(c)));
    return s;
}

static std::string join(const std::string& dir, const std::string& name) {
    if (dir.empty()) return name;
    char last = dir.back();
    return (last == '/' || last == '\\' || last == ':') ? dir + name : dir + "/" + name;
}

bool Vfs::mount(const std::string& dir) {
    root_ = dir;
    entries_.clear();
    mounted_ = false;
#ifndef XENON
    std::error_code ec;
    if (!fs::is_directory(fs::path(dir), ec)) return false;
    for (auto& e : fs::directory_iterator(fs::path(dir), ec)) {
        if (!e.is_regular_file(ec)) continue;
        entries_.push_back({e.path().filename().string(), uint64_t(e.file_size(ec))});
    }
#else
    // newlib + the console's FAT driver: plain dirent / stat
    DIR* d = ::opendir(dir.c_str());
    if (!d) return false;
    while (dirent* e = ::readdir(d)) {
        std::string n = e->d_name;
        if (n == "." || n == "..") continue;
        struct stat st {};
        if (::stat(join(dir, n).c_str(), &st) != 0 || S_ISDIR(st.st_mode)) continue;
        entries_.push_back({n, uint64_t(st.st_size)});
    }
    ::closedir(d);
#endif
    mounted_ = true;
    std::sort(entries_.begin(), entries_.end(),
              [](const Entry& a, const Entry& b) { return upper(a.name) < upper(b.name); });
    return true;
}

std::string Vfs::resolve(const std::string& name) const {
    if (!mounted_) return {};
    const std::string want = upper(name);
    for (const auto& e : entries_)
        if (upper(e.name) == want) return join(root_, e.name);
    return {};
}

bool Vfs::read(const std::string& name, omf::Bytes& out) const {
    std::string p = resolve(name);
    return !p.empty() && omf::readFile(p, out);
}
