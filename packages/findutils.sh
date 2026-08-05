#!/bin/bash
#
# findutils - find, xargs, locate, updatedb. LFS 12.4 section 8.62.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'findutils-*.tar.xz' 'findutils-4.10.0')
cd "${directory}"

# --localstatedir puts the locate database at the FHS location
./configure --prefix=/usr --localstatedir=/var/lib/locate

make

make DESTDIR="${build_directory}" install
