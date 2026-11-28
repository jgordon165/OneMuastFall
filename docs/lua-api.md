# Lua API

The C++ host (`src/lua_api.cpp`) gives the game scripts these globals.
Palettes and remap tables are byte strings (768 / 256 bytes, 8-bit RGB);
images are userdata with `:w()`, `:h()`, `:pixel(x, y)`, `:crop(x, y, w, h)`
and `:map(table)` (a copy with each index i replaced by byte i of a
256-byte string). Ids that the
game numbers from 0 (animations, palettes, strings, photos, sounds) are
0-based in the tables too.

## The game: `game`

The host calls `game.init()`, then every frame `game.update(dt_ms)` and
`game.draw()`, and `game.shutdown()` at the end (`scripts/main.lua`).

## Original files: `omf`

| | |
|---|---|
| `omf.bk(name)` | a BK as a table: `background` (image), `palettes[0..]`, `remaps[pal][0..18]`, `sound_table[0..29]`, `anims[id]` = `{ chain_hit, chain_no_hit, repeat_flag, probability, hazard_damage, footer, start_x, start_y, script, extra, coords, sprites }`; or `nil, error` |
| `omf.af(name)` | an AF: the stats, `sound_table`, `moves[id]` = the animation fields plus `move_string`, `damage`, `category`, `successor`... |
| `omf.pic(name)` | photos `[0..]` = `{ is_player, sex, has_photo, palette (48 colours), sprite }` |
| `omf.lang([name])` | ENGLISH.DAT (default) strings `[0..]` = `{ description, text }` |
| `omf.altpals()` | the 11 palettes of ALTPALS.DAT |
| `omf.load_sounds()` | loads SOUNDS.DAT into the mixer; returns `[id] = { rate, length }` |
| `omf.load_fonts()` | loads GRAPHCHR.DAT and CHARSMAL.DAT for `gfx.text` |

A sprite is `{ x, y, w, h, index, missing, img }`.

## Drawing: `gfx` (320 × 200, 8-bit)

| | |
|---|---|
| `clear([c])`, `pset(x,y,c)`, `pget(x,y)`, `fill(x,y,w,h,c)`, `rect(...)`, `line(x0,y0,x1,y1,c)` | |
| `draw(img, x, y [, flip_x, flip_y, opaque, remap, pal_offset, pal_limit, opacity])` | index 0 is transparent unless `opaque`; with a remap string the pixels under the sprite are remapped instead; indices ≤ pal_limit become min(i + pal_offset, pal_limit) (player 2's HAR colours); opacity < 255 dithers |
| `draw_color(img, x, y, flip_x, flip_y, c)` | the sprite's shape in one colour |
| `remap_rect(x, y, w, h, remap [, rounds])` | remaps a box (the menu panels) |
| `text(s, x, y [, c, font, shadow, shadow_dir])` | font 0 = big (8x8), 1 = small (6x6); the shadow falls bottom-right, or top-left with shadow_dir -1; returns the end x |
| `text_width(s [, font])`, `has_fonts()` | |
| `clip(x,y,w,h)`, `unclip()` | |
| `set_base(rgb [, first])`, `base_color(i, r, g, b)` | the scene's base palette |
| `reset_palette()`, `mix(ref, start, end, step)`, `tint(...)`, `darken(step)` | this frame's palette: rebuilt from the base, then tricks applied |
| `color(i)` | r, g, b of this frame's palette |
| `mark(on)` | while on, drawn pixels count as sprite pixels for SMOOTHING SPRITES (`core/player.lua` marks every animated object) |
| `upscale(factor, smoothing, soft, sharpen)` | ADVANCED SETTINGS: factor 1..4, smoothing 0 off / 1 sprites / 2 everything, soft = linear stretch to the window, sharpen 0..3 |
| `screenshot(path)`, `fullscreen()` | screenshots are of the frame as shown (upscaled / sharpened) |

## Sound: `audio`

| | |
|---|---|
| `sound(id [, { volume=0..127, pan=-100..100, pan_end, pitch, channel, priority }])` | a SOUNDS.DAT effect; returns the channel |
| `stop(ch)`, `stop_all()` | |
| `music(name [, loop])` | a PSM from the game folder |
| `stop_music()`, `music_playing()`, `music_volume(0..100)`, `sound_volume(0..100)`, `available()` | |

## Input: `input`

`down(name)`, `pressed(name, ...)` (any of them, this frame), `any()`,
`last()`. Keys by their SDL name in lowercase (`"left"`, `"return"`,
`"escape"`, `"f12"`, `"a"`); pads as `"pad_a"`, `"pad_b"`, `"pad_start"`,
`"pad_up"`...

## The rest: `fs`, `sys`

`fs.mounted()`, `fs.exists(name)`, `fs.list()`, `fs.read(name)` (the game
folder, names in any case). `sys.log(s)`, `sys.ticks()`, `sys.quit()`,
`sys.save(name, s)` / `sys.load(name)` (the user's preferences folder),
`sys.data_path`, `sys.platform`, `sys.headless`.
