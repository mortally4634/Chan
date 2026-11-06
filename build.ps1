# =============================================================================
#  Chan Linux  --  build (Windows / PowerShell)
# -----------------------------------------------------------------------------
#  Builds dist\chan.iso using the reproducible Docker builder image.
#  Only Docker Desktop is required on the host.
#
#     .\build.ps1          build the ISO
#     .\build.ps1 -Test    build, then boot-test it under QEMU in the container
# =============================================================================
param([switch]$Test)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
Set-Location $root

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker not found. Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
}
try { docker info *> $null } catch { throw "Docker daemon is not running. Start Docker Desktop and retry." }
if ($LASTEXITCODE -ne 0) { throw "Docker daemon is not running. Start Docker Desktop and retry." }

$mount = "$($root):/work"

Write-Host "==> building builder image (cached after first run)" -ForegroundColor Cyan
docker build -t chan-builder -f tools/Dockerfile .
if ($LASTEXITCODE -ne 0) { throw "docker build failed" }

Write-Host "==> assembling userland + mastering ISO" -ForegroundColor Cyan
docker run --rm -v $mount chan-builder /work/tools/build-iso.sh
if ($LASTEXITCODE -ne 0) { throw "ISO build failed" }

if ($Test) {
    Write-Host "==> boot-testing under QEMU (software emulation; patience)" -ForegroundColor Cyan
    docker run --rm -v $mount chan-builder /work/tools/test-boot.sh
}

Write-Host ""
Write-Host "Done -> dist\chan.iso" -ForegroundColor Green
Write-Host "Boot it:  .\run.ps1   (or attach dist\chan.iso to any VM)" -ForegroundColor Green
