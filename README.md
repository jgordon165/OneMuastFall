# OneMuastFall

[![CI-build](https://github.com/jgordon165/OneMuastFall/actions/workflows/ci-build.yml/badge.svg)](https://github.com/jgordon165/OneMuastFall/actions/workflows/ci-build.yml)
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
- **Asset explorer** (F12): browse and play every BK animation and scene,
  every HAR move, photo, sound, song and string.
- Not yet: fighting (HAR physics, moves, AI, the arenas' hazards),
  tournament mode, the other menus, settings, networking.

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
| `--scale N` | window size (default 3 × 320×240) |
| F12 | asset explorer, from anywhere |
| F11 / Alt+Enter | full screen |

In the intro, Esc / Enter / Space go to the menu. In the menu, Up/Down and
Enter; Esc jumps to QUIT. DEMO replays the intro.

The picture is the original's 320×200 shown at 4:3, as on a DOS monitor.

### Asset explorer

Up/Down (or a letter) to pick a file, Enter to open, Esc back.

- **BK**: Left/Right pick an animation, Enter plays it, A plays the whole
  scene, B background on/off, P next palette, S the animation string.
- **AF**: Left/Right pick a move, Enter plays it over an arena, S strings.
- **PIC**: Left/Right pick a photo. **PSM**: Enter plays/stops.
- **SOUNDS.DAT**: Enter plays. **ENGLISH.DAT**: scroll the strings.

## Layout

| | |
|---|---|
| `src/formats/` | decoders for the original files (no SDL; tested on their own) |
| `src/` | the host: window and palette, mixer and music, input, Lua API |
| `scripts/` | the game, in Lua: `core/` (animation scripts, scenes), `scenes/`, `ui/`, `game/` |
| `docs/` | [formats](docs/formats.md), [Lua API](docs/lua-api.md) |
| `re/`, `tools/` | reverse engineering: unpacking `MASTER.DAT` for Ghidra ([re/README.md](re/README.md)) |
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
