// The player's game folder. DOS file names are matched case-insensitively,
// so a copy made on Linux or macOS with lowercase names works too.
#pragma once
#include <string>
#include <vector>

#include "formats/reader.h"

class Vfs {
public:
    struct Entry {
        std::string name;   // as on disk
        uint64_t size = 0;
    };

    bool mount(const std::string& dir);
    bool mounted() const { return mounted_; }
    const std::string& root() const { return root_; }

    // Full path of `name` (any case), or "" when it isn't there.
    std::string resolve(const std::string& name) const;
    bool exists(const std::string& name) const { return !resolve(name).empty(); }
    bool read(const std::string& name, omf::Bytes& out) const;
    const std::vector<Entry>& list() const { return entries_; }

private:
    std::string root_;
    bool mounted_ = false;
    std::vector<Entry> entries_;
};
