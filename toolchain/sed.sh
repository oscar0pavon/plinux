#!/bin/bash
#
# LFS 6.14. Sed-4.9.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

directory=$(unpack_cross 'sed-*.tar.xz' 'sed-4.9')
cd "${directory}"

cross_configure

make

make DESTDIR="${LFS}" install
