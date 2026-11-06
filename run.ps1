# =============================================================================
#  Chan Linux  --  run in a VM (Windows / PowerShell)
# -----------------------------------------------------------------------------
#  Boots Chan under QEMU. Requires qemu-system-x86_64 on PATH and a kernel
#  image named 'bzImage' in this folder (see README.md for how to get one).
#
#     qemu -> https://www.qemu.org/download/#windows
#             (or: winget install SoftwareFreedomConservancy.QEMU)
#
#  Run:  .\run.ps1            (serial console in this terminal; exit = Ctrl-A X)
#        .\run.ps1 -Window    (graphical VGA window instead)
# =============================================================================
param([switch]$Window)

$ErrorActionPreference = "Stop"
$root  = $PSScriptRoot
$cpio  = Join-Path $root "build\chan.cpio"
$kernel = Join-Path $root "bzImage"

if (-not (Get-Command qemu-system-x86_64 -ErrorAction SilentlyContinue)) {
    throw "qemu-system-x86_64 not found on PATH. See README.md."
}
if (-not (Test-Path $cpio))   { throw "build\chan.cpio missing. Run .\build.ps1 first." }
if (-not (Test-Path $kernel)) { throw "Kernel 'bzImage' missing in $root. See README.md (Get a kernel)." }

$common = @(
    "-kernel", $kernel,
    "-initrd", $cpio,
    "-m", "256"
)

if ($Window) {
    # VGA window: /dev/console is the graphical text console (tty0).
    qemu-system-x86_64 @common -append "console=tty0"
} else {
    # Serial console wired to this terminal. Best for seeing the echo loop.
    qemu-system-x86_64 @common -append "console=ttyS0" -nographic
}
