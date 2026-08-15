#!/bin/bash
#
# LFS 6.15. Tar-1.35.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

directory=$(unpack_cross 'tar-*.tar.xz' 'tar-1.35')
cd "${directory}"

cross_configure

make

make DESTDIR="${LFS}" install
