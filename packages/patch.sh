#!/bin/bash
#
# patch - LFS 12.4 section 8.70.
#
# Replaces chapter 6's copy. packages/common.sh's apply_patch runs it, so a
# rebuild of the image from inside the image needs it to be here.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'patch-*.tar.xz' 'patch-2.8')
cd "${directory}"

export CC=gcc

./configure --prefix=/usr

make

make DESTDIR="${build_directory}" install
