# =============================================================================
#  Chan Linux  --  Makefile (Linux / WSL / macOS)
# -----------------------------------------------------------------------------
#  Targets:
#    make            assemble init + build initramfs
#    make run        boot in QEMU (serial console; exit with Ctrl-A X)
#    make run-vga    boot in QEMU with a graphical window
#    make kernel     copy the host's running kernel to ./bzImage (WSL/Linux)
#    make clean      remove build artifacts
#
#  Requires: nasm, python3, qemu-system-x86_64. Plus a ./bzImage kernel image.
# =============================================================================

NASM    ?= nasm
PYTHON  ?= python3
QEMU    ?= qemu-system-x86_64

BUILD   := build
INIT    := $(BUILD)/init
CPIO    := $(BUILD)/chan.cpio
KERNEL  := bzImage

.PHONY: all run run-vga kernel clean

all: $(CPIO)

$(INIT): src/init.asm | $(BUILD)
	$(NASM) -f bin $< -o $@

$(CPIO): $(INIT) tools/mkinitramfs.py
	$(PYTHON) tools/mkinitramfs.py $(INIT) $(CPIO)

$(BUILD):
	mkdir -p $(BUILD)

run: all
	@test -f $(KERNEL) || { echo "Missing ./$(KERNEL) -- run 'make kernel' or see README.md"; exit 1; }
	$(QEMU) -kernel $(KERNEL) -initrd $(CPIO) -m 256 -append "console=ttyS0" -nographic

run-vga: all
	@test -f $(KERNEL) || { echo "Missing ./$(KERNEL) -- run 'make kernel' or see README.md"; exit 1; }
	$(QEMU) -kernel $(KERNEL) -initrd $(CPIO) -m 256 -append "console=tty0"

# Grab a kernel the easy way: reuse the one this Linux/WSL system already boots.
kernel:
	@k=$$(ls -1 /boot/vmlinuz-* 2>/dev/null | sort -V | tail -n1); \
	if [ -n "$$k" ]; then cp "$$k" $(KERNEL) && echo "copied $$k -> ./$(KERNEL)"; \
	else echo "No /boot/vmlinuz-* found. See README.md (Get a kernel)."; exit 1; fi

clean:
	rm -rf $(BUILD) $(KERNEL)
