#!/bin/bash
#
# pixman - software pixel manipulation.
#
# wlroots renders with the GPU when it has one and falls back to pixman when
# it does not, so this is what makes the compositor work in the VM, where
# virtio-gpu offers no acceleration mesa can use. cairo will want it later
# too.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'pixman-*.tar.gz' 'pixman-0.46.4')
cd "${directory}"

# The SIMD paths are left at their defaults, which detect what the compiler
# can emit; this is x86-64 and common.sh already passes -march=native, so mmx,
# sse2 and ssse3 all come in.
#
# gtk and libpng are only for the demos and tests, and pulling in either would
# drag a toolkit into the image. Turning them off explicitly rather than
# relying on them being absent is the same rule as everywhere else here: a
# dependency should be a decision, not an accident of what the host has.
meson_setup build     \
      -Dgtk=disabled  \
      -Dlibpng=disabled \
      -Dopenmp=disabled \
      -Dtests=disabled  \
      -Ddemos=disabled

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
