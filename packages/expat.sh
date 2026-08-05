#!/bin/bash
#
# expat - XML parser. LFS 12.4 section 8.40.
#
# Here because dbus links against it: dbus-daemon parses its configuration
# and every service file with expat.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'expat-*.tar.xz' 'expat-2.7.1')
cd "${directory}"

export CC=gcc

./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/expat-2.7.1

make

make DESTDIR="${build_directory}" install
