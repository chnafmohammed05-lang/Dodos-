#!/usr/bin/env python3
"""
headless test harness for the OS image.

  tools/drive.py <image> <script.txt> [outdir]

Script commands (one per line, '#' comments):
  wait <ms>                 sleep
  key <qcode>               press+release
  hold <qcode> / release <qcode>
  type "text"              type ascii text
  move <x> <y>              move the mouse to absolute screen coords
  click <left|right|middle>
  dblclick <left|right>     two clicks fast
  drag <x1> <y1> <x2> <y2>  press, move, release
  shot <name>               screenshot -> <outdir>/<name>.ppm + ascii art
  log <name>                dump the serial log
"""
import json
import os
import socket
import subprocess
import sys
import time

PAL = [
    (0, 0, 0), (45, 45, 55), (105, 105, 115), (170, 170, 180), (240, 244, 255),
    (16, 26, 64), (40, 90, 220), (0, 170, 170), (40, 180, 60), (190, 240, 60),
    (140, 85, 30), (255, 205, 40), (255, 140, 30), (225, 45, 45), (255, 110, 170),
    (130, 90, 220),
]
CH = [" ", ".", "-", ":", "=", "+", "*", "#", "%", "@", "@", "#", "%", "$", "&", "@"]

KEYMAP = {c: "spc" for c in " "}
KEYMAP["\n"] = "ret"
KEYMAP["\t"] = "tab"
KEYMAP["\b"] = "backspace"


def qcode(ch):
    if ch in KEYMAP:
        return KEYMAP[ch]
    if ch.isdigit():
        return ch
    if ch.isalpha():
        return ch
    if ch in "-_[]\\;',./+=<>*&^%$#@!~`":
        return ch
    return None


class Qmp:
    def __init__(self, path):
        self.s = socket.socket(socket.AF_UNIX)
        for _ in range(100):
            try:
                self.s.connect(path)
                break
            except OSError:
                time.sleep(0.05)
        self.f = self.s.makefile("rwb")
        self.f.readline()
        self.cmd("qmp_capabilities")

    def hmp(self, line):
        """Run a human-monitor command.  QMP input-send-event is not delivered
        to the guest with -display none, but the HMP input commands are."""
        return self.cmd("human-monitor-command", **{"command-line": line})

    def cmd(self, name, **args):
        req = {"execute": name}
        if args:
            req["arguments"] = args
        self.f.write((json.dumps(req) + "\n").encode())
        self.f.flush()
        while True:
            line = self.f.readline()
            if not line:
                raise RuntimeError("qmp died")
            r = json.loads(line)
            if "event" in r:
                continue
            if "error" in r:
                raise RuntimeError("qmp error: %s" % r)
            return r


def key_event(qc, down):
    return {"type": "key", "data": {"down": down, "key": {"type": "qcode", "data": qc}}}


def mouse_btn(btn, down):
    return {"type": "btn", "data": {"down": down, "button": btn}}


BTN = {"left": 1, "middle": 2, "right": 3}
LETTERS = "abcdefghijklmnopqrstuvwxyz"
HMP_KEYS = {c: c for c in LETTERS}
# QEMU's sendkey takes a plain key name, so capitals need an explicit shift.
HMP_KEYS.update({c.upper(): "shift-" + c for c in LETTERS})
HMP_KEYS.update({"0": "0", "1": "1", "2": "2", "3": "3", "4": "4",
                 "5": "5", "6": "6", "7": "7", "8": "8", "9": "9",
                 " ": "spc", "\n": "ret", ".": "dot", ",": "comma",
                 "-": "minus", "/": "slash", "=": "equal", "\t": "tab"})


def mouse_rel(dx, dy):
    ev = []
    if dx:
        ev.append({"type": "rel", "data": {"axis": "x", "value": dx}})
    if dy:
        ev.append({"type": "rel", "data": {"axis": "y", "value": dy}})
    return ev


def read_ppm(path):
    with open(path, "rb") as f:
        data = f.read()
    # P6 with possible comments
    fields, i = [], 2
    while len(fields) < 3:
        while i < len(data) and data[i : i + 1].isspace():
            i += 1
        if data[i : i + 1] == b"#":
            while data[i : i + 1] not in (b"\n", b""):
                i += 1
            continue
        j = i
        while j < len(data) and not data[j : j + 1].isspace():
            j += 1
        fields.append(int(data[i:j]))
        i = j
    i += 1
    w, h = fields[0], fields[1]
    return w, h, data[i : i + w * h * 3]


def nearest(r, g, b):
    best, bd = 0, 1 << 30
    for idx, (pr, pg, pb) in enumerate(PAL):
        d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
        if d < bd:
            bd, best = d, idx
    return best


def art(path, zoom=4, x0=0, y0=0, w=320, h=200, label=""):
    W, H, px = read_ppm(path)
    w = min(w, W - x0)
    h = min(h, H - y0)
    print("--- %s (%dx%d @%dx%d) ---" % (label or path, w, h, zoom, zoom))
    if zoom <= 1:
        for y in range(y0, y0 + h):
            line = ""
            for x in range(x0, x0 + w):
                o = (y * W + x) * 3
                c = nearest(px[o], px[o + 1], px[o + 2])
                line += CH[c] if c < 16 else " "
            print(line)
        return
    for y in range(y0, y0 + h, zoom):
        line = ""
        for x in range(x0, x0 + w, zoom):
            rs = gs = bs = n = 0
            for dy in range(zoom):
                for dx in range(zoom):
                    xx, yy = x + dx, y + dy
                    if xx < W and yy < H:
                        o = (yy * W + xx) * 3
                        rs += px[o]
                        gs += px[o + 1]
                        bs += px[o + 2]
                        n += 1
            r, g, b = rs // n, gs // n, bs // n
            lum = (r * 3 + g * 6 + b) // 10
            if lum > 205 and max(r, g, b) - min(r, g, b) < 40:
                line += " "
            else:
                c = nearest(r, g, b)
                line += CH[c] if c < 16 else "#"
        print(line)


def main():
    img, script = sys.argv[1], sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else "shots"
    os.makedirs(out, exist_ok=True)
    sock = "/tmp/opencode/qmp-%d.sock" % os.getpid()
    if os.path.exists(sock):
        os.unlink(sock)
    serial = os.path.join(out, "serial.log")
    sf = open(serial, "wb")
    qemu = subprocess.Popen(
        ["qemu-system-i386", "-m", "32", "-drive", "file=%s,format=raw,if=floppy" % img,
         "-display", "none", "-vga", "std", "-rtc", "base=localtime",
         "-qmp", "unix:%s,server,nowait" % sock, "-serial", "file:%s" % serial, "-no-reboot"],
        stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    try:
        q = Qmp(sock)
        state = {"x": 160, "y": 100}
        held = set()
        for raw in open(script):
            line = raw.split("#")[0].strip()
            if not line:
                continue
            parts = line.split(None, 1)
            cmd = parts[0]
            arg = parts[1] if len(parts) > 1 else ""
            if cmd == "wait":
                time.sleep(int(arg) / 1000.0)
            elif cmd == "key":
                q.hmp("sendkey %s" % arg)
                time.sleep(0.06)
            elif cmd == "type":
                for ch in arg:
                    if ch == '"':
                        continue
                    kn = HMP_KEYS.get(ch)
                    if not kn:
                        continue
                    q.hmp("sendkey %s" % kn)
                    time.sleep(0.04)
            elif cmd == "move":
                x, y = (int(v) for v in arg.split())
                q.hmp("mouse_move %d %d" % (x * 2, y * 2))
                state["x"], state["y"] = x, y
                time.sleep(0.08)
            elif cmd == "click":
                btn = BTN.get(arg, 1)
                if arg != "left":
                    q.hmp("sendkey shift")
                    q.hmp("mouse_button %d" % btn)
                    q.hmp("mouse_button 0")
                    q.hmp("sendkey shift")
                else:
                    q.hmp("mouse_button %d" % btn)
                    time.sleep(0.08)
                    q.hmp("mouse_button 0")
                time.sleep(0.08)
            elif cmd == "dblclick":
                for _ in range(2):
                    q.hmp("mouse_button %d" % BTN.get(arg, 1))
                    time.sleep(0.05)
                    q.hmp("mouse_button 0")
                    time.sleep(0.08)
            elif cmd == "drag":
                x1, y1, x2, y2 = (int(v) for v in arg.split())
                q.hmp("mouse_move %d %d" % (x1 * 2, y1 * 2))
                state["x"], state["y"] = x1, y1
                time.sleep(0.08)
                q.hmp("mouse_button 1")
                time.sleep(0.05)
                for i in range(1, 11):
                    nx = x1 + (x2 - x1) * i // 10
                    ny = y1 + (y2 - y1) * i // 10
                    q.hmp("mouse_move %d %d" % (nx * 2, ny * 2))
                    state["x"], state["y"] = nx, ny
                    time.sleep(0.04)
                q.hmp("mouse_button 0")
                time.sleep(0.08)
            elif cmd == "shot":
                name = arg or "shot"
                p = os.path.join(out, name + ".ppm")
                q.cmd("screendump", filename=p)
                art(p, zoom=4, label=name)
            elif cmd == "crop":
                n, x, y, w, h = arg.split()
                p = os.path.join(out, n + ".ppm")
                if not os.path.exists(p):
                    q.cmd("screendump", filename=p)
                art(p, zoom=1, x0=int(x), y0=int(y), w=int(w), h=int(h), label="%s %s,%s %sx%s" % (n, x, y, w, h))
            elif cmd == "mon":
                r = q.cmd("human-monitor-command", **{"command-line": arg})
                print("--- mon %s ---" % arg)
                print(r.get("return", ""))
            elif cmd == "log":
                sf.flush()
                print("--- serial log ---")
                sys.stdout.write(open(serial).read())
        time.sleep(0.2)
    finally:
        qemu.terminate()
        qemu.wait()
        sf.close()
    tail = open(serial).read()
    if tail.strip():
        print("--- serial log ---")
        sys.stdout.write(tail)


main()
