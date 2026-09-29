#!/usr/bin/env python3
"""Extract label -> runtime address from a NASM listing.

NASM -l lines look like:

    14 000047CD B061                <1>     mov al, 'a'
    34 00003350 00<rep D0h>         <1> wm_windows:    times WM_MAX * WINDOW_SIZE db 0
  i.e. <srcline> <file offset> <bytes> ... <context> <source>

Two wrinkles worth knowing about:

  * A label sitting on a line of its own carries no offset, so the address
    must be taken from the first instruction that follows it.
  * A label attached to a data declaration (a `db`/`dd`/`times` line) does
    carry an offset, and that offset *is* the address.
  * The byte column may itself contain '>' (as in "00<rep D0h>"), so the
    source text is what follows the *last* '>' on the line.
"""
import re
import sys

BASE = 0x10000          # KERNEL_ADDR
lst = sys.argv[1]
want = sys.argv[2:]

CODE = re.compile(r'^\s*\d+\s+([0-9A-Fa-f]{8})\s+[0-9A-Fa-f]')
LABEL = re.compile(r'^\s*([A-Za-z_.$?][\w.$?]*):')

lines = open(lst, encoding='utf-8', errors='replace').read().splitlines()
off = 0
symbols = {}

for i, line in enumerate(lines):
    own = None
    m = CODE.match(line)
    if m:
        own = int(m.group(1), 16)
        off = own
    if '<' not in line:
        continue
    src = line.rsplit('>', 1)[1]
    lm = LABEL.match(src)
    if not lm or lm.group(1) in symbols:
        continue
    if own is not None:
        addr = own
    else:
        addr = off
        for j in range(i + 1, min(i + 6, len(lines))):
            m2 = CODE.match(lines[j])
            if m2:
                addr = int(m2.group(1), 16)
                break
    symbols[lm.group(1)] = BASE + addr

if not want:
    for k in sorted(symbols):
        print(hex(symbols[k]), k)
else:
    for w in want:
        print(hex(symbols[w]), w) if w in symbols else print('0x0 (not found)', w)
