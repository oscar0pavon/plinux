#!/bin/bash
#
# LFS 6.9. Gawk-5.3.2.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

directory=$(unpack_cross 'gawk-*.tar.xz' 'gawk-5.3.2')
cd "${directory}"

# The extras directory holds optional shared-library extensions that this
# temporary gawk has no use for. Dropped from the makefile rather than built
# and deleted.
sed -i 's/extras//' Makefile.in

cross_configure

make

make DESTDIR="${LFS}" install
