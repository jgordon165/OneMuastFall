# Tournament mode

TOURNAMENT PLAY is One Must Fall 2097's career mode. You create a pilot,
buy and upgrade robots in the **mechlab**, enter one of four tournaments,
and climb its rankings one opponent at a time. Each win earns money,
which pays for repairs, training and better HARs. Becoming champion
unlocks the next tournament, ending with the World Championship.

This page collects what we know so far and where each fact comes from:

- **[OG]**: checked in the original game. Either decoded from its data files
  with this port's own readers, or found in MASTER.DAT's code or data
  (`re/`, see re/README.md).
- **[OpenOMF]**: taken from OpenOMF's implementation, not yet checked
  against the original.
- **[?]**: unknown, or known to be wrong in OpenOMF.

## Files

| File | What it is | Status |
|---|---|---|
| `NORTH_AM.TRN`, `KATUSHAI.TRN`, `WAR.TRN`, `WORLD.TRN` | a tournament: its pilots, logo, description, fee, endings | decoded: `src/formats/trn.cpp`, `omf.trn()`, asset explorer |
| `*.PIC` of the same names | the tournament pilots' photos | decoded (`omf.pic`) |
| `NORTH_AM.BK` ... `WORLD.BK` | the tournament's cutscenes (arrival, champion) | decoded (BK) |
| `MECHLAB.BK` | the mechlab: background, HARs on the platform, dashboards | decoded (BK) |
| `NEWSROOM.BK` | the news after a fight, and a challenger's challenge | decoded (BK) |
| `PLAYERS.PIC` | the photos a new pilot can pick | decoded |
| `*.CHR` | a pilot's save: the pilot block + the state of every opponent | written by the game; layout below, not decoded yet |

### TRN [OG, after OpenOMF's layout]

- **Header (300 bytes):** enemy count (u16), unknown (u16), offset of
  the ending texts (u32), BK name (14), winnings multiplier (float),
  unknown (u32), registration fee (s32), "assumed initial value" (s32),
  tournament id (s32).
- **Offsets:** at byte 300, one u32 per enemy plus one more, which is the
  offset of the logos.
- **Enemies:** each is a **428-byte pilot block** XOR-encoded with a
  running key (start 428 & 0xFF = 0xAC, +1 per byte), then 10 quotes (one
  per language, u16 length + text). The block holds:
  - the name;
  - wins and losses;
  - rank and HAR (255 = "buys a random HAR with its money");
  - HAR upgrades: arm/leg power and speed, armor, stun resistance;
  - the pilot's POWER/AGILITY/ENDURANCE;
  - money and colours;
  - the requirements for a secret challenger to appear;
  - the AI's attitude, move preferences and learn/forget rates;
  - the enhancement level per HAR;
  - the photo id.
- **Locales:** after the enemies come 10 locale logos (sprites), colours
  128..167, the PIC name, then a title and description per locale. The
  description carries `{WIDTH n}{VMOVE n}{SIZE n}{COLOR n}` layout tags.
- **Ending texts:** 10 locales × 11 HARs × 10 pages, the text shown when
  you win the tournament with that HAR.

The decoder checks that the descriptions end exactly at the ending-text
offset, and all four files pass (`tests/test_formats.cpp`).

### CHR [OpenOMF]

- A 448-byte pilot block (same XOR key 0xAC; the pilot block plus 20 more
  bytes).
- For each of the tournament's enemies, a 68-byte state block: the 43
  "player" bytes (name, wins/losses, rank, HAR, upgrades, money, colours)
  plus unknowns, XOR key (count × 68) & 0xFF.
- The enemies' other fields (AI, quotes, photos) come from the TRN named
  in the pilot block.

## The four tournaments [OG]

| Tournament | Pilots | Fee | Winnings × | "Assumed value" | Top seed | Secret challengers (*1 = fight only once) |
|---|---|---|---|---|---|---|
| North American Open | 14 | 1,500K | 0.85 | 0 | Raven (Pyros) | Iceman*1, Jazzy, Christian, Steel Claw*1 |
| Katushai Challenge | 14 | 3,000K | 1.00 | 15,000K | Jaqouline (buys a HAR) | Angel, Selenna, Devan Shell*1 |
| WAR Invitational | 14 | 5,000K | 1.12 | 30,000K | Nicoli (Shadow) | Eva Earlong, Bethany, Killian |
| World Championship | 35 | 10,000K | 1.35 | 58,000K | Ian Tavares (Nova) | Iceman*1, Angel, Nicoli, Jazzy, Eva Earlong, Bethany, Devan Shell*1 |

Money is shown in thousands: the North American Open's description says
"Registration fee: 1,500K" for a fee field of 1500.

## The career, step by step

1. **New pilot [OpenOMF]:** name, photo (PLAYERS.PIC), colours; starts
   with 2,000K and a Jaguar. Tournament difficulty: ALUMINUM, IRON, STEEL,
   HEAVY METAL.
2. **Pick a tournament [OpenOMF]:** pay its registration fee. Every
   non-secret opponent gets a rank in file order, and you start at the
   bottom (rank = ranked opponents + 1). Opponents with HAR 255 buy a
   random HAR they can afford, and every opponent then spends what's left
   on random upgrades.
3. **ARENA:** you always fight the pilot ranked directly above you
   [OpenOMF]. The VS screen shows his tournament quote.
4. **After the fight [OpenOMF]:**
   - A win swaps your rank with his; a loss swaps you down one. Secret
     challengers have no rank and don't move yours.
   - Money: winnings + bonuses (this fight's score ÷ 1000) − repair cost.
   - Plug, the mechlab's mechanic, gives the financial report (ENGLISH.DAT
     606–621) and comments (587–605).
5. **Going broke [OpenOMF]:** below zero you get a warning. Then Plug
   sells your most valuable upgrade ("I HAD TO SELL A %s"). If you're
   still in debt, the officials throw you out of the tournament.
6. **Secret challengers [OpenOMF]:** after a win, any secret pilot whose
   requirements you meet can appear in the newsroom with a challenge you
   may accept. Requirements can be your rank (exact or at most), the HAR
   you fly, difficulty, vitality %, accuracy %, average damage, a
   scrap/destruction finish, or having beaten a given opponent.
   Destroying one may give you an **enhancement** for your HAR (the
   enhanced moves).
7. **Champion:** at rank 1 there's no one left to fight. The tournament's
   BK plays its cutscene, then the ending text for your HAR, and the next
   tournament opens.

### The economy

| | Values | Source |
|---|---|---|
| HAR prices | Jaguar 20,000, Shadow 36,000, Thorn 26,000, Pyros 28,000, Electra 29,000, Katana 32,000, Shredder 25,000, Flail 30,000, Gargoyle 24,000, Chronos 22,000, Nova 75,000 | **[OG]** MASTER.DAT `0x81d2c`, same as OpenOMF |
| Upgrade base price per HAR | 380, 400, 350, 400, 500, 330, 420, 370, 450, 360, 700 | **[OG]** `0x81fe4` |
| Upgrade level multipliers | 0, 1, 3, 7, 12, 18, 30, 50, 75, 120 | **[OG]** `0x82010` |
| Upgrade price | base × level multiplier × 2 for arm/leg power and speed, × 5 for armor, × 3 for stun resistance | [OpenOMF] |
| Upgrade limits per HAR | not found as a table in the executable | [OpenOMF] values, [?] origin |
| Training (POWER/AGILITY/ENDURANCE) | the original stores price ÷ 10: 5, 8, 12, 18, 24, 30, 45, 60, 80, 110, 150, 250, 400, 700, 1,000, 1,400, 2,000, 2,800, 4,000, 5,500, 7,500, 10,000, 14,000, 20,000, **30,000** | **[OG]** `0x81e04`. OpenOMF has the same values × 10 but stops one level short |
| Trade-in value | 70% of the HAR and its upgrades | [OpenOMF] |
| Winnings | uses the loser's value and money, his winnings, your rank and the tournament multiplier (`calculate_winnings`) | [OpenOMF]; its rank-bonus table matches the original's at `0x82398` **[OG]**, the formula is unchecked |
| Repair cost | OpenOMF calls its own formula "completely bogus" | **[?]**: to trace in MASTER.DAT, from the report at `0x64300` |
| Score multiplier | 50 / 100 / 150 / 200 by the pilot's tournament difficulty (ALUMINUM .. HEAVY METAL) | **[OG]** fight start, `0x30cba`; for the arena to use in tournament fights |

### What upgrades do in a fight [OpenOMF]

- **HP:** HAR HP × (endurance + 25) / 35 × 1.5 (1.1 outside tournaments).
- **Damage:** base × (25 + power) / 35 + 1, then × (arm or leg power + 3)
  × 0.192 depending on the move. Armor divides incoming damage by
  (armor + 2.5) × 0.25.
- **Stun:** stun resistance raises the stun limit and the stun factor.
- **Arm/leg speed** picks a faster animation string (the AF's extra
  strings) for punches and kicks.

## Already in OneMuastFall

- **Fighting:** HARs, moves and the AI fight; damage uses the
  one/two-player formula.
- **Shared screens:** the pilot select, the score and announcer, and the
  scoreboard.
- **Tournament files:** decoded and in the asset explorer (TRN pilots,
  requirements, quotes, logo and description).

## Plan

The VS screen and the newsroom are needed by the one-player game too
(see the progression research), so they come first.

1. **Shared screens:** the VS screen (VS.BK: portraits, quotes, the arena
   choice in two-player games) and the newsroom (NEWSROOM.BK: stories by
   health, the continue prompt). The one-player ladder (random unbeaten
   opponents, Kreissack, the endings) comes with them.
2. **Saves:** decode and write CHR, with a round-trip test against a save
   made by the original. Saves go in the preferences folder.
3. **Mechlab:** MECHLAB.BK with the HAR on the platform and the
   dashboards. NEW (name, photo, colours, difficulty), LOAD, DELETE, NEW
   TOURNAMENT, QUIT. Controller-friendly, with an on-screen keyboard for
   the name on the 360.
4. **The tournament fight loop:** next opponent → VS (quote) → arena with
   tournament stats (HP × 1.5, power/armor damage, speed strings,
   difficulty) → ranks and money → Plug's financial report → back to the
   mechlab.
5. **Economy:** TRAINING COURSES, BUY, SELL, upgrades, repair cost (traced
   in MASTER.DAT first), the going-broke rules.
6. **Challengers:** the newsroom challenge, enhancements, champion
   cutscenes and HAR endings, moving between tournaments.
7. **The rest:** SIM, and the AI using each pilot's attitude, preferences
   and learning.

Open questions to settle in MASTER.DAT as each phase is built: the repair
formula, where the upgrade limits come from, how "fight only once"
pilots are retired, how an unranked challenger's rank works, and CHR's
unknown bytes (20 after the pilot block, 25 in each opponent's 68).
