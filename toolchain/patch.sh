#!/bin/bash
#
# LFS 6.13. Patch-2.8.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

directory=$(unpack_cross 'patch-*.tar.xz' 'patch-2.8')
cd "${directory}"

cross_configure

make

make DESTDIR="${LFS}" install
