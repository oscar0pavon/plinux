#!/bin/bash
#
# zstd - libzstd and the zstd tools. LFS 12.4 section 8.10.
#
# kmod links libzstd to read zstd-compressed kernel modules, which is what
# the kernel compresses them with by default now.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'zstd-*.tar.gz' 'zstd-1.5.7')
cd "${directory}"

export CC=gcc

# no configure: zstd is a plain makefile, and the prefix has to be repeated on
# the install because it is read at both steps.
#
# HAVE_LZ4=0 because the zstd program otherwise links the host's liblz4 for
# its --format=lz4 passthrough, and lz4 is not in this image: the binary then
# dies with "error while loading shared libraries: liblz4.so.1". libzstd
# itself never wanted it, so nothing kmod needs is affected either way.
make prefix=/usr HAVE_LZ4=0

make prefix=/usr HAVE_LZ4=0 DESTDIR="${build_directory}" install

rm -f "${build_directory}/usr/lib/libzstd.a"
