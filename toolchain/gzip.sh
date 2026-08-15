#!/bin/bash
#
# LFS 6.11. Gzip-1.14.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

directory=$(unpack_cross 'gzip-*.tar.xz' 'gzip-1.14')
cd "${directory}"

# The book configures this one with --prefix and --host only, and no --build.
# It goes through cross_configure like everything else here, which adds it.
#
# That is not a deviation with consequences: --build is how autoconf is told
# the build machine differs from the host, and gzip's configure reaches the
# same conclusion from --host alone. Naming it makes the cross-compile
# explicit rather than inferred, and keeps this script from being the one
# exception that has to be read twice.
cross_configure

make

make DESTDIR="${LFS}" install
