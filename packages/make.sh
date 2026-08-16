#!/bin/bash
#
# make - LFS 12.4 section 8.69.
#
# Replaces chapter 6's cross-compiled copy. The image builds its own packages
# now, so the make that does it should be one this system produced rather than
# one the chapter 5 toolchain left behind.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'make-*.tar.gz' 'make-4.4.1')
cd "${directory}"

export CC=gcc

./configure --prefix=/usr

make

make DESTDIR="${build_directory}" install
