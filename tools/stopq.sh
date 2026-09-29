#!/bin/bash
# stopq.sh -- kill any running QEMU.
# Use -x (exact name), NOT -f: a -f pattern matches this script's own
# command line and kills the calling shell.
pkill -9 -x qemu-system-i386 2>/dev/null
exit 0
