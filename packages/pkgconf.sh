#!/bin/bash
#
# pkgconf - the pkg-config implementation. LFS 12.4 section 8.19.
#
# The single most load-bearing package in this list, and the one that was
# missing longest without anyone noticing. packages/common.sh points
# PKG_CONFIG_LIBDIR and PKG_CONFIG_SYSROOT_DIR at the image, and every
# package from libffi onward -- the whole Wayland stack -- asks pkg-config
# where its dependencies are. None of them configure without it.
#
# It was absent because the build host supplied it. Building inside the
# chroot is what made "the host has pkgconf" stop being a substitute for the
# image having one.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'pkgconf-*.tar.xz' 'pkgconf-2.5.1')
cd "${directory}"

# glibc: this is a build tool the whole glibc stack consults, and the
# toolchain packages around it are glibc too.
export CC=gcc

./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/pkgconf-2.5.1

make

make DESTDIR="${build_directory}" install

# Everything asks for pkg-config, not pkgconf. The book creates both links.
ln -sfv pkgconf   "${build_directory}/usr/bin/pkg-config"
ln -sfv pkgconf.1 "${build_directory}/usr/share/man/man1/pkg-config.1"
