#!/bin/bash
#
# kmod - libkmod and the module loading tools.
#
# LFS 12.4 section 8.58. Built before udev, which uses libkmod to load modules
# in response to device events.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'kmod-*.tar.xz' 'kmod-34.2')
cd "${directory}"

# glibc, to match udev
export CC=gcc

mkdir -p build
cd build

# manpages=false avoids needing an external documentation generator
meson setup --prefix=/usr .. \
            --buildtype=release \
            -D manpages=false

ninja

DESTDIR="${build_directory}" ninja install
