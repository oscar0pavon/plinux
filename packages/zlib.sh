#!/bin/bash
#
# zlib - deflate. LFS 12.4 section 8.6.
#
# kmod links libz to read gzip-compressed kernel modules.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'zlib-*.tar.gz' 'zlib-1.3.1')
cd "${directory}"

# glibc, to match kmod and udev, which are what need it
export CC=gcc

./configure --prefix=/usr

make

make DESTDIR="${build_directory}" install

# the book removes this; a static libz has nothing to link against it here
rm -f "${build_directory}/usr/lib/libz.a"
