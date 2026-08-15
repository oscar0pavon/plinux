#!/bin/bash
#
# autoconf - configure script generator. LFS 12.4 section 8.46.
#
# Here because coreutils needs it. Its upstream_fix patch touches
# tests/local.mk, which makes Makefile.in older than the Makefile.am it is
# generated from, so make runs automake to regenerate it -- and automake runs
# autoconf. On the host that worked because the host had both. In the chroot
# coreutils stopped with "Error 127" four packages into the build.
#
# Shell and perl, so nothing here is compiled and CC does not matter. It
# needs m4 and perl at *run* time, which is the reason it sits after them
# rather than anywhere else.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'autoconf-*.tar.xz' 'autoconf-2.72')
cd "${directory}"

export CC=gcc

./configure --prefix=/usr

make

make DESTDIR="${build_directory}" install
