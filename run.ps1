# =============================================================================
#  Chan Linux  --  run the ISO in a VM (Windows / PowerShell)
# -----------------------------------------------------------------------------
#  Boots dist\chan.iso in QEMU with a graphical window. If QEMU isn't on PATH,
#  prints how to boot the ISO in VirtualBox / VMware / Hyper-V instead.
#
#     .\run.ps1            graphical window (daily-driver view)
#     .\run.ps1 -Serial    serial console in this terminal (exit: Ctrl-A X)
# =============================================================================
param([switch]$Serial)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$iso = Join-Path $root "dist\chan.iso"

if (-not (Test-Path $iso)) { throw "dist\chan.iso not found. Run .\build.ps1 first." }

$qemu = Get-Command qemu-system-x86_64 -ErrorAction SilentlyContinue
if (-not $qemu) {
    Write-Host "QEMU not found on PATH." -ForegroundColor Yellow
    Write-Host "Install it:  winget install SoftwareFreedomConservancy.QEMU   (reopen terminal after)"
    Write-Host ""
    Write-Host "Or boot dist\chan.iso in any VM:" -ForegroundColor Cyan
    Write-Host "  VirtualBox : New > Type 'Other/Unknown (64-bit)' > attach the ISO as a CD > Start"
    Write-Host "  VMware     : New VM > 'I will install later' > attach ISO to the CD/DVD drive"
    Write-Host "  Hyper-V    : New > Generation 1 > attach ISO as DVD (Gen 1 = BIOS boot)"
    return
}

if ($Serial) {
    & $qemu.Path -cdrom $iso -m 512 -boot d -nographic
} else {
    & $qemu.Path -cdrom $iso -m 512 -boot d
}
