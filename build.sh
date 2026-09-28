#!/bin/sh
# ---------------------------------------------------------------------------
#  build.sh -- assemble DektopOS and produce a bootable disk image
#
#    ./build.sh              -> out/dodos.img      (1.44 MB floppy image)
#    ./build.sh hd           -> out/dodos-hd.img   (16 MB USB/HDD image)
# ---------------------------------------------------------------------------
set -e
cd "$(dirname "$0")"

OUT=out
TARGET=${1:-floppy}

nasm -f bin -I src -o $OUT/boot.bin src/boot.asm
nasm -f bin -I src -o $OUT/kernel.bin src/kernel.asm

K=$(stat -c%s $OUT/kernel.bin)
echo "kernel: $K bytes ($(( (K + 511) / 512 )) sectors)"

# The boot loader only reads KERNEL_SECTORS sectors. If the kernel outgrows
# that ceiling the tail is silently never loaded and the CPU runs off into
# zeroed memory -- a very expensive bug to chase. Fail the build instead.
SECTORS=$(grep -oP '^KERNEL_SECTORS\s+equ\s+\K[0-9]+' src/boot.asm)
if [ -n "$SECTORS" ] && [ "$K" -gt "$(( SECTORS * 512 ))" ]; then
  echo "ERROR: kernel is $K bytes but boot.asm only loads $SECTORS sectors" \
       "($(( SECTORS * 512 )) bytes). Raise KERNEL_SECTORS." >&2
  exit 1
fi
[ -n "$SECTORS" ] && echo "loader: $SECTORS sectors ($(( SECTORS * 512 )) bytes) OK"

# pad the kernel to a sector boundary
python3 - "$OUT/kernel.bin" <<'PY'
import sys
p = sys.argv[1]
d = open(p, 'rb').read()
d += b'\0' * ((-len(d)) % 512)
open(p, 'wb').write(d)
print("kernel padded to", len(d), "bytes")
PY

case "$TARGET" in
  floppy)
    IMG=$OUT/dodos.img
    rm -f $IMG
    dd if=/dev/zero of=$IMG bs=512 count=2880 status=none
    cat $OUT/boot.bin $OUT/kernel.bin > $OUT/parts.img
    dd if=$OUT/parts.img of=$IMG bs=512 seek=0 conv=notrunc status=none
    ;;
  hd)
    IMG=$OUT/dodos-hd.img
    rm -f $IMG
    dd if=/dev/zero of=$IMG bs=1M count=16 status=none
    cat $OUT/boot.bin $OUT/kernel.bin > $OUT/parts.img
    dd if=$OUT/parts.img of=$IMG bs=512 seek=0 conv=notrunc status=none
    # a descriptive (unused) partition table entry so some BIOSes are happy
    printf '\x80\x01\x01\x00\x04\x01\x01\x00\x20\x00\x00\x00\x00\x00\x00\x00\x00\x04\x00\x00\x00\x01\x00\x07\x00\xee\xfe\xff\xff\x1f\x3f\x0f\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' \
      | dd of=$IMG bs=1 seek=446 conv=notrunc status=none
    printf '\x55\xaa' | dd of=$IMG bs=1 seek=510 conv=notrunc status=none
    ;;
  *)
    echo "usage: ./build.sh [floppy|hd]"; exit 1 ;;
esac

rm -f $OUT/parts.img
echo "image : $IMG ($(stat -c%s $IMG) bytes)"
echo "run   : qemu-system-i386 -drive file=$IMG,format=raw,if=floppy -m 32"
