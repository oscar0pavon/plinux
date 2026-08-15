#!/bin/bash
#
# mpc - complex arithmetic. LFS 12.4 section 8.23.
#
# The last of gcc's three arithmetic libraries. Built on gmp and mpfr.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'mpc-*.tar.gz' 'mpc-1.3.1')
cd "${directory}"

export CC=gcc

./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/mpc-1.3.1

make

make DESTDIR="${build_directory}" install
