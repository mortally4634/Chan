#!/usr/bin/env python3
# =============================================================================
#  Chan Linux  --  initramfs builder
# -----------------------------------------------------------------------------
#  Packs a staging root filesystem + the assembled /init into a `newc` cpio
#  archive the Linux kernel unpacks into RAM at boot. Pure standard library,
#  so it runs identically on Windows, macOS, Linux and WSL -- no `cpio` tool.
#
#  What goes in:
#     /init                 <- the assembled x86-64 program (PID 1), mode 0755
#     everything in ROOTFS  <- dirs + files (var/four repo, etc, proc, ...)
#     /dev, /dev/console    <- synthesized char device (5,1) so init gets a tty
#
#  Usage:  python mkinitramfs.py <rootfs-dir> <init-binary> <output.cpio>
# =============================================================================

import sys
import os

MAGIC = b"070701"

S_IFDIR = 0o040000
S_IFREG = 0o100000
S_IFCHR = 0o020000


def makedev(major, minor):
    return (major << 8) | minor


class CpioWriter:
    def __init__(self):
        self.out = bytearray()
        self.ino = 0

    def _pad4(self):
        while len(self.out) % 4 != 0:
            self.out += b"\x00"

    def add(self, name, data=b"", mode=0o100644, nlink=1, rdev=0):
        self.ino += 1
        name_bytes = name.encode("ascii") + b"\x00"
        fields = [
            self.ino, mode, 0, 0, nlink, 0, len(data),
            0, 0, (rdev >> 8) & 0xFF, rdev & 0xFF, len(name_bytes), 0,
        ]
        self.out += MAGIC + b"".join(b"%08X" % f for f in fields)
        self.out += name_bytes
        self._pad4()
        self.out += data
        self._pad4()

    def finish(self):
        self.add("TRAILER!!!", b"", mode=0, nlink=1)
        return bytes(self.out)


def main():
    if len(sys.argv) != 4:
        sys.stderr.write(
            "usage: python mkinitramfs.py <rootfs-dir> <init-binary> <out.cpio>\n"
        )
        return 2

    rootfs, init_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    cpio = CpioWriter()

    # /dev/console: without this node the kernel can't wire init's fd 0/1/2.
    cpio.add("dev", mode=S_IFDIR | 0o755, nlink=2)
    cpio.add("dev/console", mode=S_IFCHR | 0o600, nlink=1, rdev=makedev(5, 1))

    # /init -- the entire userland, executable.
    with open(init_path, "rb") as f:
        cpio.add("init", f.read(), mode=S_IFREG | 0o755, nlink=1)

    # Walk the staging rootfs. os.walk is top-down, so parent dirs are always
    # emitted before their children -- exactly what cpio requires.
    for dirpath, dirnames, filenames in os.walk(rootfs):
        dirnames.sort()
        filenames.sort()
        rel = os.path.relpath(dirpath, rootfs).replace("\\", "/")
        if rel != ".":
            cpio.add(rel, mode=S_IFDIR | 0o755, nlink=2)
        for fn in filenames:
            if fn == ".keep":           # marker for otherwise-empty dirs
                continue
            full = os.path.join(dirpath, fn)
            name = fn if rel == "." else rel + "/" + fn
            with open(full, "rb") as f:
                cpio.add(name, f.read(), mode=S_IFREG | 0o644, nlink=1)

    image = cpio.finish()
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(image)
    print("wrote %s (%d bytes)" % (out_path, len(image)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
