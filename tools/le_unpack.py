#!/usr/bin/env python3
"""Unpack a 32-bit LE executable (DOS/4GW, PMODE/W) into a flat memory image.

One Must Fall 2097's game code is MASTER.DAT: a small MZ stub with a 32-bit
LE program after it (PMODE/W extender, Watcom C). Ghidra has no LE loader, so
this lays every object out at its link-time base address, applies the
internal fixups, and writes:

  <out>/image.bin     flat image from the lowest object base upward
  <out>/image.txt     object table, entry point, and how to import it

Import image.bin into Ghidra as "Raw Binary", language x86:LE:32:default,
base address = the "image base" printed (re/README.md has the steps).

    python3 -I tools/le_unpack.py /path/to/MASTER.DAT re/output

Output is decompiled-code territory: keep it local (re/output is
git-ignored).
"""
import os
import struct
import sys


def u8(d, o): return d[o]
def u16(d, o): return struct.unpack_from("<H", d, o)[0]
def u32(d, o): return struct.unpack_from("<I", d, o)[0]


def find_le(data):
    if data[:2] != b"MZ":
        raise SystemExit("not an MZ executable")
    off = u32(data, 0x3C)
    if data[off:off + 2] in (b"LE", b"LX"):
        return off
    # PMODE/W stubs don't always set e_lfanew; scan for the signature.
    i = data.find(b"LE\x00\x00")
    if i < 0:
        raise SystemExit("no LE header found")
    return i


def unpack(path, outdir):
    data = open(path, "rb").read()
    le = find_le(data)
    sig = data[le:le + 2]
    page_size = u32(data, le + 0x28)
    last_page = u32(data, le + 0x2C)          # LE: bytes used on the last page
    eip_obj, eip = u32(data, le + 0x18), u32(data, le + 0x1C)
    esp_obj, esp = u32(data, le + 0x20), u32(data, le + 0x24)
    obj_tab, n_obj = le + u32(data, le + 0x40), u32(data, le + 0x44)
    page_map = le + u32(data, le + 0x48)
    fix_page = le + u32(data, le + 0x68)
    fix_rec = le + u32(data, le + 0x6C)
    data_pages = u32(data, le + 0x80)           # from the file start
    n_pages = u32(data, le + 0x14)

    objs = []
    for i in range(n_obj):
        o = obj_tab + i * 24
        vsize, base, flags, pidx, pcnt = struct.unpack_from("<IIIII", data, o)
        objs.append(dict(n=i + 1, vsize=vsize, base=base, flags=flags, pidx=pidx, pcnt=pcnt))

    def page_file_offset(pnum):          # 1-based logical page
        e = page_map + (pnum - 1) * 4
        if sig == b"LE":
            phys = (data[e] << 16) | (data[e + 1] << 8) | data[e + 2]
        else:
            phys = u32(data, e) + 1
        return data_pages + (phys - 1) * page_size

    lo = min(o["base"] for o in objs)
    hi = max(o["base"] + max(o["vsize"], o["pcnt"] * page_size) for o in objs)
    img = bytearray(hi - lo)

    # load pages
    for o in objs:
        for k in range(o["pcnt"]):
            pnum = o["pidx"] + k
            src = page_file_offset(pnum)
            n = last_page if pnum == n_pages else page_size
            chunk = data[src:src + n]
            dst = o["base"] - lo + k * page_size
            img[dst:dst + len(chunk)] = chunk

    # internal fixups (32-bit offsets, 16:32 pointers' offset part, 32-bit
    # self-relative): enough for Ghidra to follow calls and data references
    applied = skipped = 0
    for o in objs:
        for k in range(o["pcnt"]):
            pnum = o["pidx"] + k
            a, b = u32(data, fix_page + (pnum - 1) * 4), u32(data, fix_page + pnum * 4)
            p, end = fix_rec + a, fix_rec + b
            page_va = o["base"] + k * page_size
            while p < end:
                stype, tflags = data[p], data[p + 1]
                p += 2
                if stype & 0x20:
                    cnt = data[p]; p += 1
                    srcoffs = None
                else:
                    srcoffs = [struct.unpack_from("<h", data, p)[0]]; p += 2
                if tflags & 3 != 0:            # imports / entry refs: not used by OMF
                    skipped += 1
                    break
                if tflags & 0x40:
                    tobj = u16(data, p); p += 2
                else:
                    tobj = data[p]; p += 1
                kind = stype & 0x0F
                if kind == 0x02:               # 16-bit selector: no offset
                    toff = 0
                elif tflags & 0x10:
                    toff = u32(data, p); p += 4
                else:
                    toff = u16(data, p); p += 2
                if srcoffs is None:
                    srcoffs = [struct.unpack_from("<h", data, p + 2 * j)[0] for j in range(cnt)]
                    p += 2 * cnt
                if tobj < 1 or tobj > len(objs):
                    skipped += len(srcoffs)
                    continue
                target = objs[tobj - 1]["base"] + toff
                for so in srcoffs:
                    va = page_va + so
                    at = va - lo
                    if not (0 <= at < len(img) - 3):
                        skipped += 1
                        continue
                    if kind in (0x07, 0x06, 0x03):     # 32-bit offset / 16:32 ptr / 16:16 ptr
                        if kind == 0x03:
                            struct.pack_into("<H", img, at, target & 0xFFFF)
                        else:
                            struct.pack_into("<I", img, at, target & 0xFFFFFFFF)
                        applied += 1
                    elif kind == 0x08:                 # 32-bit self-relative
                        struct.pack_into("<I", img, at, (target - (va + 4)) & 0xFFFFFFFF)
                        applied += 1
                    elif kind == 0x05:                 # 16-bit offset
                        struct.pack_into("<H", img, at, target & 0xFFFF)
                        applied += 1
                    else:
                        skipped += 1

    os.makedirs(outdir, exist_ok=True)
    open(os.path.join(outdir, "image.bin"), "wb").write(img)
    entry = objs[eip_obj - 1]["base"] + eip if 0 < eip_obj <= len(objs) else 0
    code = [o for o in objs if o["flags"] & 0x4]
    code_end = max(o["base"] + o["vsize"] for o in code) if code else lo
    lines = [
        f"source       : {path}",
        f"format       : {sig.decode()} at file offset 0x{le:X}, page size {page_size}",
        f"image base   : 0x{lo:08X} (load image.bin here)",
        f"image size   : 0x{len(img):X}",
        f"entry point  : 0x{entry:08X} (object {eip_obj} + 0x{eip:X})",
        f"stack        : object {esp_obj} + 0x{esp:X}",
        f"code end     : 0x{code_end:08X}",
        f"fixups       : {applied} applied, {skipped} skipped",
        "objects      :",
    ]
    for o in objs:
        kind = "code" if o["flags"] & 0x4 else "data"
        lines.append(f"  #{o['n']}  base 0x{o['base']:08X}  size 0x{o['vsize']:06X}  flags 0x{o['flags']:04X} ({kind})"
                     f"  pages {o['pidx']}..{o['pidx'] + o['pcnt'] - 1}")
    lines += ["", "Ghidra: File > Import > image.bin, Format Raw Binary, Language x86:LE:32:default,",
              "Options > Base Address = image base above. Then create a function at the entry",
              "point, mark the code objects executable and run Auto Analyze."]
    open(os.path.join(outdir, "image.txt"), "w").write("\n".join(lines) + "\n")
    print("\n".join(lines[:9 + len(objs)]))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        raise SystemExit(2)
    unpack(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "re/output")
