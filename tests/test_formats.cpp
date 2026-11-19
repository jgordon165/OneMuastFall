// Format tests. Synthetic cases always run; with OMF_DATA=<game folder> every
// original file is decoded too (nothing from the game is in the repo).
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>

#include "formats/af.h"
#include "formats/altpal.h"
#include "formats/bk.h"
#include "formats/font.h"
#include "formats/language.h"
#include "formats/pic.h"
#include "formats/sounds.h"

using namespace omf;
namespace fs = std::filesystem;

static int failures = 0;
#define CHECK(c)                                                              \
    do {                                                                      \
        if (!(c)) {                                                           \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c);          \
            ++failures;                                                       \
        }                                                                     \
    } while (0)

static void testSpriteRle() {
    // 3x2 sprite: row 0 = 5 6 7, row 1 at x=1 = 9.
    Bytes rle;
    auto w = [&](unsigned v) { rle.push_back(uint8_t(v)); rle.push_back(uint8_t(v >> 8)); };
    w((0 << 2) | 2);          // y = 0
    w((3 << 2) | 1);          // copy 3
    rle.insert(rle.end(), {5, 6, 7});
    w((1 << 2) | 2);          // y = 1
    w((1 << 2) | 0);          // x = 1
    w((1 << 2) | 1);          // copy 1
    rle.push_back(9);
    w(3);                     // end
    Image img = decodeSpriteRle(rle, 3, 2);
    CHECK(img.w == 3 && img.h == 2);
    CHECK(img.px[0] == 5 && img.px[1] == 6 && img.px[2] == 7);
    CHECK(img.px[3] == 0 && img.px[4] == 9 && img.px[5] == 0);
}

static void testDac() {
    CHECK(dac6to8(63) == 255);
    CHECK(dac6to8(0) == 0);
    CHECK(dac6to8(32) == 130);
}

static void testLanguageXor() {
    // One entry: offset 36 + 32-byte description, then "HI\0" XORed.
    Bytes d(36 + 3, 0);
    d[0] = 36;
    const char* s = "HI";
    uint8_t key = 3;
    for (int i = 0; i < 3; ++i) d[36 + i] = uint8_t((i < 2 ? s[i] : 0) ^ key++);
    LanguageFile lf;
    CHECK(loadLanguage(d, lf));
    CHECK(lf.strings.size() == 1 && lf.strings[0].text == "HI");
}

static fs::path find(const fs::path& dir, const std::string& name) {
    for (auto& e : fs::directory_iterator(dir)) {
        std::string n = e.path().filename().string();
        std::string a = n, b = name;
        for (auto& c : a) c = char(std::toupper(static_cast<unsigned char>(c)));
        for (auto& c : b) c = char(std::toupper(static_cast<unsigned char>(c)));
        if (a == b) return e.path();
    }
    return {};
}

static void testRealData(const fs::path& dir) {
    std::printf("decoding the original files in %s\n", dir.string().c_str());
    int bks = 0, afs = 0, sprites = 0;
    for (auto& e : fs::directory_iterator(dir)) {
        std::string ext = e.path().extension().string();
        for (auto& c : ext) c = char(std::toupper(static_cast<unsigned char>(c)));
        Bytes b;
        if (ext == ".BK") {
            CHECK(readFile(e.path().string(), b));
            BkFile bk;
            std::string err;
            bool ok = loadBk(b, bk, &err);
            if (!ok) std::printf("  %s: %s\n", e.path().filename().string().c_str(), err.c_str());
            CHECK(ok);
            CHECK(bk.background.w == 320 && bk.background.h == 200);
            CHECK(!bk.palettes.empty());
            for (auto& [id, a] : bk.anims)
                for (auto& s : a.ani.sprites) {
                    Image img = decodeSprite(s);
                    CHECK(img.w >= 1);
                    ++sprites;
                }
            std::printf("  %-12s %2zu anims, %zu palettes\n", e.path().filename().string().c_str(), bk.anims.size(),
                        bk.palettes.size());
            ++bks;
        } else if (ext == ".AF") {
            CHECK(readFile(e.path().string(), b));
            AfFile af;
            std::string err;
            bool ok = loadAf(b, af, &err);
            if (!ok) std::printf("  %s: %s\n", e.path().filename().string().c_str(), err.c_str());
            CHECK(ok);
            CHECK(af.moves.size() > 10);
            for (auto& [id, m] : af.moves)
                for (auto& s : m.ani.sprites) { decodeSprite(s); ++sprites; }
            std::printf("  %-12s id %u, %zu moves, health %u\n", e.path().filename().string().c_str(), af.fighterId,
                        af.moves.size(), af.health);
            ++afs;
        } else if (ext == ".PIC") {
            CHECK(readFile(e.path().string(), b));
            PicFile pic;
            CHECK(loadPic(b, pic));
            CHECK(!pic.photos.empty());
            std::printf("  %-12s %zu photos\n", e.path().filename().string().c_str(), pic.photos.size());
        }
    }
    CHECK(bks >= 10);
    CHECK(afs == 11);
    std::printf("  %d sprites decoded\n", sprites);

    Bytes b;
    SoundsFile sf;
    CHECK(readFile(find(dir, "SOUNDS.DAT").string(), b) && loadSounds(b, sf));
    std::printf("  SOUNDS.DAT   %zu sounds\n", sf.sounds.size());
    CHECK(sf.sounds.size() > 50);

    LanguageFile lf;
    CHECK(readFile(find(dir, "ENGLISH.DAT").string(), b) && loadLanguage(b, lf));
    std::printf("  ENGLISH.DAT  %zu strings; #0 \"%s\"\n", lf.strings.size(),
                lf.strings.empty() ? "" : lf.strings[0].text.substr(0, 40).c_str());
    CHECK(lf.strings.size() > 900);

    FontFile big, small;
    CHECK(readFile(find(dir, "GRAPHCHR.DAT").string(), b) && loadFont(b, 8, big));
    CHECK(readFile(find(dir, "CHARSMAL.DAT").string(), b) && loadFont(b, 6, small));
    AltPalFile ap;
    CHECK(readFile(find(dir, "ALTPALS.DAT").string(), b) && loadAltPals(b, ap));
}

int main() {
    testSpriteRle();
    testDac();
    testLanguageXor();
    if (const char* d = std::getenv("OMF_DATA")) testRealData(d);
    if (failures) {
        std::printf("%d failure(s)\n", failures);
        return 1;
    }
    std::printf("all format tests passed\n");
    return 0;
}
