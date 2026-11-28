#include "formats/trn.h"

#include <cstring>

namespace omf {
namespace {

float readFloat(Reader& r) {
    uint32_t u = r.u32();
    float f;
    std::memcpy(&f, &u, 4);
    return f;
}

std::string cstr(Reader& r, size_t len) {
    std::string s = r.fixedStr(len);
    auto z = s.find('\0');
    return z == std::string::npos ? s : s.substr(0, z);
}

// u16 length, then that many bytes (the string ends at the first NUL)
bool padded(Reader& r, std::string& out) {
    uint16_t len = r.u16();
    out = len ? cstr(r, len) : std::string();
    return r.ok();
}

}  // namespace

bool readPilot(Reader& in, Pilot& p) {
    Bytes block = in.bytes(kPilotBlock);
    if (!in.ok() || block.size() != kPilotBlock) return false;
    uint8_t key = uint8_t(kPilotBlock & 0xFF);
    for (auto& b : block) b ^= key++;
    Reader r(block);

    p.unknownA = r.u32();
    p.name = cstr(r, 18);
    p.wins = r.u16();
    p.losses = r.u16();
    p.rank = r.u8();
    p.harId = r.u8();
    const uint16_t a = r.u16(), b = r.u16(), c = r.u16();
    const uint8_t d = r.u8();
    p.armPower = a & 0x1F;
    p.legPower = (a >> 5) & 0x1F;
    p.armSpeed = (a >> 10) & 0x1F;
    p.legSpeed = b & 0x1F;
    p.armor = (b >> 5) & 0x1F;
    p.stunResistance = (b >> 10) & 0x1F;
    p.agility = c & 0x7F;
    p.power = (c >> 7) & 0x7F;
    p.endurance = d & 0x7F;
    r.skip(1);
    p.offense = r.u16();
    p.defense = r.u16();
    p.money = r.s32();
    p.color3 = r.u8();
    p.color2 = r.u8();
    p.color1 = r.u8();

    p.trnName = cstr(r, 13);
    p.trnDesc = cstr(r, 31);
    p.trnImage = cstr(r, 13);
    p.trnRankMoney = readFloat(r);
    p.trnWinningsMult = readFloat(r);
    r.skip(40);                        // pointers, meaningless on disk
    p.pilotId = r.u8();
    p.unknownK = r.u8();
    p.forceArena = r.u16();
    p.difficulty = (r.u8() >> 3) & 0x3;
    r.skip(2);
    p.movement = r.u8();
    r.skip(6);
    for (auto& e : p.enhancements) e = r.u8();
    r.skip(1);
    const uint8_t flags = r.u8();
    p.secret = flags & 0x02;
    p.onlyFightOnce = flags & 0x08;
    r.skip(1);
    uint16_t req[5];
    for (auto& q : req) q = r.u16();
    p.reqRank = req[0] & 0xFF;
    p.reqMaxRank = req[0] >> 8;
    p.reqFighter = req[1] & 0x1F;
    p.reqDifficulty = (req[2] >> 8) & 0x0F;
    p.reqEnemy = req[2] & 0xFF;
    p.reqVitality = req[3] & 0x7F;
    p.reqAccuracy = (req[3] >> 7) & 0x7F;
    p.reqAvgDamage = req[4] & 0x7F;
    p.reqScrap = req[4] & 0x80;
    p.reqDestroy = (req[4] >> 8) & 0x01;
    uint16_t att[3];
    for (auto& q : att) q = r.u16();
    p.attNormal = (att[0] >> 4) & 0x7F;
    p.attHyper = att[1] & 0x7F;
    p.attJump = (att[1] >> 7) & 0x7F;
    p.attDef = att[2] & 0x7F;
    p.attSniper = (att[2] >> 7) & 0x7F;
    r.skip(4);
    p.apClose = r.s16();
    p.apThrow = r.s16();
    p.apSpecial = r.s16();
    p.apJump = r.s16();
    p.apHigh = r.s16();
    p.apLow = r.s16();
    p.apMiddle = r.s16();
    p.prefJump = r.s16();
    p.prefFwd = r.s16();
    p.prefBack = r.s16();
    p.unknownE = r.u32();
    p.learning = readFloat(r);
    p.forget = readFloat(r);
    p.sound1 = r.s16();
    p.sound2 = r.s16();
    p.sound3 = r.s16();
    r.skip(8);
    p.enemiesIncUnranked = r.u16();
    p.enemiesExUnranked = r.u16();
    p.unkDA = r.u16();
    p.harTrades = r.u32();
    p.winnings = r.u32();
    p.totalValue = r.u32();
    p.currentHealth = r.s16();
    p.maximumHealth = r.s16();
    p.unkFB = readFloat(r);
    r.skip(8);
    readPalette(r, p.palette, 0, 48);
    p.isPlayer = r.u16();
    p.photoId = r.u16() & 0x3FF;
    if (!r.ok()) return false;

    for (auto& q : p.quotes)
        if (!padded(in, q)) return false;
    return in.ok();
}

bool loadTrn(const Bytes& data, TrnFile& t, std::string* err) {
    auto fail = [&](const char* why) {
        if (err) *err = why;
        return false;
    };
    if (data.size() < 1582) return fail("too small for a tournament");
    Reader r(data);
    t.enemyCount = r.u16();
    if (t.enemyCount == 0 || t.enemyCount >= 256) return fail("bad enemy count");
    t.unknownB = r.u16();
    const uint32_t victoryTexts = r.u32();
    t.bkName = cstr(r, 14);
    t.winningsMultiplier = readFloat(r);
    t.unknownA = r.s32();
    t.registrationFee = r.s32();
    t.assumedInitialValue = r.s32();
    t.tournamentId = r.s32();

    r.seek(300);
    std::vector<uint32_t> offsets(size_t(t.enemyCount) + 1);
    for (auto& o : offsets) o = r.u32();
    if (!r.ok()) return fail("truncated offset list");

    t.enemies.resize(t.enemyCount);
    for (size_t i = 0; i < t.enemyCount; ++i) {
        r.seek(offsets[i]);
        if (!readPilot(r, t.enemies[i])) return fail("bad enemy pilot");
    }
    r.seek(offsets[t.enemyCount]);
    for (auto& loc : t.locales)
        if (!readSprite(r, loc.logo)) return fail("bad logo");
    readPalette(r, t.palette, 128, 40);
    padded(r, t.picFile);
    for (auto& loc : t.locales) {
        padded(r, loc.title);
        padded(r, loc.description);
    }
    if (!r.ok() || r.pos() != victoryTexts) return fail("description block doesn't end at the ending texts");
    for (auto& loc : t.locales)
        for (auto& har : loc.endTexts)
            for (auto& page : har) padded(r, page);
    if (!r.ok()) return fail("truncated ending texts");
    return true;
}

}  // namespace omf
