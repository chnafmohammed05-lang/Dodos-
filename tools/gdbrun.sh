#!/bin/bash
# gdbrun.sh <script.gdb> [connect_delay]
#
# Kills any existing QEMU, boots a fresh one with a GDB stub on tcp::6677,
# runs the given GDB script against it, then cleans up.
#
# Doing this in one shot matters: attaching by hand easily lands you on a
# leftover QEMU from an earlier run, which serves a stale image on 6677 and
# makes the results completely meaningless.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$1"
DELAY="${2:-4}"

"$HERE/stopq.sh"
setsid "$HERE/gdbmon.sh" >/dev/null 2>&1 &
# With -gdb, QEMU holds the CPU at reset until a debugger attaches, so a
# short fixed wait is enough. Do NOT probe the port by connecting to it --
# that consumes the single gdbstub connection and lets the VM run away.
sleep 1
gdb -q -batch -x "$SCRIPT"
rc=$?
"$HERE/stopq.sh"
exit $rc
