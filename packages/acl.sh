#!/bin/bash
#
# acl - access control lists. LFS 12.4 section 8.25.
#
# udev links against libacl to set permissions on device nodes.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'acl-*.tar.xz' 'acl-2.3.2')
cd "${directory}"

export CC=gcc

# Deliberately built against the host's libattr rather than the copy attr
# just staged. Pointing LDFLAGS at obj/usr/lib puts the *image's* glibc ahead
# of the host's, so configure's test programs link against a libc they cannot
# run and it stops at "cannot run C compiled programs". The library this
# produces records libattr.so.1 as a plain dependency, which resolves to the
# staged copy at runtime in the image.

./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/acl-2.3.2

make

make DESTDIR="${build_directory}" install
