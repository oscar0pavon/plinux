#!/bin/bash
#
# bison - the parser generator. LFS 12.4 section 8.34.
#
# Replaces chapter 7's copy. After m4, which bison is written in terms of and
# calls at run time.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'bison-*.tar.xz' 'bison-3.8.2')
cd "${directory}"

export CC=gcc

./configure --prefix=/usr \
            --docdir=/usr/share/doc/bison-3.8.2

make

make DESTDIR="${build_directory}" install
