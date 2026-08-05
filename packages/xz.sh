#!/bin/bash
#
# xz - liblzma and the xz tools. LFS 12.4 section 8.8.
#
# kmod links liblzma to read xz-compressed kernel modules. The command line
# tools come along with it, which is what unpacks most of sources/.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'xz-*.tar.xz' 'xz-5.8.1')
cd "${directory}"

export CC=gcc

./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/xz-5.8.1

make

make DESTDIR="${build_directory}" install
