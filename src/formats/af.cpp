#include "formats/af.h"

namespace omf {

bool loadAf(const Bytes& data, AfFile& af, std::string* err) {
    auto fail = [&](const char* m) { if (err) *err = m; return false; };
    Reader r(data);
    af.fighterId = r.u16();
    af.execWindow = r.u16();
    af.endurance = r.s32();
    af.upwardsJumpFrameLimit = r.u8();
    af.health = r.u16();
    af.forwardSpeed = r.s32();
    af.reverseSpeed = r.s32();
    af.jumpSpeed = r.s32();
    af.fallSpeed = r.s32();
    af.version = r.u8();
    af.aiProjectileYThreshold = r.u8();
    while (true) {
        uint8_t id = r.u8();
        if (id >= 70 || !r.ok()) break;
        AfMove m;
        if (!readAnimation(r, m.ani)) return fail("bad AF animation");
        m.aiFlags = r.u16();
        m.posConstraint = r.u16();
        r.bytes(m.unknown.data(), m.unknown.size());
        m.playIfHit = r.u8();
        m.category = r.u8();
        m.blockDamage = r.u8();
        m.blockStun = r.u8();
        m.successorId = r.u8();
        m.damage = r.u8();
        m.throwDuration = r.u8();
        m.extraStringSelector = r.u8();
        m.points = r.u8();
        m.moveString = r.fixedStr(21);
        if (!r.paddedStr(m.footer, 512)) return fail("bad AF footer string");
        af.moves[id] = std::move(m);
    }
    r.bytes(af.soundTable.data(), 30);
    if (!r.ok()) return fail("AF truncated");
    std::vector<Animation*> all;
    for (auto& [id, m] : af.moves) all.push_back(&m.ani);
    resolveMissingSprites(all);
    return true;
}

}  // namespace omf
