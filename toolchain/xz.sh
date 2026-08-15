#!/bin/bash
#
# LFS 6.16. Xz-5.8.1.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

directory=$(unpack_cross 'xz-*.tar.xz' 'xz-5.8.1')
cd "${directory}"

cross_configure --disable-static \
                --docdir=/usr/share/doc/xz-5.8.1

make

make DESTDIR="${LFS}" install

# As for file's libmagic.la: the recorded link paths are this workstation's.
rm -v "${LFS}/usr/lib/liblzma.la"
