# Chan Linux 🍀

A minimalist Linux distribution whose **entire userland is x86-64 assembly**.

Chan boots the stock Linux kernel — like every Linux distribution — and then hands
control to a single hand-written assembly program as **PID 1 (`/init`)**. That one
program *is* Chan's whole userland: it draws a four-leaf-clover logo beside a
fastfetch-style panel (with the real kernel version, read via `uname`), then runs an
interactive shell with a built-in package manager called **`four`**. No libc, no
coreutils, no external shell — just one freestanding ELF the kernel executes directly.

```
   .-. .-.     root@chan
  (   V   )    ---------
   '-. .-'     OS:       Chan Linux x86_64
   .-'V'-.     Kernel:   6.12.x-amd64
  (   ^   )    Arch:     x86_64
   '-' '-'     Init:     /init (PID 1, asm)
      |        Userland: x86-64 assembly
      |        Pkgmgr:   four

chan> four install hello
installed: hello
```

## What "mainly ASM" means here

A Linux *distribution* is a kernel plus a userland; no distro rewrites the kernel
(~30M lines of C). Chan's contribution — **every line of code that is Chan's own** —
is assembly: the init/shell and the `four` package manager, in [`src/init.asm`](src/init.asm).
It even emits its **own ELF executable header by hand**, so building the userland
needs *no compiler and no linker* — just the NASM assembler.

> **Scope, honestly:** an all-assembly userland can't include a browser, a GUI, or a
> C library, so Chan isn't a daily driver in the Ubuntu sense. What it *is*: a real,
> bootable, interactive, package-managed OS on a standard ISO. That's the ceiling for
> a hand-written assembly userland — and everything here genuinely boots and runs.

## Quick start

You need **Docker Desktop** (the only host dependency — it builds the ISO
reproducibly on any OS). To boot the result you need any VM (QEMU, VirtualBox,
VMware, Hyper-V).

### Windows (PowerShell)
```powershell
.\build.ps1          # -> dist\chan.iso
.\run.ps1            # boot it in a QEMU window
```
`.\build.ps1 -Test` also boots it headlessly and asserts the shell + `four` work.

### Linux / macOS / WSL
```bash
./build.sh           # -> dist/chan.iso   (or: make iso)
./run.sh             # boot it            (or: make run)
```
`make test` runs the automated boot test.

Then attach `dist/chan.iso` to any VM (BIOS / "Generation 1" boot). The ISO is
isohybrid, so `dd`-ing it to a USB stick boots on real BIOS hardware too.

## Using Chan

| Command | What it does |
|---|---|
| `help` | list shell commands |
| `clear` | clear the screen |
| `echo <text>` | print text |
| `fetch` | redraw the clover system panel |
| `uname` | show the real kernel release + arch |
| `four <args>` | the package manager (below) |
| `poweroff` / `reboot` | ACPI power-down / restart |

### `four` — the package manager 🍀

Named after the clover's four leaves. Packages live as files in a repository under
`/var/four`, and `four` tracks installed state on disk — a real install/remove cycle.

| Command | What it does |
|---|---|
| `four list` | available packages (reads the repo dir via `getdents64`) |
| `four installed` | installed packages |
| `four install <pkg>` | copy a package into the installed set |
| `four remove <pkg>` | remove an installed package (`unlinkat`) |
| `four info <pkg>` | print a package's contents |
| `four help` | help |

Add your own package by dropping a file in [`rootfs/var/four/available/`](rootfs/var/four/available)
and rebuilding.

## How it boots

```
QEMU / VirtualBox / real HW
  └─ ISOLINUX (BIOS bootloader on the ISO)
       └─ Linux kernel (bzImage)              stock, from Debian's linux-image
            └─ unpacks initramfs into RAM     built by tools/mkinitramfs.py
                 └─ exec /init                src/init.asm  (100% x86-64 asm)
                      • uname() + draw clover/fetch panel
                      • shell REPL: builtins + four
```

## Repository layout

| Path | Role |
|---|---|
| [`src/init.asm`](src/init.asm) | The entire userland: ELF header + shell + `four` |
| [`rootfs/`](rootfs) | The distro filesystem (etc, proc, `four`'s package repo) |
| [`tools/mkinitramfs.py`](tools/mkinitramfs.py) | Pure-Python `newc` cpio packer |
| [`tools/Dockerfile`](tools/Dockerfile) | Reproducible builder image (nasm, xorriso, isolinux, kernel) |
| [`tools/build-iso.sh`](tools/build-iso.sh) | Assemble → pack → master ISO |
| [`tools/test-boot.sh`](tools/test-boot.sh) | Automated QEMU boot test |
| `build.ps1` / `run.ps1` / `build.sh` / `run.sh` / `Makefile` | Host wrappers |
| `dist/chan.iso` | Output (git-ignored; rebuildable) |

## Implementation highlights

- **Self-hosting ELF.** `src/init.asm` writes the 64-byte ELF header and 56-byte
  program header as raw bytes under `org 0x400000`, so `nasm -f bin` alone yields a
  valid static Linux executable — no toolchain beyond the assembler.
- **Raw syscalls only.** `read`, `write`, `uname`, `openat`, `getdents64`,
  `unlinkat`, `mount`, `reboot` — invoked directly via the `syscall` instruction with
  the x86-64 ABI (`rax`=number, `rdi/rsi/rdx/r10/r8/r9`=args). No libc wrappers.
- **PID 1 discipline.** If PID 1 exits the kernel panics, so the shell loop is
  infinite; only `poweroff`/`reboot` end the session, via the `reboot(2)` magic.
- **`/dev/console` is mandatory.** The initramfs includes a char-device node
  `(5,1)` so the kernel wires `/init`'s stdin/stdout to the console — without it the
  program runs but you'd see nothing.

## Extending it

Everything grows in one place — `src/init.asm`. Natural next steps: more builtins
(`cat`, `ls` via `getdents64`), making `four` fetch over a real network socket,
splitting `four` into its own `/bin/four` ELF launched with `fork`+`execve`, or
adding a UEFI boot path alongside ISOLINUX.

## License

MIT for Chan's own code (see [LICENSE](LICENSE)). The Linux kernel on the ISO is
GPLv2, from kernel.org.
