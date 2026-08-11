#!/bin/bash
#
# elfutils - here only for libelf.
#
# mesa's meson.build is unambiguous: "Gallium driver radeonsi requires
# libelf". It is used to parse the ELF objects the shader compiler produces.
#
# Only the library is wanted, not eu-readelf and the rest of the tools, and
# certainly not debuginfod, which would pull in libcurl and libmicrohttpd. The
# tools are built anyway because elfutils does not offer a way not to, and
# then removed after install.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'elfutils-*.tar.bz2' 'elfutils-0.193')
cd "${directory}"

# --disable-debuginfod drops the client and server; --enable-libdebuginfod=dummy
# builds a stub so the rest of the tree still links against the symbol names it
# expects without any of it doing anything.
# The compression options are all for libdwfl, which is not built here, and
# every one of them is a chance to link the host's copy: configure's link test
# for -lbz2 succeeds against /usr/lib because gcc's own search path is not
# sysroot-relative, and the build then fails on bzlib.h, which the sysroot
# does block. Turning them off is the decision; discovering them by accident
# is not.
./configure --prefix=/usr                 \
            --disable-debuginfod          \
            --enable-libdebuginfod=dummy  \
            --disable-nls                 \
            --without-bzlib               \
            --without-lzma                \
            --without-zstd

make

make -C libelf DESTDIR="${build_directory}" install
make -C libelf DESTDIR="${build_directory}" install-pkgconfigDATA 2>/dev/null || true
install -D -m 644 config/libelf.pc "${build_directory}/usr/lib/pkgconfig/libelf.pc" 2>/dev/null || true
