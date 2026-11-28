// Tournament files (*.TRN) and the pilot block they're made of. The same
// 428-byte pilot block (XOR-encoded) is the heart of a tournament save
// (*.CHR) too. Layout after OpenOMF's formats/tournament.c and pilot.c;
// see docs/tournament.md.
#pragma once
#include <array>
#include <string>
#include <vector>

#include "formats/sprite.h"

namespace omf {

// One pilot: a tournament opponent, or the player in a save.
struct Pilot {
    uint32_t unknownA = 0;
    // the part a save shares with the player (43 bytes)
    std::string name;               // 18 bytes
    uint16_t wins = 0, losses = 0;
    uint8_t rank = 0, harId = 0;
    uint8_t armPower = 0, legPower = 0, armSpeed = 0, legSpeed = 0, armor = 0, stunResistance = 0;
    uint8_t agility = 0, power = 0, endurance = 0;
    uint16_t offense = 0, defense = 0;
    int32_t money = 0;
    uint8_t color1 = 0, color2 = 0, color3 = 0;   // primary, secondary, tertiary
    // tournament
    std::string trnName, trnDesc, trnImage;       // 13, 31, 13 bytes
    float trnRankMoney = 0, trnWinningsMult = 0;
    uint8_t pilotId = 0, unknownK = 0;
    uint16_t forceArena = 0;
    uint8_t difficulty = 0;
    uint8_t movement = 0;
    std::array<uint8_t, 11> enhancements{};       // per HAR
    bool secret = false, onlyFightOnce = false;
    // requirements for an unranked challenger to appear
    uint8_t reqRank = 0, reqMaxRank = 0, reqFighter = 0, reqDifficulty = 0, reqEnemy = 0;
    uint8_t reqVitality = 0, reqAccuracy = 0, reqAvgDamage = 0;
    bool reqScrap = false, reqDestroy = false;
    // AI attitude and preferences
    uint8_t attNormal = 0, attHyper = 0, attJump = 0, attDef = 0, attSniper = 0;
    int16_t apClose = 0, apThrow = 0, apSpecial = 0, apJump = 0, apHigh = 0, apLow = 0, apMiddle = 0;
    int16_t prefJump = 0, prefFwd = 0, prefBack = 0;
    uint32_t unknownE = 0;
    float learning = 0, forget = 0;
    int16_t sound1 = 0, sound2 = 0, sound3 = 0;
    uint16_t enemiesIncUnranked = 0, enemiesExUnranked = 0, unkDA = 0;
    uint32_t harTrades = 0, winnings = 0, totalValue = 0;
    int16_t currentHealth = 0, maximumHealth = 0;
    float unkFB = 0;
    Palette palette;                              // 0..47
    uint16_t isPlayer = 0, photoId = 0;
    // after the block: a quote per language
    std::array<std::string, 10> quotes;
};

constexpr size_t kPilotBlock = 428;

// The XOR-encoded block (key 428 & 0xFF, +1 per byte), then the quotes.
bool readPilot(Reader& r, Pilot& p);

struct TrnLocale {
    Sprite logo;
    std::string title, description;
    // ending texts: 11 HARs x 10 pages
    std::array<std::array<std::string, 10>, 11> endTexts;
};

struct TrnFile {
    uint16_t enemyCount = 0, unknownB = 0;
    std::string bkName;             // the tournament's own BK (its cutscenes)
    float winningsMultiplier = 0;
    int32_t unknownA = 0, registrationFee = 0, assumedInitialValue = 0, tournamentId = 0;
    std::vector<Pilot> enemies;
    std::array<TrnLocale, 10> locales;   // 0 English, 1 German, ...
    Palette palette;                     // 128..167
    std::string picFile;
};

bool loadTrn(const Bytes& data, TrnFile& out, std::string* err = nullptr);

}  // namespace omf
