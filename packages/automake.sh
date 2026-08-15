#!/bin/bash
#
# automake - Makefile.in generator. LFS 12.4 section 8.47.
#
# After autoconf, which it drives. Together they are what coreutils reaches
# for when its patched Makefile.am is newer than the Makefile.in in the
# tarball.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'automake-*.tar.xz' 'automake-1.18.1')
cd "${directory}"

export CC=gcc

./configure --prefix=/usr \
            --docdir=/usr/share/doc/automake-1.18.1

make

make DESTDIR="${build_directory}" install
