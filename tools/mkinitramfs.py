#!/usr/bin/env python3
# =============================================================================
#  Chan Linux  --  initramfs builder
# -----------------------------------------------------------------------------
#  Builds a `newc` (ASCII) cpio archive the Linux kernel unpacks into RAM at
#  boot. Pure standard library, so it runs identically on Windows, macOS, Linux
#  and WSL with no external `cpio` tool.
#
#  Contents of the image:
#     dev/            directory
#     dev/console     char device (5,1)  <- kernel wires init's fd 0/1/2 here
#     init            our assembled x86-64 program, mode 0755  <- PID 1
#
#  Usage:  python tools/mkinitramfs.py <path-to-init-binary> <output.cpio>
# =============================================================================

import sys
import os

MAGIC = b"070701"            # newc format magic

# Linux mode bits
S_IFDIR = 0o040000
S_IFREG = 0o100000
S_IFCHR = 0o020000


def makedev(major, minor):
    # Classic 8-bit encoding used by cpio newc fields.
    return (major << 8) | minor


class CpioWriter:
    def __init__(self):
        self.out = bytearray()
        self.ino = 0

    def _pad4(self):
        while len(self.out) % 4 != 0:
            self.out += b"\x00"

    def add(self, name, data=b"", mode=0o100644, nlink=1, rdev=0):
        """Append one cpio entry."""
        self.ino += 1
        name_bytes = name.encode("ascii") + b"\x00"

        # 13 hex fields, each 8 chars, in the exact newc order.
        fields = [
            self.ino,            # c_ino
            mode,                # c_mode
            0,                   # c_uid
            0,                   # c_gid
            nlink,               # c_nlink
            0,                   # c_mtime
            len(data),           # c_filesize
            0,                   # c_devmajor
            0,                   # c_devminor
            (rdev >> 8) & 0xFF,  # c_rdevmajor
            rdev & 0xFF,         # c_rdevminor
            len(name_bytes),     # c_namesize (includes trailing NUL)
            0,                   # c_check (unused for newc)
        ]

        header = MAGIC + b"".join(b"%08X" % f for f in fields)
        self.out += header
        self.out += name_bytes
        self._pad4()             # pad header+name to 4-byte boundary
        self.out += data
        self._pad4()             # pad data to 4-byte boundary

    def finish(self):
        # Mandatory end-of-archive marker.
        self.add("TRAILER!!!", b"", mode=0, nlink=1)
        return bytes(self.out)


def main():
    if len(sys.argv) != 3:
        sys.stderr.write(
            "usage: python tools/mkinitramfs.py <init-binary> <output.cpio>\n"
        )
        return 2

    init_path, out_path = sys.argv[1], sys.argv[2]

    with open(init_path, "rb") as f:
        init_data = f.read()

    cpio = CpioWriter()
    # Parent directories must come before their children.
    cpio.add("dev", mode=S_IFDIR | 0o755, nlink=2)
    cpio.add("dev/console", mode=S_IFCHR | 0o600, nlink=1, rdev=makedev(5, 1))
    cpio.add("init", init_data, mode=S_IFREG | 0o755, nlink=1)
    image = cpio.finish()

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(image)

    print("wrote %s (%d bytes, init=%d bytes)"
          % (out_path, len(image), len(init_data)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
