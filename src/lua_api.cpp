// The Lua API. The C++ side reads the original files (src/formats) and hands
// Lua plain tables; images are userdata (decoded 8-bit pixels), palettes and
// remap tables are byte strings (768 / 256 bytes).
#include "lua_api.h"

extern "C" {
#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"
}

#include <SDL.h>

#include <algorithm>
#include <cstdio>
#include <fstream>
#include <memory>
#include <new>
#include <sstream>

#include "engine.h"
#include "log.h"

#ifdef OMF_XENON_LAYOUT
extern "C" {
#include "xenon_platform.h"
}
#endif
#include "formats/af.h"
#include "formats/altpal.h"
#include "formats/bk.h"
#include "formats/font.h"
#include "formats/language.h"
#include "formats/pic.h"
#include "formats/trn.h"
#include "formats/sounds.h"

namespace {

Engine* E = nullptr;
const char* kImage = "omf.image";

using ImagePtr = std::shared_ptr<omf::Image>;

void pushImage(lua_State* L, omf::Image img) {
    void* mem = lua_newuserdatauv(L, sizeof(ImagePtr), 0);
    new (mem) ImagePtr(std::make_shared<omf::Image>(std::move(img)));
    luaL_setmetatable(L, kImage);
}

omf::Image& checkImage(lua_State* L, int i) {
    auto* p = static_cast<ImagePtr*>(luaL_checkudata(L, i, kImage));
    return **p;
}

int image_gc(lua_State* L) {
    static_cast<ImagePtr*>(luaL_checkudata(L, 1, kImage))->~ImagePtr();
    return 0;
}
int image_w(lua_State* L) { lua_pushinteger(L, checkImage(L, 1).w); return 1; }
int image_h(lua_State* L) { lua_pushinteger(L, checkImage(L, 1).h); return 1; }
int image_pixel(lua_State* L) {
    auto& img = checkImage(L, 1);
    int x = int(luaL_checkinteger(L, 2)), y = int(luaL_checkinteger(L, 3));
    lua_pushinteger(L, (x >= 0 && y >= 0 && x < img.w && y < img.h) ? img.px[size_t(y) * img.w + x] : 0);
    return 1;
}

// img:map(table) -> a copy with every index i replaced by table[i] (a
// 256-byte string): dimmed/greyed copies of the selection portraits.
int image_map(lua_State* L) {
    auto& img = checkImage(L, 1);
    size_t n = 0;
    const char* t = luaL_checklstring(L, 2, &n);
    if (n < 256) return luaL_error(L, "map table must be 256 bytes");
    omf::Image out = img;
    for (auto& v : out.px) v = uint8_t(t[v]);
    pushImage(L, std::move(out));
    return 1;
}
// img:crop(x, y, w, h) -> the part of the image in that box.
int image_crop(lua_State* L) {
    auto& img = checkImage(L, 1);
    int x0 = int(luaL_checkinteger(L, 2)), y0 = int(luaL_checkinteger(L, 3));
    int w = std::max(0, int(luaL_checkinteger(L, 4))), h = std::max(0, int(luaL_checkinteger(L, 5)));
    omf::Image out;
    out.w = w;
    out.h = h;
    out.px.assign(size_t(w) * h, 0);
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
            int sx = x0 + x, sy = y0 + y;
            if (sx >= 0 && sy >= 0 && sx < img.w && sy < img.h) out.px[size_t(y) * w + x] = img.px[size_t(sy) * img.w + sx];
        }
    pushImage(L, std::move(out));
    return 1;
}

void setInt(lua_State* L, const char* k, lua_Integer v) { lua_pushinteger(L, v); lua_setfield(L, -2, k); }
void setStr(lua_State* L, const char* k, const std::string& v) {
    lua_pushlstring(L, v.data(), v.size());
    lua_setfield(L, -2, k);
}
void setBool(lua_State* L, const char* k, bool v) { lua_pushboolean(L, v); lua_setfield(L, -2, k); }
void setNum(lua_State* L, const char* k, double v) { lua_pushnumber(L, v); lua_setfield(L, -2, k); }
void pushBytes(lua_State* L, const uint8_t* d, size_t n) { lua_pushlstring(L, reinterpret_cast<const char*>(d), n); }

void pushSprite(lua_State* L, const omf::Sprite& s) {
    lua_createtable(L, 0, 8);
    setInt(L, "x", s.x);
    setInt(L, "y", s.y);
    setInt(L, "w", s.w);
    setInt(L, "h", s.h);
    setInt(L, "index", s.index);
    setBool(L, "missing", s.missing);
    pushImage(L, omf::decodeSprite(s));
    lua_setfield(L, -2, "img");
}

void pushAnimation(lua_State* L, const omf::Animation& a) {
    // into the table on top of the stack
    setInt(L, "start_x", a.startX);
    setInt(L, "start_y", a.startY);
    setStr(L, "script", a.script);
    lua_createtable(L, int(a.extraStrings.size()), 0);
    for (size_t i = 0; i < a.extraStrings.size(); ++i) {
        lua_pushlstring(L, a.extraStrings[i].data(), a.extraStrings[i].size());
        lua_rawseti(L, -2, lua_Integer(i + 1));
    }
    lua_setfield(L, -2, "extra");
    lua_createtable(L, int(a.coords.size()), 0);
    for (size_t i = 0; i < a.coords.size(); ++i) {
        lua_createtable(L, 0, 3);
        setInt(L, "x", a.coords[i].x);
        setInt(L, "y", a.coords[i].y);
        setInt(L, "frame", a.coords[i].frame);
        lua_rawseti(L, -2, lua_Integer(i + 1));
    }
    lua_setfield(L, -2, "coords");
    lua_createtable(L, int(a.sprites.size()), 0);
    for (size_t i = 0; i < a.sprites.size(); ++i) {
        pushSprite(L, a.sprites[i]);
        lua_rawseti(L, -2, lua_Integer(i + 1));
    }
    lua_setfield(L, -2, "sprites");
}

void pushSoundTable(lua_State* L, const std::array<uint8_t, 30>& t) {
    lua_createtable(L, 30, 0);
    for (int i = 0; i < 30; ++i) {
        lua_pushinteger(L, t[size_t(i)]);
        lua_rawseti(L, -2, i);   // 0-based, as the scripts' s tag counts
    }
    lua_setfield(L, -2, "sound_table");
}

bool readData(lua_State* L, const char* name, omf::Bytes& b) {
    if (E->data.read(name, b)) return true;
    lua_pushnil(L);
    lua_pushfstring(L, "%s: not found in the game folder", name);
    return false;
}

int fail(lua_State* L, const char* name, const std::string& err) {
    lua_pushnil(L);
    lua_pushfstring(L, "%s: %s", name, err.c_str());
    return 2;
}

// ---- omf.* : the original files --------------------------------------------

int omf_bk(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    omf::Bytes b;
    if (!readData(L, name, b)) return 2;
    omf::BkFile bk;
    std::string err;
    if (!omf::loadBk(b, bk, &err)) return fail(L, name, err);
    lua_createtable(L, 0, 8);
    setStr(L, "name", name);
    setInt(L, "file_id", bk.fileId);
    pushImage(L, bk.background);
    lua_setfield(L, -2, "background");
    lua_createtable(L, int(bk.palettes.size()), 0);
    for (size_t i = 0; i < bk.palettes.size(); ++i) {
        pushBytes(L, bk.palettes[i].rgb.data(), 768);
        lua_rawseti(L, -2, lua_Integer(i));   // 0-based like the game's numbering
    }
    lua_setfield(L, -2, "palettes");
    lua_createtable(L, int(bk.remaps.size()), 0);
    for (size_t i = 0; i < bk.remaps.size(); ++i) {
        lua_createtable(L, 19, 0);
        for (size_t t = 0; t < bk.remaps[i].size(); ++t) {
            pushBytes(L, bk.remaps[i][t].data(), 256);
            lua_rawseti(L, -2, lua_Integer(t));
        }
        lua_rawseti(L, -2, lua_Integer(i));
    }
    lua_setfield(L, -2, "remaps");
    setInt(L, "palette_count", lua_Integer(bk.palettes.size()));
    pushSoundTable(L, bk.soundTable);
    lua_createtable(L, 0, int(bk.anims.size()));
    for (const auto& [id, a] : bk.anims) {
        lua_createtable(L, 0, 16);
        setInt(L, "id", id);
        setInt(L, "null", a.null);
        setInt(L, "chain_hit", a.chainHit);
        setInt(L, "chain_no_hit", a.chainNoHit);
        setInt(L, "repeat_flag", a.repeat);
        setInt(L, "probability", a.probability);
        setInt(L, "hazard_damage", a.hazardDamage);
        setStr(L, "footer", a.footer);
        pushAnimation(L, a.ani);
        lua_rawseti(L, -2, id);
    }
    lua_setfield(L, -2, "anims");
    return 1;
}

int omf_af(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    omf::Bytes b;
    if (!readData(L, name, b)) return 2;
    omf::AfFile af;
    std::string err;
    if (!omf::loadAf(b, af, &err)) return fail(L, name, err);
    lua_createtable(L, 0, 16);
    setStr(L, "name", name);
    setInt(L, "fighter_id", af.fighterId);
    setInt(L, "exec_window", af.execWindow);
    setInt(L, "endurance", af.endurance);
    setInt(L, "jump_frame_limit", af.upwardsJumpFrameLimit);
    setInt(L, "health", af.health);
    setInt(L, "forward_speed", af.forwardSpeed);
    setInt(L, "reverse_speed", af.reverseSpeed);
    setInt(L, "jump_speed", af.jumpSpeed);
    setInt(L, "fall_speed", af.fallSpeed);
    setInt(L, "version", af.version);
    setInt(L, "ai_projectile_y", af.aiProjectileYThreshold);
    pushSoundTable(L, af.soundTable);
    lua_createtable(L, 0, int(af.moves.size()));
    for (const auto& [id, m] : af.moves) {
        lua_createtable(L, 0, 24);
        setInt(L, "id", id);
        setInt(L, "ai_flags", m.aiFlags);
        setInt(L, "pos_constraint", m.posConstraint);
        setInt(L, "play_if_hit", m.playIfHit);
        setInt(L, "category", m.category);
        setInt(L, "block_damage", m.blockDamage);
        setInt(L, "block_stun", m.blockStun);
        setInt(L, "successor", m.successorId);
        setInt(L, "damage", m.damage);
        setInt(L, "throw_duration", m.throwDuration);
        setInt(L, "extra_string_selector", m.extraStringSelector);
        setInt(L, "points", m.points);
        setStr(L, "move_string", m.moveString);
        setStr(L, "footer", m.footer);
        pushAnimation(L, m.ani);
        lua_rawseti(L, -2, id);
    }
    lua_setfield(L, -2, "moves");
    return 1;
}

int omf_pic(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    omf::Bytes b;
    if (!readData(L, name, b)) return 2;
    omf::PicFile pic;
    std::string err;
    if (!omf::loadPic(b, pic, &err)) return fail(L, name, err);
    lua_createtable(L, int(pic.photos.size()), 0);
    for (size_t i = 0; i < pic.photos.size(); ++i) {
        const auto& p = pic.photos[i];
        lua_createtable(L, 0, 6);
        setBool(L, "is_player", p.isPlayer);
        setInt(L, "sex", p.sex);
        setBool(L, "has_photo", p.hasPhoto);
        pushBytes(L, p.pal.rgb.data(), 48 * 3);
        lua_setfield(L, -2, "palette");
        pushSprite(L, p.sprite);
        lua_setfield(L, -2, "sprite");
        lua_rawseti(L, -2, lua_Integer(i));   // 0-based
    }
    return 1;
}

// One pilot block (tournament enemy, later the player's save) as a table.
void pushPilot(lua_State* L, const omf::Pilot& p) {
    lua_createtable(L, 0, 80);
    setStr(L, "name", p.name);
    setInt(L, "wins", p.wins);
    setInt(L, "losses", p.losses);
    setInt(L, "rank", p.rank);
    setInt(L, "har", p.harId);   // 255: buys a random HAR with its money
    setInt(L, "arm_power", p.armPower);
    setInt(L, "leg_power", p.legPower);
    setInt(L, "arm_speed", p.armSpeed);
    setInt(L, "leg_speed", p.legSpeed);
    setInt(L, "armor", p.armor);
    setInt(L, "stun_resistance", p.stunResistance);
    setInt(L, "power", p.power);
    setInt(L, "agility", p.agility);
    setInt(L, "endurance", p.endurance);
    setInt(L, "offense", p.offense);
    setInt(L, "defense", p.defense);
    setInt(L, "money", p.money);
    setInt(L, "color1", p.color1);
    setInt(L, "color2", p.color2);
    setInt(L, "color3", p.color3);
    setStr(L, "trn_name", p.trnName);
    setStr(L, "trn_desc", p.trnDesc);
    setStr(L, "trn_image", p.trnImage);
    setNum(L, "trn_rank_money", p.trnRankMoney);
    setNum(L, "trn_winnings_mult", p.trnWinningsMult);
    setInt(L, "pilot_id", p.pilotId);
    setInt(L, "force_arena", p.forceArena);
    setInt(L, "difficulty", p.difficulty);
    setInt(L, "movement", p.movement);
    lua_createtable(L, 11, 0);
    for (int i = 0; i < 11; ++i) {
        lua_pushinteger(L, p.enhancements[size_t(i)]);
        lua_rawseti(L, -2, i);   // by HAR, 0-based
    }
    lua_setfield(L, -2, "enhancements");
    setBool(L, "secret", p.secret);
    setBool(L, "only_fight_once", p.onlyFightOnce);
    lua_createtable(L, 0, 10);
    setInt(L, "rank", p.reqRank);
    setInt(L, "max_rank", p.reqMaxRank);
    setInt(L, "har", p.reqFighter);
    setInt(L, "difficulty", p.reqDifficulty);
    setInt(L, "enemy", p.reqEnemy);
    setInt(L, "vitality", p.reqVitality);
    setInt(L, "accuracy", p.reqAccuracy);
    setInt(L, "avg_damage", p.reqAvgDamage);
    setBool(L, "scrap", p.reqScrap);
    setBool(L, "destroy", p.reqDestroy);
    lua_setfield(L, -2, "requires");
    lua_createtable(L, 0, 5);
    setInt(L, "normal", p.attNormal);
    setInt(L, "hyper", p.attHyper);
    setInt(L, "jump", p.attJump);
    setInt(L, "defensive", p.attDef);
    setInt(L, "sniper", p.attSniper);
    lua_setfield(L, -2, "attitude");
    lua_createtable(L, 0, 10);
    setInt(L, "close", p.apClose);
    setInt(L, "throw", p.apThrow);
    setInt(L, "special", p.apSpecial);
    setInt(L, "jump", p.apJump);
    setInt(L, "high", p.apHigh);
    setInt(L, "low", p.apLow);
    setInt(L, "middle", p.apMiddle);
    setInt(L, "pref_jump", p.prefJump);
    setInt(L, "pref_forward", p.prefFwd);
    setInt(L, "pref_back", p.prefBack);
    lua_setfield(L, -2, "ai");
    setNum(L, "learning", p.learning);
    setNum(L, "forget", p.forget);
    setInt(L, "enemies_inc_unranked", p.enemiesIncUnranked);
    setInt(L, "enemies_ex_unranked", p.enemiesExUnranked);
    setInt(L, "har_trades", p.harTrades);
    setInt(L, "winnings", p.winnings);
    setInt(L, "total_value", p.totalValue);
    setInt(L, "photo", p.photoId);
    setBool(L, "is_player", p.isPlayer != 0);
    pushBytes(L, p.palette.rgb.data(), 48 * 3);
    lua_setfield(L, -2, "palette");
    lua_createtable(L, 10, 0);
    for (int i = 0; i < 10; ++i) {
        lua_pushlstring(L, p.quotes[size_t(i)].data(), p.quotes[size_t(i)].size());
        lua_rawseti(L, -2, i);   // by language, 0 English
    }
    lua_setfield(L, -2, "quotes");
}

// omf.trn(name): a tournament (docs/tournament.md)
int omf_trn(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    omf::Bytes b;
    if (!readData(L, name, b)) return 2;
    omf::TrnFile t;
    std::string err;
    if (!omf::loadTrn(b, t, &err)) return fail(L, name, err);
    lua_createtable(L, 0, 12);
    setStr(L, "bk_name", t.bkName);
    setStr(L, "pic_file", t.picFile);
    setNum(L, "winnings_multiplier", t.winningsMultiplier);
    setInt(L, "registration_fee", t.registrationFee);
    setInt(L, "assumed_initial_value", t.assumedInitialValue);
    setInt(L, "tournament_id", t.tournamentId);
    lua_createtable(L, int(t.enemies.size()), 0);
    for (size_t i = 0; i < t.enemies.size(); ++i) {
        pushPilot(L, t.enemies[i]);
        lua_rawseti(L, -2, lua_Integer(i + 1));
    }
    lua_setfield(L, -2, "enemies");
    lua_createtable(L, 10, 0);
    for (int i = 0; i < 10; ++i) {
        const auto& loc = t.locales[size_t(i)];
        lua_createtable(L, 0, 4);
        setStr(L, "title", loc.title);
        setStr(L, "description", loc.description);
        pushSprite(L, loc.logo);
        lua_setfield(L, -2, "logo");
        lua_createtable(L, 11, 0);
        for (int h = 0; h < 11; ++h) {
            lua_createtable(L, 10, 0);
            for (int pg = 0; pg < 10; ++pg) {
                const auto& txt = loc.endTexts[size_t(h)][size_t(pg)];
                lua_pushlstring(L, txt.data(), txt.size());
                lua_rawseti(L, -2, pg + 1);
            }
            lua_rawseti(L, -2, h);   // by HAR, 0-based
        }
        lua_setfield(L, -2, "endings");
        lua_rawseti(L, -2, i);   // by language, 0 English
    }
    lua_setfield(L, -2, "locales");
    pushBytes(L, t.palette.rgb.data() + 128 * 3, 40 * 3);
    lua_setfield(L, -2, "palette");   // colours 128..167
    return 1;
}

int omf_lang(lua_State* L) {
    const char* name = luaL_optstring(L, 1, "ENGLISH.DAT");
    omf::Bytes b;
    if (!readData(L, name, b)) return 2;
    omf::LanguageFile lf;
    std::string err;
    if (!omf::loadLanguage(b, lf, &err)) return fail(L, name, err);
    lua_createtable(L, int(lf.strings.size()), 0);
    for (size_t i = 0; i < lf.strings.size(); ++i) {
        lua_createtable(L, 0, 2);
        setStr(L, "description", lf.strings[i].description);
        setStr(L, "text", lf.strings[i].text);
        lua_rawseti(L, -2, lua_Integer(i));   // 0-based string ids
    }
    return 1;
}

int omf_altpals(lua_State* L) {
    omf::Bytes b;
    if (!readData(L, "ALTPALS.DAT", b)) return 2;
    omf::AltPalFile ap;
    std::string err;
    if (!omf::loadAltPals(b, ap, &err)) return fail(L, "ALTPALS.DAT", err);
    lua_createtable(L, int(ap.palettes.size()), 0);
    for (size_t i = 0; i < ap.palettes.size(); ++i) {
        pushBytes(L, ap.palettes[i].rgb.data(), 768);
        lua_rawseti(L, -2, lua_Integer(i));
    }
    return 1;
}

int omf_load_sounds(lua_State* L) {
    omf::Bytes b;
    if (!readData(L, "SOUNDS.DAT", b)) return 2;
    omf::SoundsFile sf;
    std::string err;
    if (!omf::loadSounds(b, sf, &err)) return fail(L, "SOUNDS.DAT", err);
    lua_createtable(L, int(sf.sounds.size()), 0);
    for (size_t i = 0; i < sf.sounds.size(); ++i) {
        lua_createtable(L, 0, 2);
        setInt(L, "rate", sf.sounds[i].pcm.empty() ? 0 : sf.sounds[i].rate());
        setInt(L, "length", lua_Integer(sf.sounds[i].pcm.size()));
        lua_rawseti(L, -2, lua_Integer(i));
    }
    E->audio.setSounds(std::move(sf));
    return 1;
}

int omf_load_fonts(lua_State* L) {
    omf::Bytes b;
    omf::FontFile f;
    bool ok = true;
    if (E->data.read("GRAPHCHR.DAT", b) && omf::loadFont(b, 8, f)) E->video.setFont(0, f);
    else ok = false;
    if (E->data.read("CHARSMAL.DAT", b) && omf::loadFont(b, 6, f)) E->video.setFont(1, f);
    else ok = false;
    lua_pushboolean(L, ok);
    return 1;
}

// ---- gfx ---------------------------------------------------------------------

uint8_t col(lua_State* L, int i) { return uint8_t(luaL_checkinteger(L, i) & 0xFF); }

int gfx_clear(lua_State* L) { E->video.clear(uint8_t(luaL_optinteger(L, 1, 0))); return 0; }
int gfx_pset(lua_State* L) {
    E->video.pset(int(luaL_checkinteger(L, 1)), int(luaL_checkinteger(L, 2)), col(L, 3));
    return 0;
}
int gfx_pget(lua_State* L) {
    lua_pushinteger(L, E->video.pget(int(luaL_checkinteger(L, 1)), int(luaL_checkinteger(L, 2))));
    return 1;
}
int gfx_fill(lua_State* L) {
    E->video.fill(int(luaL_checkinteger(L, 1)), int(luaL_checkinteger(L, 2)), int(luaL_checkinteger(L, 3)),
                  int(luaL_checkinteger(L, 4)), col(L, 5));
    return 0;
}
int gfx_rect(lua_State* L) {
    E->video.rect(int(luaL_checkinteger(L, 1)), int(luaL_checkinteger(L, 2)), int(luaL_checkinteger(L, 3)),
                  int(luaL_checkinteger(L, 4)), col(L, 5));
    return 0;
}
int gfx_line(lua_State* L) {
    E->video.line(int(luaL_checkinteger(L, 1)), int(luaL_checkinteger(L, 2)), int(luaL_checkinteger(L, 3)),
                  int(luaL_checkinteger(L, 4)), col(L, 5));
    return 0;
}
// gfx.draw(img, x, y [, flip_x, flip_y, opaque, remap_string, pal_offset, pal_limit, opacity])
int gfx_draw(lua_State* L) {
    auto& img = checkImage(L, 1);
    const uint8_t* remap = nullptr;
    size_t n = 0;
    if (lua_isstring(L, 7)) {
        remap = reinterpret_cast<const uint8_t*>(lua_tolstring(L, 7, &n));
        if (n < 256) remap = nullptr;
    }
    E->video.blit(img, int(luaL_checknumber(L, 2)), int(luaL_checknumber(L, 3)), lua_toboolean(L, 4),
                  lua_toboolean(L, 5), lua_toboolean(L, 6), remap, int(luaL_optinteger(L, 8, 0)),
                  int(luaL_optinteger(L, 9, 255)), int(luaL_optinteger(L, 10, 255)));
    return 0;
}
int gfx_draw_color(lua_State* L) {
    auto& img = checkImage(L, 1);
    E->video.blitColor(img, int(luaL_checknumber(L, 2)), int(luaL_checknumber(L, 3)), lua_toboolean(L, 4),
                       lua_toboolean(L, 5), col(L, 6));
    return 0;
}
int gfx_remap_rect(lua_State* L) {
    size_t n = 0;
    const char* r = luaL_checklstring(L, 5, &n);
    if (n < 256) return luaL_error(L, "remap table must be 256 bytes");
    E->video.remapRect(int(luaL_checkinteger(L, 1)), int(luaL_checkinteger(L, 2)), int(luaL_checkinteger(L, 3)),
                       int(luaL_checkinteger(L, 4)), reinterpret_cast<const uint8_t*>(r),
                       int(luaL_optinteger(L, 6, 1)));
    return 0;
}
int gfx_text(lua_State* L) {
    size_t n = 0;
    const char* s = luaL_checklstring(L, 1, &n);
    int end = E->video.text(std::string(s, n), int(luaL_checkinteger(L, 2)), int(luaL_checkinteger(L, 3)),
                            uint8_t(luaL_optinteger(L, 4, 255)), int(luaL_optinteger(L, 5, 0)),
                            int(luaL_optinteger(L, 6, -1)), int(luaL_optinteger(L, 7, 1)));
    lua_pushinteger(L, end);
    return 1;
}
int gfx_text_width(lua_State* L) {
    size_t n = 0;
    const char* s = luaL_checklstring(L, 1, &n);
    lua_pushinteger(L, E->video.textWidth(std::string(s, n), int(luaL_optinteger(L, 2, 0))));
    return 1;
}
int gfx_has_fonts(lua_State* L) { lua_pushboolean(L, E->video.hasFont(0) && E->video.hasFont(1)); return 1; }
int gfx_clip(lua_State* L) {
    E->video.clip(int(luaL_checkinteger(L, 1)), int(luaL_checkinteger(L, 2)), int(luaL_checkinteger(L, 3)),
                  int(luaL_checkinteger(L, 4)));
    return 0;
}
int gfx_unclip(lua_State*) { E->video.unclip(); return 0; }
// gfx.set_base(rgb_string [, first])  6-bit already widened to 8-bit
int gfx_set_base(lua_State* L) {
    size_t n = 0;
    const char* s = luaL_checklstring(L, 1, &n);
    int first = int(luaL_optinteger(L, 2, 0));
    E->video.setBase(first, int(n / 3), reinterpret_cast<const uint8_t*>(s));
    return 0;
}
int gfx_base_color(lua_State* L) {
    E->video.setBaseColor(int(luaL_checkinteger(L, 1)), col(L, 2), col(L, 3), col(L, 4));
    return 0;
}
int gfx_reset_palette(lua_State*) { E->video.resetPalette(); return 0; }
int gfx_mix(lua_State* L) {
    E->video.mixRange(int(luaL_checkinteger(L, 1)), int(luaL_checkinteger(L, 2)), int(luaL_checkinteger(L, 3)),
                      int(luaL_checkinteger(L, 4)));
    return 0;
}
int gfx_tint(lua_State* L) {
    E->video.tintRange(int(luaL_checkinteger(L, 1)), int(luaL_checkinteger(L, 2)), int(luaL_checkinteger(L, 3)),
                       int(luaL_checkinteger(L, 4)));
    return 0;
}
int gfx_darken(lua_State* L) { E->video.darken(int(luaL_checkinteger(L, 1))); return 0; }
// gfx.mark(on): pixels drawn while on are sprite pixels for the upscaler
int gfx_mark(lua_State* L) { E->video.setMarking(lua_toboolean(L, 1)); return 0; }
// gfx.upscale(factor, smoothing, soft, sharpen): factor 1..4, smoothing 0
// off / 1 sprites / 2 everything, soft = linear filtering to the window,
// sharpen 0 off .. 3 strong
int gfx_upscale(lua_State* L) {
    E->video.setUpscale(int(luaL_optinteger(L, 1, 1)), int(luaL_optinteger(L, 2, 0)), lua_toboolean(L, 3),
                        int(luaL_optinteger(L, 4, 0)));
    return 0;
}
int gfx_color(lua_State* L) {
    int i = int(luaL_checkinteger(L, 1)) & 0xFF;
    auto& w = E->video.work();
    lua_pushinteger(L, w[size_t(i * 3)]);
    lua_pushinteger(L, w[size_t(i * 3 + 1)]);
    lua_pushinteger(L, w[size_t(i * 3 + 2)]);
    return 3;
}
int gfx_screenshot(lua_State* L) {
    E->video.present();
    lua_pushboolean(L, E->video.screenshot(luaL_checkstring(L, 1)));
    return 1;
}
int gfx_fullscreen(lua_State*) { E->video.toggleFullscreen(); return 0; }

// ---- audio ---------------------------------------------------------------------

int audio_sound(lua_State* L) {
    int id = int(luaL_checkinteger(L, 1));
    Audio::Opts o;
    if (lua_istable(L, 2)) {
        auto geti = [&](const char* k, int& dst) {
            lua_getfield(L, 2, k);
            if (lua_isnumber(L, -1)) dst = int(lua_tointeger(L, -1));
            lua_pop(L, 1);
        };
        geti("volume", o.volume);
        geti("pan", o.pan);
        geti("pitch", o.pitch);
        geti("channel", o.channel);
        geti("priority", o.priority);
        lua_getfield(L, 2, "pan_end");
        if (lua_isnumber(L, -1)) { o.panEnd = int(lua_tointeger(L, -1)); o.sweep = true; }
        lua_pop(L, 1);
    }
    lua_pushinteger(L, E->audio.play(id, o));
    return 1;
}
int audio_stop(lua_State* L) { E->audio.stop(int(luaL_checkinteger(L, 1))); return 0; }
int audio_stop_all(lua_State*) { E->audio.stopAll(); return 0; }
int audio_music(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    bool loop = lua_isnoneornil(L, 2) ? true : lua_toboolean(L, 2);
    omf::Bytes b;
    lua_pushboolean(L, E->data.read(name, b) && E->audio.playMusic(b, loop));
    return 1;
}
int audio_stop_music(lua_State*) { E->audio.stopMusic(); return 0; }
int audio_music_playing(lua_State* L) { lua_pushboolean(L, E->audio.musicPlaying()); return 1; }
int audio_music_volume(lua_State* L) { E->audio.setMusicVolume(int(luaL_checkinteger(L, 1))); return 0; }
int audio_sound_volume(lua_State* L) { E->audio.setSoundVolume(int(luaL_checkinteger(L, 1))); return 0; }
int audio_available(lua_State* L) { lua_pushboolean(L, E->audio.available()); return 1; }

// ---- input -----------------------------------------------------------------------

int input_down(lua_State* L) { lua_pushboolean(L, E->input.down(luaL_checkstring(L, 1))); return 1; }
int input_pressed(lua_State* L) {
    // any of the names given
    int n = lua_gettop(L);
    for (int i = 1; i <= n; ++i)
        if (E->input.pressed(luaL_checkstring(L, i))) { lua_pushboolean(L, 1); return 1; }
    lua_pushboolean(L, 0);
    return 1;
}
int input_any(lua_State* L) { lua_pushboolean(L, E->input.any()); return 1; }
int input_last(lua_State* L) { lua_pushstring(L, E->input.last().c_str()); return 1; }

// ---- fs / sys ----------------------------------------------------------------------

int fs_mounted(lua_State* L) { lua_pushboolean(L, E->data.mounted()); return 1; }
int fs_exists(lua_State* L) { lua_pushboolean(L, E->data.exists(luaL_checkstring(L, 1))); return 1; }
int fs_list(lua_State* L) {
    const auto& l = E->data.list();
    lua_createtable(L, int(l.size()), 0);
    for (size_t i = 0; i < l.size(); ++i) {
        lua_createtable(L, 0, 2);
        setStr(L, "name", l[i].name);
        setInt(L, "size", lua_Integer(l[i].size));
        lua_rawseti(L, -2, lua_Integer(i + 1));
    }
    return 1;
}
int fs_read(lua_State* L) {
    omf::Bytes b;
    if (!E->data.read(luaL_checkstring(L, 1), b)) { lua_pushnil(L); return 1; }
    pushBytes(L, b.data(), b.size());
    return 1;
}

std::string prefPath() {
    char* p = SDL_GetPrefPath("OneMuastFall", "OneMuastFall");
    std::string s = p ? p : "./";
    SDL_free(p);
    return s;
}
int sys_log(lua_State* L) { omfLog(luaL_checkstring(L, 1)); return 0; }
int sys_ticks(lua_State* L) { lua_pushinteger(L, lua_Integer(SDL_GetTicks64())); return 1; }
int sys_quit(lua_State*) { E->quit = true; return 0; }
int sys_save(lua_State* L) {
    std::string name = luaL_checkstring(L, 1);
    size_t n = 0;
    const char* s = luaL_checklstring(L, 2, &n);
    std::ofstream f(prefPath() + name, std::ios::binary);
    f.write(s, std::streamsize(n));
    lua_pushboolean(L, bool(f));
    return 1;
}
int sys_load(lua_State* L) {
    std::ifstream f(prefPath() + luaL_checkstring(L, 1), std::ios::binary);
    if (!f) { lua_pushnil(L); return 1; }
    std::stringstream ss;
    ss << f.rdbuf();
    std::string s = ss.str();
    lua_pushlstring(L, s.data(), s.size());
    return 1;
}

void lib(lua_State* L, const char* name, const luaL_Reg* fns) {
    lua_newtable(L);
    luaL_setfuncs(L, fns, 0);
    lua_setglobal(L, name);
}

}  // namespace

void registerLuaApi(lua_State* L, Engine& e) {
    E = &e;

    luaL_newmetatable(L, kImage);
    static const luaL_Reg imgm[] = {{"w", image_w}, {"h", image_h}, {"pixel", image_pixel}, {"map", image_map}, {"crop", image_crop}, {nullptr, nullptr}};
    lua_newtable(L);
    luaL_setfuncs(L, imgm, 0);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, image_gc);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1);

    static const luaL_Reg omfl[] = {{"bk", omf_bk}, {"af", omf_af}, {"pic", omf_pic}, {"trn", omf_trn}, {"lang", omf_lang},
                                    {"altpals", omf_altpals}, {"load_sounds", omf_load_sounds},
                                    {"load_fonts", omf_load_fonts}, {nullptr, nullptr}};
    static const luaL_Reg gfxl[] = {
        {"clear", gfx_clear}, {"pset", gfx_pset}, {"pget", gfx_pget}, {"fill", gfx_fill}, {"rect", gfx_rect},
        {"line", gfx_line}, {"draw", gfx_draw}, {"draw_color", gfx_draw_color}, {"remap_rect", gfx_remap_rect}, {"text", gfx_text},
        {"text_width", gfx_text_width}, {"has_fonts", gfx_has_fonts}, {"clip", gfx_clip}, {"unclip", gfx_unclip},
        {"set_base", gfx_set_base}, {"base_color", gfx_base_color}, {"reset_palette", gfx_reset_palette},
        {"mix", gfx_mix}, {"tint", gfx_tint}, {"darken", gfx_darken}, {"mark", gfx_mark}, {"upscale", gfx_upscale}, {"color", gfx_color},
        {"screenshot", gfx_screenshot}, {"fullscreen", gfx_fullscreen}, {nullptr, nullptr}};
    static const luaL_Reg audiol[] = {{"sound", audio_sound}, {"stop", audio_stop}, {"stop_all", audio_stop_all},
                                      {"music", audio_music}, {"stop_music", audio_stop_music},
                                      {"music_playing", audio_music_playing}, {"music_volume", audio_music_volume},
                                      {"sound_volume", audio_sound_volume}, {"available", audio_available},
                                      {nullptr, nullptr}};
    static const luaL_Reg inputl[] = {{"down", input_down}, {"pressed", input_pressed}, {"any", input_any},
                                      {"last", input_last}, {nullptr, nullptr}};
    static const luaL_Reg fsl[] = {{"mounted", fs_mounted}, {"exists", fs_exists}, {"list", fs_list},
                                   {"read", fs_read}, {nullptr, nullptr}};
    static const luaL_Reg sysl[] = {{"log", sys_log}, {"ticks", sys_ticks}, {"quit", sys_quit},
                                    {"save", sys_save}, {"load", sys_load}, {nullptr, nullptr}};
    lib(L, "omf", omfl);
    lib(L, "gfx", gfxl);
    lib(L, "audio", audiol);
    lib(L, "input", inputl);
    lib(L, "fs", fsl);
    lib(L, "sys", sysl);

    lua_getglobal(L, "sys");
    setStr(L, "data_path", e.dataArg);
#ifdef OMF_XENON_LAYOUT
    // "xenon" on the Xbox 360: controllers only, no keyboard; can_exit is
    // false on the XeLL build, which has no dashboard to go back to.
    setStr(L, "platform", "xenon");
    setBool(L, "can_exit", xp_can_exit() != 0);
#else
    setStr(L, "platform", SDL_GetPlatform());
    setBool(L, "can_exit", true);
#endif
    setBool(L, "headless", e.video.headless());
    setBool(L, "skip_intro", e.skipIntro);
    lua_pop(L, 1);
    lua_getglobal(L, "gfx");
    setInt(L, "width", Video::W);
    setInt(L, "height", Video::H);
    lua_pop(L, 1);
}
