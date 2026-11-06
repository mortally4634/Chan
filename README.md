# Chan Linux

A deliberately minimal Linux distribution whose **entire userland is x86-64 assembly**.

Chan boots the stock Linux kernel (like every Linux distro) and then hands control
to a single hand-written assembly program as **PID 1 (`/init`)**. That program is
all of Chan's userland: on boot it draws a **four-leaf-clover logo** beside a
**fastfetch-style system panel** (with the *real* kernel version read via `uname`),
then echoes your keystrokes back. No libc, no shell, no coreutils — just one ELF
the kernel runs directly.

```
   .-. .-.     root@chan
  (   V   )    ---------
   '-. .-'     OS:       Chan Linux x86_64
   .-'V'-.     Kernel:   6.x.x-...
  (   ^   )    Arch:     x86_64
   '-' '-'     Init:     /init (PID 1, asm)
      |        Userland: x86-64 assembly
      |        Shell:    none (echo loop)
```

```
QEMU
  └─ Linux kernel (bzImage)          ← stock, unchanged (C, like all distros)
       └─ unpacks initramfs into RAM
            └─ exec /init             ← src/init.asm, 100% x86-64 assembly
                 • write() banner to the console
                 • loop: read() a line  →  write() it back (echo)
```

## Why this counts as "mainly ASM"

The Linux kernel is ~30 million lines of C and no distribution rewrites it — a
"distro" is a kernel plus a userland. Chan's userland is a single assembly file,
so *every line of code that is Chan's own is assembly*. It even emits its own
ELF executable header by hand, so building needs **no compiler and no linker** —
just the NASM assembler.

## Repository layout

| Path                    | What it is                                                        |
|-------------------------|-------------------------------------------------------------------|
| `src/init.asm`          | The whole OS userland: ELF header + banner + echo loop (NASM).    |
| `tools/mkinitramfs.py`  | Pure-Python `newc` cpio packer (builds the initramfs image).      |
| `build.ps1` / `run.ps1` | Windows build & run scripts.                                      |
| `Makefile`              | Linux / WSL / macOS build & run (`make`, `make run`).             |
| `build/`                | Output: `init` (the ELF) and `chan.cpio` (the bootable image).    |

## What you need

1. **NASM** — the assembler (a single `.exe` on Windows).
2. **Python 3** — to build the initramfs (no extra packages).
3. **QEMU** — the VM to boot it in.
4. A Linux **kernel image** named `bzImage` in this folder (see below).

### Installing the tools on Windows (PowerShell)

```powershell
winget install NASM.NASM
winget install Python.Python.3.12
winget install SoftwareFreedomConservancy.QEMU
```

Then open a **new** terminal so the tools are on your `PATH`.

## Get a kernel (the one external piece)

Chan supplies the userland; you supply a kernel. Pick whichever is easiest:

- **Easiest if you have WSL / any Linux:** reuse the kernel your system already boots:
  ```bash
  cp "$(ls -1 /boot/vmlinuz-* | sort -V | tail -n1)" bzImage
  ```
  (or just run `make kernel`).

- **Download a tiny prebuilt kernel (Alpine `virt`):** grab `vmlinuz-virt` from an
  Alpine *netboot* release on <https://dl-cdn.alpinelinux.org/alpine/> and save it
  here as `bzImage`. Any recent x86-64 `vmlinuz`/`bzImage` works.

> A `vmlinuz`/`bzImage` is just a self-extracting Linux kernel; QEMU's `-kernel`
> flag boots it directly, no bootloader needed.

## Build and run

### Windows

```powershell
.\build.ps1          # assemble + pack  ->  build\chan.cpio
.\run.ps1            # boot (serial console in this terminal)
```

`.\run.ps1 -Window` opens a graphical VGA window instead.

### Linux / WSL / macOS

```bash
make                 # assemble + pack
make run             # boot (serial console)
```

`make run-vga` opens a graphical window.

## Using Chan

You'll see the cyan **Chan Linux** banner, then a `chan>` prompt. Type anything,
press **Enter**, and `/init` echoes the line back — proof that the assembly is
doing the reading and writing.

To quit the serial-console VM: press **Ctrl-A**, release, then **X**.
(Close the window to quit the `-Window` / `run-vga` variant.)

## How the magic works (two highlights)

- **Self-hosting ELF.** `src/init.asm` starts with `org 0x400000` and writes the
  64-byte ELF header and 56-byte program header as raw `db`/`dq` bytes. `nasm -f bin`
  turns that into a valid static Linux executable with zero toolchain beyond NASM.
- **`/dev/console` matters.** The initramfs includes a char-device node for
  `/dev/console` (major 5, minor 1). The kernel opens it as `/init`'s fd 0/1/2; omit
  it and the program runs but you'd see nothing. `tools/mkinitramfs.py` creates it.

## Notes & limits

- `/init` never calls `exit` — if PID 1 exits, the kernel panics. The echo loop is
  infinite by design.
- The console TTY runs in cooked mode, so the kernel's line discipline also echoes
  as you type; after Enter you'll see the line again from Chan's own `write()`.
- This is a teaching-sized OS. Extending it (more commands, raw-mode input via an
  `ioctl` termios call, mounting `/proc`) is all just more assembly in `init.asm`.
