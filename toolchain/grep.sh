#!/bin/bash
#
# LFS 6.10. Grep-3.12.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

directory=$(unpack_cross 'grep-*.tar.xz' 'grep-3.12')
cd "${directory}"

cross_configure

make

make DESTDIR="${LFS}" install
