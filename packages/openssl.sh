#!/bin/bash
#
# openssl - libcrypto and libssl. LFS 12.4 section 8.48.
#
# udev links against libcrypto. Built without zlib support, since zlib is not
# in the image yet and compression is not something udev needs.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'openssl-*.tar.gz' 'openssl-3.5.2')
cd "${directory}"

export CC=gcc

# ./config, not ./configure: openssl has its own
./config --prefix=/usr         \
         --openssldir=/etc/ssl \
         --libdir=lib          \
         shared

make

# MANSUFFIX keeps openssl's man pages from colliding with same-named pages
# from other packages
make DESTDIR="${build_directory}" MANSUFFIX=ssl install
