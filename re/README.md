# Reverse engineering workflow

Everything produced here (the unpacked image, the Ghidra project,
decompiled C) is **git-ignored**. It's reference material for writing the
port, not part of it. The port's own code in `src/` and `scripts/` is
written fresh from what we learn, and from OpenOMF's documentation of the
formats (MIT).

## 1. Which file is the game

```
python3 -I tools/identify_exe.py /path/to/OMF2097/FILE0001.EXE
python3 -I tools/identify_exe.py /path/to/OMF2097/MASTER.DAT
```

| File | What it is |
|---|---|
| `OMF.EXE` | tiny launcher (starts `SETUP.EXE -megaload`) |
| `FILE0001.EXE` | 16-bit real-mode loader (Watcom C) |
| `MASTER.DAT` | **the game**: an MZ stub with a 32-bit LE program behind it at 0x2090, PMODE/W extender, Watcom C/C++32 |
| `SETUP.EXE` | sound card / controls setup (Borland C, PMODE) |
| `NET*.EXE` | the modem / IPX network launchers |

## 2. Unpack MASTER.DAT

Ghidra has no LE loader, so `tools/le_unpack.py` lays the program out as
one flat image at its link addresses and applies its internal fixups:

```
python3 -I tools/le_unpack.py /path/to/OMF2097/MASTER.DAT re/output
```

On the freeware release: two objects, code at 0x00010000 (0x6337A bytes)
and data at 0x00080000; entry point 0x0006C5BC (Watcom's start-up, a `jmp`
over its copyright string); 11,401 fixups. The data object holds the file
names the game opens (`intro.bk`, `fightr0.af`, `menu.psm`...), which is
where to start following the loaders.

## 3. Decompile

```
GHIDRA_HOME=~/ghidra_11.x re/ghidra_headless.sh /path/to/OMF2097/MASTER.DAT
```

Runs the unpacker, imports the image as raw x86 32-bit at its base,
splits it into code and data (`re/scripts/SetupImage.java`), starts at the
entry point, analyses, and writes `re/output/all_functions.c` and
`functions.tsv` (`ExportDecompiled.java`).

By hand instead: File > Import `re/output/image.bin`, format Raw Binary,
language `x86:LE:32:default`, base address from `re/output/image.txt`;
then disassemble at the entry point and Auto Analyze.

## 4. Map subsystems, then rewrite

1. **File access**: the data strings name every file; their references lead
   to each loader (they match the layouts in `docs/formats.md`).
2. **Formats**: confirm with the asset explorer (F12), then decode in
   `src/formats/`.
3. **Game logic**: the animation tags, HAR physics and AI, the tournament,
   menus and scoring become Lua modules under `scripts/`, written from
   notes on the decompiled behaviour and OpenOMF's findings rather than
   translated line by line.

Tools worth having alongside: DOSBox-X with its debugger (watch memory
while the real game runs: the LE objects load at the addresses above), and
a hex editor.
