#!/bin/bash
#
# glibc - the GNU C library.
#
# LFS 12.4 section 8.5.
#
# Present because udev is part of systemd, and systemd does not build against
# musl: even the udev-only subset compiles src/basic and src/shared, which use
# glibc-specific interfaces. eudev was the usual way around that and is no
# longer maintained.
#
# glibc and musl coexist in the image the same way they do on the build host.
# They share no filenames and each binary names its own interpreter, so
# /lib64/ld-linux-x86-64.so.2 and /lib/ld-musl-x86_64.so.1 sit side by side.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'glibc-*.tar.xz' 'glibc-2.42')
cd "${directory}"

apply_patch 'glibc-*-fhs-1.patch'

# The C library is built with the host compiler; common.sh defaults CC to
# musl-gcc, which would be nonsense here.
export CC=gcc

# And without common.sh's -march. The book warns that untested -march values
# can break the toolchain packages and names Glibc among them, and glibc
# already selects AVX2 string and memory routines at runtime through ifunc, so
# building it for one CPU wins nothing that is not already happening.
unset CFLAGS CXXFLAGS

# The book's sed on stdlib/abort.c is skipped: it fixes Valgrind, which is a
# BLFS concern and not part of this system.

mkdir -p build
cd build

# ldconfig and sln otherwise land in /usr/sbin only by accident of the default
echo "rootsbindir=/usr/sbin" > configparms

# libc_cv_slibdir is an absolute path *inside the image*. The install below
# must therefore go through DESTDIR: without it, libc.so.6 and the dynamic
# loader are written straight into the build host's /usr/lib, replacing the
# running system's C library.
../configure --prefix=/usr                   \
             --disable-werror                \
             --disable-nscd                  \
             libc_cv_slibdir=/usr/lib        \
             --enable-stack-protector=strong \
             --enable-kernel=5.4

make

make DESTDIR="${build_directory}" install
