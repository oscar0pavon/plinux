#!/bin/bash
#
# attr - extended attribute support. LFS 12.4 section 8.24.
#
# Here because acl needs it, and udev needs libacl.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'attr-*.tar.gz' 'attr-2.5.2')
cd "${directory}"

export CC=gcc

./configure --prefix=/usr     \
            --disable-static  \
            --sysconfdir=/etc \
            --docdir=/usr/share/doc/attr-2.5.2

make

make DESTDIR="${build_directory}" install
