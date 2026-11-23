# One Must Fall 2097 file formats

What the port reads, and how. All values are little-endian. The layouts
follow [OpenOMF](https://github.com/omf2097/openomf)'s `src/formats/`
(MIT licence), checked here against the freeware release's files: every BK,
AF and PIC file decodes (`OMF_DATA=<folder> ctest`, 5,149 sprites). The
decoders are in `src/formats/`; the animation-script interpreter is Lua
(`scripts/core/`).

| File | What | Decoder |
|---|---|---|
| `*.BK` | scenes: intro, menu, arenas, cutscenes | `bk.cpp` |
| `FIGHTRn.AF` | the 11 HARs (fighting robots) | `af.cpp` |
| `*.PIC` | pilot photos | `pic.cpp` |
| `SOUNDS.DAT` | every sound effect | `sounds.cpp` |
| `ENGLISH.DAT`, `GERMAN.DAT` | the game's text | `language.cpp` |
| `GRAPHCHR.DAT`, `CHARSMAL.DAT` | the big (8x8) and small (6x6) fonts | `font.cpp` |
| `ALTPALS.DAT` | 11 alternate palettes (HAR colours) | `altpal.cpp` |
| `*.PSM` | music: Epic MegaGames MASI modules | libxmp |
| `MASTER.DAT` | the game program itself (see `re/README.md`) | `tools/le_unpack.py` |
| `FILE0001.EXE` | 16-bit loader that starts MASTER.DAT | — |

Not decoded yet: `*.TRN` (tournaments), `SETUP.CFG`, `SCORES.DAT`,
`RANDOM.DAT`, the `.CHR` save files, `*.REC` recordings.

## Palettes

VGA DAC values, 3 bytes per colour, 6 bits each (0..63). The port widens
them as OpenOMF does, `c << 2 | (c & 0x30) >> 4`, so 63 becomes 255.

Every scene's palette also gets the menu colours at 250..255 (dark blues
for panels, greens for text); index 0 is always black. Index 255 pulses
for the selected menu item.

## Sprites

    u16  length of the RLE data
    s16  x, y      offset from the object's position
    u16  width, height
    u8   index     shared-sprite number within the file
    u8   missing   1 = no data here: reuse the earlier sprite with this index
    ...  RLE data (length bytes), unless missing

The RLE is a stream of 16-bit words; the low two bits are the operation and
the rest (`word >> 2`) its value:

| op | meaning |
|---|---|
| 0 | x = value |
| 2 | y = value |
| 1 | copy `value` pixel bytes from the stream to (x, y) onward; then x = 0 |
| 3 | end |

Pixels never written are transparent (index 0). In PIC files the stored
width and height are one less than the real size.

## Animations (shared by BK and AF)

    s16  start x, start y
    u32  unknown (0)
    u16  collision point count
    u8   sprite count
    u32  × points  two 10-bit signed values: x in bits 0..9, y in 16..25;
                   bits 26..31 are the sprite (frame) the point belongs to
    u16  len, len+1 bytes   the animation string (NUL-terminated)
    u8   extra string count (≤ 10), each: u16 len, len+1 bytes
    sprites

### The animation string

The behaviour of every animation is a script, e.g.

    s1l60A10-bps0bpd63bpn144bpp64m6mp100md5A10-B5000

Frames are separated by `-`. A frame is any number of **tags** (lowercase,
1–3 letters, some followed by a signed number) and ends with the
**sprite letter** (`A` = sprite 0 … `Z` = 25; `Z` usually means none) and
its length in ticks. Tags are matched longest first; a tag that takes no
number is skipped over when a number follows (so `x=-250` is the `x=` tag).
The full tag list is in `scripts/core/script.lua`.

Tags the port implements so far (scenes and fights; `scripts/core/player.lua`
and `scripts/game/har.lua`):

| tag | does |
|---|---|
| `m n` | spawn BK animation n; `mx`/`my` position (relative to this one's start), `mrx`/`mry`/`mm` random position, `mi` instances, `mp` flags |
| `md n` | remove the playing animation n |
| `d n` | jump: to tick n+1 (n ≥ 0) or n ticks before the end |
| `s n` | play sound: the file's sound table entry n − 1 in SOUNDS.DAT; `l` volume (×2), `sb` pan, `sl`/`se` pan sweep, `sf` pitch, `sc` channel, `sp` priority |
| `smo n` | play song n (1 = END.PSM, 2 = MENU.PSM, 3.. = ARENA0..4.PSM); `smo0`/`smf` stop |
| `bps`/`bpn`/`bpd`/`bpp`/`bpb`/`bz` | palette trick over the frame: colours bps..bps+bpn mix toward colour bpd, from bpb to bpp (6-bit amounts), `bz` tints instead |
| `x=`/`y=` | position relative to the start; slides evenly to the next frame's value |
| `x+`/`x-`/`y+`/`y-` | move by |
| `r`/`f` | flip horizontally / vertically |
| `ox`/`oy` | sprite offset correction |
| `bs`/`bf` | opacity at the frame's start / end, drawn dithered |
| `br` | glow (the scene's remap table 3 under the sprite) |
| `x+`/`x-`/`y+`/`y-`, `v` | every tick: move by (x relative to facing); with `v`, set the velocity instead |
| `e`, `ar`, `ac`, `ad`, `g`, `h`, `ab`, `bu`, `cg` | position: stick to the enemy, turn around, face the middle, face the stick, to the floor, stop, pass walls, aim for the middle, land |
| `q`, `n`, `k` | hit window, no hit points, damage multiplier |
| `jl`/`jm`/`jh`/`jj`/`jz`/`jg`/`jn`/`jf`/`jf2` | which moves can chain from this frame |
| `zz`/`zl`/`zm`/`zh`/`zj`/`zp`/`zg` | invulnerable (to everything / low / mid / high / jumping / projectiles / throws) |
| `bj`, `cl`, `cw`, `aw`, `ai`, `ue`, `uh`, `ur`, `bn`, `i`, `aa`, `af`, `cx`, `cp` | fight rules: jump to move, land into the next move, wall tricks, launchers, block rules, air attacks, time freeze, steering, hit pause |

Not done yet: translucency (`bt`, `ub`, `bg`), screen shake (`bl`, `bb`),
the HAR palette flashes (`ptd`/`ptr`/`ptp`, `pa`...), the credits palette
copies (`bpo`, `ba`, `bi`, `bc`, `bd`), walking to a spot (`bm`), and the
rarer fight tags (`mu`, `ua`, `at`, `as`, `b1`/`b2` secrets...).

### Timing

Outside the arenas one tick is 10 ms. Each tick every object first
**advances** (moves its tick on, follows `d` jumps, ends or repeats), then
every object **applies** its frame: on entering a frame its tags run once;
slides and the sprite timer run every tick. An object spawned during a tick
starts on the next one, at its script's tick 1. A scene starts only the
animations it asks for (the intro: 25; the menu: 10 and 11, repeating);
the rest are spawned by `m` tags.

## BK

    u32  file id
    u8   unknown
    u16  background width, height (320 × 200)
    repeated:
      u32  offset of the next entry
      u8   animation id (≥ 50 ends the list)
      u8   null, chain if hit, chain if not hit, repeat
      u16  probability (1 = repeats when spawned)
      u8   hazard damage
      u16  len, len bytes   footer string
      animation
    w × h bytes   background (opaque)
    u8   palette count
    each: 768 bytes palette, 19 × 256 bytes remap tables
    30 bytes   sound table (script sound n → SOUNDS.DAT id + 1)

The remap tables map colour → colour; the menus darken what's under them
with table 4.

## AF

    u16  fighter id         u16  exec window
    s32  endurance          u8   upwards jump frame limit
    u16  health
    s32  forward, reverse, jump and fall speed
    u8   version (0x32)     u8   AI projectile Y threshold
    repeated:
      u8   move id (≥ 70 ends the list)
      animation
      u16  AI flags, position constraint
      u8 × 8  unknown
      u8   play if hit, category, block damage, block stun, successor,
           damage, throw duration, extra string selector, points
      21 bytes  move string (the input that triggers it, e.g. "K6")
      u16  len, len bytes   footer string
    30 bytes   sound table

## PIC

    s32  photo count (< 256)
    at offset 200: u32 × count   photo offsets
    each photo: u8 is player, u16 sex, 48 colours (144 bytes),
                u8 has photo, sprite (size stored −1)

Photos are drawn in the scene's palette (their own 48 colours are the
pilot's HAR colours).

## SOUNDS.DAT

    u32  0
    u32  header size h; (h / 4 − 2) block offsets follow
    each block in order: u16 length, then if length > 0:
         u8 Sound Blaster time constant k, length bytes of unsigned 8-bit PCM

The rate is `1000000 / (256 − k)` Hz. The first block is empty.

## ENGLISH.DAT / GERMAN.DAT

A table of entries — u32 offset, 32-byte description — running until an
offset points past the end of the file; then the strings. Each string runs
to the next one's offset and is XORed with a key that starts at its length
`& 0xFF` and goes up by one for every byte. Strings carry the game's
formatting tags (`{SIZE 8}`, `{COLOR:YELLOW}`...).

## Fonts

224 glyphs, characters 32..255; one byte per row (8 rows for GRAPHCHR,
6 for CHARSMAL), the high bit on the left.

## ALTPALS.DAT

11 palettes of 256 colours (6-bit).
