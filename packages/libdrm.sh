#!/bin/bash
#
# libdrm - the userspace side of the kernel's Direct Rendering Manager.
#
# Every ioctl that sets a mode, allocates a buffer or submits work to the GPU
# goes through here. Mesa uses it, wlroots uses it directly for the DRM
# backend, and the amdgpu bits are what talk to the card in this machine.
#
# Which drivers get built is a per-card decision, and it is made the same way
# the kernel config was: only what this hardware has.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'libdrm-*.tar.xz' 'libdrm-2.4.126')
cd "${directory}"

# amdgpu only. The card is a Navi 23, which amdgpu drives; radeon is the
# pre-GCN driver and would never bind to it. intel is off for the same reason
# DRM_I915 came out of the kernel config -- there is no Intel GPU, the iGPU is
# disabled in the BIOS.
#
# Nothing is needed for the VM: virtio-gpu has no per-driver support here, it
# goes through the generic DRM path.
#
# udev=true so libdrm resolves device nodes the way the rest of the system
# does. tests and man pages are off; the man pages want xsltproc.
meson_setup build              \
      -Damdgpu=enabled         \
      -Dradeon=disabled        \
      -Dintel=disabled         \
      -Dnouveau=disabled       \
      -Dvmwgfx=disabled        \
      -Domap=disabled          \
      -Dexynos=disabled        \
      -Dfreedreno=disabled     \
      -Dtegra=disabled         \
      -Dvc4=disabled           \
      -Detnaviv=disabled       \
      -Dudev=true              \
      -Dcairo-tests=disabled   \
      -Dvalgrind=disabled      \
      -Dman-pages=disabled     \
      -Dtests=false            \
      -Dinstall-test-programs=false

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
