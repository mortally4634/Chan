#!/bin/sh
# =============================================================================
#  Chan Linux  --  run the ISO in QEMU (Linux / macOS)
#     ./run.sh             graphical window
#     ./run.sh --serial    serial console in this terminal (exit: Ctrl-A X)
# =============================================================================
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

[ -f dist/chan.iso ] || { echo "dist/chan.iso not found; run ./build.sh first"; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "Install QEMU (e.g. 'apt install qemu-system-x86' / 'brew install qemu'),"
    echo "or attach dist/chan.iso to any VM (BIOS/Generation-1 boot)."
    exit 1
}

if [ "${1:-}" = "--serial" ]; then
    exec qemu-system-x86_64 -cdrom dist/chan.iso -m 512 -boot d -nographic
else
    exec qemu-system-x86_64 -cdrom dist/chan.iso -m 512 -boot d
fi
