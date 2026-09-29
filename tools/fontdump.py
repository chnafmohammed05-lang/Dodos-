#!/usr/bin/env python3
"""dump an .inc of 8x8 font glyphs as ascii art: tools/fontdump.py"""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "src/font8x8.inc"
rows = {}
pat = re.compile(r"db ([0-9A-Fa-fx,]+)")
for line in open(path):
    m = pat.search(line)
    if not m:
        continue
    code = len(rows) if 32 <= len(rows) < 128 else None
    data = [int(x, 16) for x in m.group(1).split(",")]
    rows[len(rows)] = data
print("glyphs:", len(rows))
for start in range(32, 128, 16):
    for y in range(8):
        line = ""
        for c in range(start, start + 16):
            b = rows[c][y]
            line += "".join("#" if b & (0x80 >> x) else "." for x in range(8)) + " "
        print(line)
    print("  " + "  ".join(repr(chr(c))[1:-1] for c in range(start, start + 16)))
    print()
