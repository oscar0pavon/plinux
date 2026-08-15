#!/bin/bash
#
# mpfr - multiple precision floating point. LFS 12.4 section 8.22.
#
# Built on gmp, and required by mpc and gcc.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'mpfr-*.tar.xz' 'mpfr-4.2.2')
cd "${directory}"

export CC=gcc

./configure --prefix=/usr        \
            --disable-static     \
            --enable-thread-safe \
            --docdir=/usr/share/doc/mpfr-4.2.2

make

make DESTDIR="${build_directory}" install
