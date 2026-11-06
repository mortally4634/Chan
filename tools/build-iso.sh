#!/bin/sh
# =============================================================================
#  Chan Linux  --  build a bootable ISO (runs inside the builder container)
# =============================================================================
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

mkdir -p build dist iso/isolinux iso/boot

echo "[1/5] assemble userland (src/init.asm -> build/init)"
nasm -f bin src/init.asm -o build/init

echo "[2/5] pack initramfs (rootfs + /init -> build/chan.cpio.gz)"
python3 tools/mkinitramfs.py rootfs build/init build/chan.cpio
gzip -9 -c build/chan.cpio > build/chan.cpio.gz

echo "[3/5] stage kernel + initramfs"
cp /boot/vmlinuz-* iso/boot/vmlinuz
cp build/chan.cpio.gz iso/boot/chan.cpio.gz

echo "[4/5] stage isolinux bootloader"
cp /usr/lib/ISOLINUX/isolinux.bin iso/isolinux/isolinux.bin
cp /usr/lib/syslinux/modules/bios/ldlinux.c32 iso/isolinux/ldlinux.c32
cp tools/isolinux.cfg iso/isolinux/isolinux.cfg

echo "[5/5] master ISO (dist/chan.iso)"
xorriso -as mkisofs \
  -o dist/chan.iso \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
  -c isolinux/boot.cat \
  -b isolinux/isolinux.bin \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -volid CHAN_LINUX \
  iso >/dev/null 2>&1

echo ""
echo "OK -> dist/chan.iso"
ls -lh dist/chan.iso
