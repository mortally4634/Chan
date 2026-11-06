#!/bin/sh
# =============================================================================
#  Chan Linux  --  automated boot test (runs inside the builder container)
#  Boots the kernel + initramfs under QEMU on the serial console, waits for the
#  shell, then feeds commands one at a time (a reader must be waiting, or the
#  tty line discipline eats input buffered during boot).
# =============================================================================
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

feed() {
    sleep 22                       # let the kernel boot and /init reach its prompt
    for c in \
        "help" \
        "four list" \
        "four install hello" \
        "four installed" \
        "four info hello" \
        "four remove hello" \
        "four installed" \
        "uname" \
        "poweroff"
    do
        printf '%s\n' "$c"
        sleep 1.5
    done
    sleep 2
}

echo "=== booting Chan under QEMU (software emulation, be patient) ==="
OUT="$(feed | timeout 240 qemu-system-x86_64 \
    -kernel iso/boot/vmlinuz \
    -initrd build/chan.cpio.gz \
    -append 'console=ttyS0 quiet' \
    -nographic -no-reboot -m 256 2>/dev/null || true)"

printf '%s\n' "$OUT"
echo "=== checks ==="
fail=0
check() { if printf '%s' "$OUT" | grep -q -- "$1"; then echo "PASS: $2"; else echo "FAIL: $2"; fail=1; fi; }
check 'root@chan'            'boot banner / clover fetch'
check 'Chan Linux commands' 'help builtin'
check 'about-four'          'four list (reads repo dir via getdents64)'
check 'installed: hello'    'four install (real file copy)'
check 'traditional first'   'four info (cats package)'
check 'removed: hello'      'four remove (unlink)'
[ "$fail" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
