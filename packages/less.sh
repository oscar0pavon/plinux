#!/bin/bash
#
# less - the pager.
#
# LFS 12.4 section 8.42. Two things were waiting on this: gzip installed
# zless, which is a wrapper around it, and the image already carries a
# /usr/share/man full of man pages with nothing able to display them.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'less-*.tar.gz' 'less-679')
cd "${directory}"

# glibc, not musl: less links libncursesw for the terminal handling, the
# same reason vim does.
export CC=gcc

# --sysconfdir=/etc so lesskey looks for /etc/sysless rather than somewhere
# under /usr/etc
./configure --prefix=/usr --sysconfdir=/etc

make

make DESTDIR="${build_directory}" install
