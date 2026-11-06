# =============================================================================
#  Chan Linux  --  Makefile (thin wrapper over the Docker builder)
# -----------------------------------------------------------------------------
#    make iso     build dist/chan.iso            (default)
#    make test    build, then boot-test in QEMU
#    make run     boot dist/chan.iso in QEMU (needs host qemu)
#    make shell   open a shell in the builder container
#    make clean   remove build artifacts
# =============================================================================
IMAGE  := chan-builder
MOUNT  := -v "$(CURDIR)":/work

.PHONY: iso test run shell image clean

iso: image
	docker run --rm $(MOUNT) $(IMAGE) /work/tools/build-iso.sh

test: image
	docker run --rm $(MOUNT) $(IMAGE) /work/tools/test-boot.sh

image:
	docker build -t $(IMAGE) -f tools/Dockerfile .

run:
	qemu-system-x86_64 -cdrom dist/chan.iso -m 512 -boot d

shell: image
	docker run --rm -it $(MOUNT) $(IMAGE)

clean:
	rm -rf build iso dist
