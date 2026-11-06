# =============================================================================
#  Chan Linux  --  build (Windows / PowerShell)
# -----------------------------------------------------------------------------
#  Assembles the ASM init and packs the initramfs. Requires only NASM + Python.
#     nasm   -> https://www.nasm.us/  (or: winget install NASM.NASM)
#     python -> https://python.org/   (or: winget install Python.Python.3.12)
#
#  Run:  .\build.ps1
# =============================================================================
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$build = Join-Path $root "build"
New-Item -ItemType Directory -Force -Path $build | Out-Null

function Need($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "'$name' not found on PATH. See README.md for install instructions."
    }
}
Need nasm
Need python

$initAsm = Join-Path $root "src\init.asm"
$initBin = Join-Path $build "init"
$cpio    = Join-Path $build "chan.cpio"

Write-Host "[1/2] assembling init.asm -> build/init" -ForegroundColor Cyan
nasm -f bin $initAsm -o $initBin
if ($LASTEXITCODE -ne 0) { throw "nasm failed" }

Write-Host "[2/2] packing initramfs -> build/chan.cpio" -ForegroundColor Cyan
python (Join-Path $root "tools\mkinitramfs.py") $initBin $cpio
if ($LASTEXITCODE -ne 0) { throw "mkinitramfs failed" }

Write-Host ""
Write-Host "Build complete. Now run:  .\run.ps1" -ForegroundColor Green
Write-Host "(You still need a kernel 'bzImage' in this folder -- see README.md.)" -ForegroundColor Yellow
