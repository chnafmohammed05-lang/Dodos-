#!/usr/bin/env python3
"""Decode a DektopOS screenshot back into text using the real 8x8 font.

  tools/screen.py <shot.ppm> [zoom]

The PPM is 2x the OS resolution (640x400).  Each OS character cell is 8x8
pixels, so each cell is a 16x16 block in the image.  Glyphs are matched
against src/font8x8.inc, which means the output is the literal text the
kernel drew.
"""
import re
import sys


def load_font(path="src/font8x8.inc"):
    font = {}
    for line in open(path):
        m = re.match(r"\s*db\s+((?:0x[0-9A-Fa-f]{2},){7}0x[0-9A-Fa-f]{2})\s*;\s*(\d+)", line)
        if not m:
            continue
        rows = [int(b, 16) for b in m.group(1).split(",")]
        font[int(m.group(2))] = rows
    return font


def read_ppm(path):
    data = open(path, "rb").read()
    parts = []
    i = 0
    while len(parts) < 4:
        while data[i : i + 1].isspace():
            i += 1
        if data[i : i + 1] == b"#":
            while data[i : i + 1] not in (b"\n", b""):
                i += 1
            continue
        j = i
        while not data[j : j + 1].isspace():
            j += 1
        parts.append(data[i:j])
        i = j
    i += 1
    w, h, maxv = int(parts[1]), int(parts[2]), int(parts[3])
    return w, h, data[i : i + w * h * 3]


def main():
    path = sys.argv[1]
    zoom = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    font = load_font()
    w, h, px = read_ppm(path)
    sx = w // 320
    sy = h // 200
    cell = 8 * sx

    # invert: 8x8 bitmap -> printable char
    inv = {}
    for code, rows in font.items():
        key = tuple(rows)
        if key not in inv and 32 <= code < 127:
            inv[key] = chr(code)

    out = []
    for row in range(200 // 8):
        line = []
        for col in range(320 // 8):
            bits = []
            for ry in range(8):
                v = 0
                for rx in range(8):
                    ox = (col * 8 + rx) * sx
                    oy = (row * 8 + ry) * sy
                    p = (oy * w + ox) * 3
                    r, g, b = px[p], px[p + 1], px[p + 2]
                    lum = (r * 30 + g * 59 + b * 11) // 100
                    v = (v << 1) | (1 if lum > 90 else 0)
                bits.append(v)
            line.append(inv.get(tuple(bits), "\x00" if any(bits) else " "))
        out.append("".join(line).rstrip())
    while out and not out[-1]:
        out.pop()
    print("\n".join(out))
    print(f"--- {path} ({w}x{h}, cell {cell}) ---")


main()
