#!/bin/bash
#
# libxcrypt - password hashing. LFS 12.4 section 8.27.
#
# sulogin from util-linux links libcrypt and could not start without it.
# Modern glibc no longer ships libcrypt itself, which is why this is a
# separate package.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'libxcrypt-*.tar.xz' 'libxcrypt-4.4.38')
cd "${directory}"

export CC=gcc

# --enable-obsolete-api=no: nothing built from source links the old entry
# points, and they only exist for binary-only applications.
./configure --prefix=/usr                \
            --enable-hashes=strong,glibc \
            --enable-obsolete-api=no     \
            --disable-static             \
            --disable-failure-tokens

make

make DESTDIR="${build_directory}" install
