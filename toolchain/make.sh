#!/bin/bash
#
# LFS 6.12. Make-4.4.1.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

directory=$(unpack_cross 'make-*.tar.gz' 'make-4.4.1')
cd "${directory}"

cross_configure

make

make DESTDIR="${LFS}" install
