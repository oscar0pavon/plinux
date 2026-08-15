#!/bin/bash
#
# LFS 6.8. Findutils-4.10.0.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

directory=$(unpack_cross 'findutils-*.tar.xz' 'findutils-4.10.0')
cd "${directory}"

# --localstatedir puts locate's database under /var/lib/locate, where the FHS
# wants it and where chapter 8's findutils will also put it.
cross_configure --localstatedir=/var/lib/locate

make

make DESTDIR="${LFS}" install
