#!/bin/bash
# gdbmon.sh -- boot out/dodos.img headless with a GDB stub on tcp::6677
#
# Run tools/stopq.sh first. A stale QEMU still holding port 6677 will accept
# your connection and show you a completely different build, which is a
# spectacularly confusing way to waste an afternoon.
mkdir -p /tmp/opencode
cp /home/mohammed-chnaf/dodos/out/dodos.img /tmp/opencode/live.img
exec qemu-system-i386 \
  -drive file=/tmp/opencode/live.img,format=raw,if=floppy \
  -m 32 -display none -vga std \
  -serial file:/tmp/opencode/ser_dbg.txt \
  -monitor unix:/tmp/opencode/mon_dbg.sock,server,nowait \
  -gdb tcp::6677 -no-reboot
