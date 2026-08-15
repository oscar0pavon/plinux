#!/bin/bash
#
# python - the interpreter, and the thing meson is written in.
# LFS 12.4 section 8.51.
#
# Not the same build as chapter 7's. That one is configured
# --without-ensurepip because it only has to run configure scripts; this one
# needs pip, because everything after it -- flit-core, packaging, wheel,
# setuptools and meson -- is installed with it.
#
# Before kmod, which is configured with meson, and therefore before most of
# what is left: wayland, libdrm, pixman, libinput, mesa, wlroots and sway are
# all meson packages.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'Python-*.tar.xz' 'Python-3.13.7')
cd "${directory}"

export CC=gcc

# --with-system-expat uses the expat built just before this rather than the
# copy bundled in the tarball, which is what moves expat up the order.
#
# --enable-optimizations builds the interpreter twice, profiling the first to
# optimise the second. The book recommends it and it roughly doubles the
# build time of this package; PLINUX_FAST_PYTHON=none is not a thing, so if
# this ever becomes annoying the switch is simply removed.
#
# --without-static-libpython drops a large archive nothing links.
#
# ensurepip is left at its default, which installs pip. That is the whole
# reason this package exists separately from chapter 7's.
./configure --prefix=/usr          \
            --enable-shared        \
            --with-system-expat    \
            --enable-optimizations \
            --without-static-libpython

make

make DESTDIR="${build_directory}" install
