# OneMuastFall

[![CI-build](https://github.com/jgordon165/OneMuastFall/actions/workflows/ci-build.yml/badge.svg)](https://github.com/jgordon165/OneMuastFall/actions/workflows/ci-build.yml)
[![xbox360](https://github.com/jgordon165/OneMuastFall/actions/workflows/xbox360.yml/badge.svg)](https://github.com/jgordon165/OneMuastFall/actions/workflows/xbox360.yml)
[![code-analysis](https://github.com/jgordon165/OneMuastFall/actions/workflows/code-analysis.yml/badge.svg)](https://github.com/jgordon165/OneMuastFall/actions/workflows/code-analysis.yml)

A Lua recompilation of Diversions Entertainment's *One Must Fall: 2097*
(1994, DOS): a C++ engine (SDL2) that reads the original game's files, with
the game itself written in Lua — the same split as
[Meguarace](https://github.com/jgordon165/Meguarace). The format knowledge
comes from [OpenOMF](https://github.com/omf2097/openomf), the open-source
C remake, and from the original program (`re/`).

**No original game code or data is included.** The engine loads every asset
at runtime from the player's own copy of the game. One Must Fall 2097 has
been freeware since 1999; OpenOMF's [BUILD.md](https://github.com/omf2097/openomf/blob/master/BUILD.md#data-files)
links the official download. Original files are git-ignored as a safety net.

## Status

- **Every original format decodes**: scenes (BK), the 11 HARs (AF), pilot
  photos (PIC), sounds, text, fonts, palettes — see
  [docs/formats.md](docs/formats.md).
- **The animation scripts run**: the per-frame scripting language every
  BK and AF animation is written in (spawning, sounds, music, palette
  flashes, slides) is interpreted in Lua (`scripts/core/`).
- **The intro** plays from INTRO.BK's own scripts, with its sounds and the
  menu music, then the **main menu** (MAIN.BK, MENU.PSM, the original's
  menu panel and items).
- **Fights**: ONE PLAYER GAME (against the computer) and TWO PLAYER GAME.
  All 11 HARs with their real moves, specials and throws, in all 5 arenas;
  blocking, damage, stun, knock-downs, rounds, KOs, victory poses, the HUD.
  How it works: [docs/fighting.md](docs/fighting.md).
- **Asset explorer** (F12): browse and play every BK animation and scene,
  every HAR move, photo, sound, song and string.
- Not yet: the original's HAR select and vs screens, arena hazards,
  tournament mode, the other menus, settings, networking (the list is at
  the end of docs/fighting.md).

## Build

Requires CMake 3.20+ and a C++20 compiler. SDL2, Lua 5.4 and libxmp (the
PSM music) are downloaded and built automatically.

```
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

Windows (Visual Studio 2022): the same commands work from a Developer
prompt, or open the folder in Visual Studio.

## Run

Point it at your One Must Fall 2097 folder (the one with `FILE0001.EXE`,
`INTRO.BK`, `FIGHTR0.AF`...). File names can be in any case.

```
build\Release\onemustfall.exe --data C:\Games\OMF2097
```

| | |
|---|---|
| `--skip-intro` | straight to the main menu |
| `--explorer` | open the asset explorer |
| `--fight` | straight into a fight (`OMF_FIGHT=har1,har2,arena,ai1,ai2`, AI level 0 = human) |
| `--scale N` | window size (default 3 × 320×240) |
| F12 | asset explorer, from anywhere |
| F11 / Alt+Enter | full screen |

In the intro, Esc / Enter / Space go to the menu. In the menu, Up/Down and
Enter; Esc jumps to QUIT. DEMO replays the intro.

### Fighting

ONE PLAYER GAME or TWO PLAYER GAME opens the original's selection screen
(MELEE.BK): each player moves a blinking box over the ten pilot faces
(red player 1, blue player 2) and picks with punch or kick; punch + kick
together takes a pick back. Then the HAR page, the picked HAR animating in
the pilot's colours, and the fight. In a one player game the computer
takes a random other pilot and HAR. Esc goes back a page. GAMEPLAY in the
main menu sets the computer's level, the arena (or random), the rounds and
the game speed. Esc leaves a fight; after it you're back on the HAR page.

The announcer calls out consecutive hits, combos, PERFECT ROUND, VITALITY
and the scrap / destruction bonuses as in the original, and their points
slide into your score under your name (docs/fighting.md). In a one player
game the score carries from fight to fight; when the run ends (a lost
fight, or Esc on the pilot page) a top-20 score goes to the SCOREBOARD for
your name: type it, or pick letters with Up/Down on a pad. SCOREBOARD in
the main menu shows the board (Left/Right: one page per ROUNDS setting);
it's saved as SCORES.DAT in your preferences folder.

| | Player 1 | Player 2 |
|---|---|---|
| move / crouch / jump | arrows (Home, PgUp, End, PgDn diagonals) | W A D X (Q E Z C diagonals) |
| punch | Enter | Left Ctrl |
| kick | Right Shift | Left Shift |
| game pad | d-pad, A/X punch, B/Y kick | — |

Back blocks, down-back blocks low. Special moves are the original's
motions from the AF files (the asset explorer shows each move's input).

The picture is the original's 320×200 shown at 4:3, as on a DOS monitor.

### Advanced settings

CONFIGURATION > ADVANCED SETTINGS changes how the picture is drawn
(saved as `advanced.cfg` in your preferences folder; all off by default):

| Setting | Choices | What it does |
|---|---|---|
| UPSCALE | OFF, 2X, 3X, 4X | draw the frame at 2–4× before it's stretched to the window |
| SMOOTHING | OFF, SPRITES, EVERYTHING | needs UPSCALE: rounds off jagged edges. SPRITES anti-aliases the fighters' and animations' outlines and diagonal colour edges on them, leaving their shading and the backgrounds as drawn; EVERYTHING also smooths colour edges across the whole picture |
| SHARPEN | OFF, LOW, MEDIUM, HIGH | crispens detail (an unsharp mask, applied last) |
| SCREEN | SHARP, SOFT | SOFT blends pixels when stretching to the window, so there's no uneven pixel width at odd window sizes |

`OMF_UPSCALE=factor,smoothing,soft,sharpen` (e.g. `3,1,1,2`) overrides
them for one run. The filters run on the CPU each frame: on a PC, about
2 ms for 3× SPRITES and 4–5 ms for EVERYTHING or 4× sharpening.

### Asset explorer

Up/Down (or a letter) to pick a file, Enter to open, Esc back.

- **BK**: Left/Right pick an animation, Enter plays it, A plays the whole
  scene, B background on/off, P next palette, S the animation string.
- **AF**: Left/Right pick a move, Enter plays it over an arena, S strings.
- **PIC**: Left/Right pick a photo. **PSM**: Enter plays/stops.
- **SOUNDS.DAT**: Enter plays. **ENGLISH.DAT**: scroll the strings.

## Xbox 360

Two console builds, from the same platform layer as Meguarace and Raptua
(`platform/xenon/`), made by the `xbox360` workflow:

| Package | For | Built with |
|---|---|---|
| `onemustfall-xbox360-xex.zip` | a console that runs unsigned code (BadUpdate + FreeMyXe, RGH, JTAG): launch `onemustfall.xex` from the dashboard or Aurora | [xsdk](https://github.com/openpak/x360-sdk) |
| `onemustfall-xbox360-xell.zip` | XeLL (`onemustfall.elf32`) | LibXenon (Free60) |

Copy the `onemustfall` folder to a FAT32 USB stick and your One Must Fall
2097 files into its `data/` folder; the README inside has the details.
Controller 1 is player 1 and runs the menus, controller 2 is player 2: A/X
punch, B/Y kick, START chooses, BACK goes back. QUIT ends the title and goes
to the dashboard, or to the program named in `dashboard.txt` (e.g.
`Usb0:\Aurora\default.xex`). The `aurora/` folder has art for Aurora
(title ID 4F4D4632), drawn by `tools/make_aurora_art.py`. Every push builds
both; a `v*` tag attaches them to the release.

Without a console, `-DOMF_XENON_SIM=ON` builds the same SDL drivers and
layout on Linux, with the pad scripted (`XENON_SIM_PAD`, see
`platform/xenon/xenon_platform_sim.c`); CI runs it on every push.

## Layout

| | |
|---|---|
| `src/formats/` | decoders for the original files (no SDL; tested on their own) |
| `src/` | the host: window and palette, mixer and music, input, Lua API |
| `scripts/` | the game, in Lua: `core/` (animation player, scenes), `game/` (HARs, AI, controls, pilots), `scenes/` (intro, menu, melee, gameplay, arena, explorer), `ui/` |
| `docs/` | [formats](docs/formats.md), [fighting](docs/fighting.md), [Lua API](docs/lua-api.md) |
| `platform/xenon/` | the Xbox 360: SDL drivers, LibXenon / xsdk platform code, the stand-in, package READMEs |
| `re/`, `tools/` | reverse engineering: unpacking `MASTER.DAT` for Ghidra ([re/README.md](re/README.md)); the Aurora art generator |
| `tests/` | format and Lua tests; `OMF_DATA=<folder> ctest` also decodes every original file |

## Testing

```
cd build && ctest -C Release --output-on-failure
OMF_DATA=C:\Games\OMF2097 ctest -C Release --output-on-failure
```

Headless runs for checking a scene frame by frame:

```
onemustfall --data <folder> --frames 600 --shot 300 intro.bmp --press 400 Return
```

## Licence

The port's code is MIT (see [LICENSE](LICENSE)). One Must Fall 2097 is ©
Diversions Entertainment; its files are not part of this repository. Format
documentation derived from OpenOMF (MIT, © Tuomas Virtanen, Andrew Thompson, Hunter and others).
