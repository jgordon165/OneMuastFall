#!/usr/bin/env bash
# Import One Must Fall 2097's game code into a local Ghidra project, run
# auto-analysis, and export decompiled C for every function into re/output/.
#
#   GHIDRA_HOME=/path/to/ghidra_11.x re/ghidra_headless.sh /path/to/your/MASTER.DAT
#
# MASTER.DAT is the real game (FILE0001.EXE only loads it): a 32-bit LE
# program under the PMODE/W extender, built with Watcom C. Ghidra has no LE
# loader, so tools/le_unpack.py first lays it out as a flat image with its
# fixups applied, and that is imported as raw 32-bit x86 at its base address.
#
# Output stays in re/ (git-ignored): decompiled original code is reference
# material for writing the port, not something to publish.
set -euo pipefail

EXE="${1:?usage: $0 <MASTER.DAT>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
: "${GHIDRA_HOME:?set GHIDRA_HOME to your Ghidra install}"

mkdir -p "$HERE/ghidra_project" "$HERE/output"
python3 -I "$HERE/../tools/le_unpack.py" "$EXE" "$HERE/output"
BASE="$(sed -n 's/^image base *: *\(0x[0-9A-Fa-f]*\).*/\1/p' "$HERE/output/image.txt")"
ENTRY="$(sed -n 's/^entry point *: *\(0x[0-9A-Fa-f]*\).*/\1/p' "$HERE/output/image.txt")"
CODE_END="$(sed -n 's/^code end *: *\(0x[0-9A-Fa-f]*\).*/\1/p' "$HERE/output/image.txt")"

"$GHIDRA_HOME/support/analyzeHeadless" \
    "$HERE/ghidra_project" omf2097 \
    -import "$HERE/output/image.bin" -overwrite \
    -loader BinaryLoader -loader-baseAddr "$BASE" \
    -processor "x86:LE:32:default" \
    -scriptPath "$HERE/scripts" \
    -preScript SetupImage.java "$ENTRY" "$CODE_END" \
    -postScript ExportDecompiled.java "$HERE/output"

echo "decompiled C written to $HERE/output/"
