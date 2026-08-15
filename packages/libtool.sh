#!/bin/bash
#
# libtool - the generic library support script. LFS 12.4 section 8.37.
#
# Wanted by packages that regenerate their build system, and by anything
# calling libtoolize. Not by the running image.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'libtool-*.tar.xz' 'libtool-2.5.4')
cd "${directory}"

export CC=gcc

./configure --prefix=/usr

make

make DESTDIR="${build_directory}" install

# Only the test suite uses it.
rm -fv "${build_directory}/usr/lib/libltdl.a"
