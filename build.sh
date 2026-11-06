#!/bin/sh
# =============================================================================
#  Chan Linux  --  build (Linux / macOS / WSL)
#  Builds dist/chan.iso via the Docker builder image. Pass --test to boot-test.
# =============================================================================
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

command -v docker >/dev/null 2>&1 || { echo "Docker required"; exit 1; }

echo "==> building builder image (cached after first run)"
docker build -t chan-builder -f tools/Dockerfile .

echo "==> assembling userland + mastering ISO"
docker run --rm -v "$(pwd)":/work chan-builder /work/tools/build-iso.sh

if [ "${1:-}" = "--test" ]; then
    echo "==> boot-testing under QEMU"
    docker run --rm -v "$(pwd)":/work chan-builder /work/tools/test-boot.sh
fi

echo ""
echo "Done -> dist/chan.iso   (boot with ./run.sh or attach to any VM)"
