#!/bin/bash
# shot.sh <tag> <wait_seconds> [out.ppm]
# Boots out/dodos.img headless, waits, grabs a 640x400 screendump, kills QEMU.
TAG="$1"
WAIT="${2:-10}"
OUT="${3:-/tmp/opencode/shot_$TAG.ppm}"
IMG=${IMG:-out/dodos.img}
SER=/tmp/opencode/ser_$TAG.txt
MON=/tmp/opencode/mon_$TAG.sock

# /tmp is volatile -- a reboot wipes this directory.
mkdir -p /tmp/opencode
rm -f "$OUT" "$SER" "$MON"
setsid qemu-system-i386 \
  -drive file="$IMG",format=raw,if=floppy \
  -m 32 -display none -vga std -serial file:"$SER" \
  -monitor unix:"$MON",server,nowait \
  -no-reboot >/dev/null 2>&1 &

for i in $(seq 1 60); do [ -S "$MON" ] && break; sleep 0.2; done
sleep "$WAIT"
printf 'screendump %s\nquit\n' "$OUT" | socat - "unix-connect:$MON" >/dev/null 2>&1
sleep 0.5
pkill -9 -x qemu-system-i386 2>/dev/null
echo "screenshot: $(ls -la "$OUT" 2>/dev/null | awk '{print $5}') bytes"
echo "serial: $(stat -c%s "$SER" 2>/dev/null || echo 0) bytes"
