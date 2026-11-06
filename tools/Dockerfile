# Chan Linux builder image.
# Everything needed to assemble the userland and master a bootable ISO.
FROM debian:stable-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      nasm \
      python3-minimal \
      gzip \
      xorriso \
      isolinux \
      syslinux-common \
      qemu-system-x86 \
      linux-image-amd64 \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /work
ENTRYPOINT ["/bin/sh"]
