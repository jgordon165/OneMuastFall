// AF: one HAR (fighting robot). Stats, then up to 70 moves (each an
// animation plus move data and the input string that triggers it), then the
// sound table.
#pragma once
#include <array>
#include <map>

#include "formats/animation.h"

namespace omf {

struct AfMove {
    Animation ani;
    uint16_t aiFlags = 0;
    uint16_t posConstraint = 0;
    std::array<uint8_t, 8> unknown{};   // bytes 4..11 of the move header
    uint8_t playIfHit = 0;
    uint8_t category = 0;
    uint8_t blockDamage = 0;
    uint8_t blockStun = 0;
    uint8_t successorId = 0;
    uint8_t damage = 0;
    uint8_t throwDuration = 0;
    uint8_t extraStringSelector = 0;
    uint8_t points = 0;
    std::string moveString;   // input, e.g. "K6"
    std::string footer;
};

struct AfFile {
    uint16_t fighterId = 0;
    uint16_t execWindow = 0;
    int32_t endurance = 0;
    uint8_t upwardsJumpFrameLimit = 0;
    uint16_t health = 0;
    int32_t forwardSpeed = 0, reverseSpeed = 0, jumpSpeed = 0, fallSpeed = 0;
    uint8_t version = 0;
    uint8_t aiProjectileYThreshold = 0;
    std::map<int, AfMove> moves;
    std::array<uint8_t, 30> soundTable{};
};

bool loadAf(const Bytes& data, AfFile& out, std::string* err = nullptr);

}  // namespace omf
