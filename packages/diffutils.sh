#!/bin/bash
#
# diffutils - cmp, diff, diff3 and sdiff.
#
# LFS 12.4 section 8.60. gzip already installed zdiff and zcmp, which are
# shell wrappers around these two and did nothing without them.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'diffutils-*.tar.xz' 'diffutils-3.12')
cd "${directory}"

# musl, like the other standalone programs: nothing links against these.

./configure --prefix=/usr

make

make DESTDIR="${build_directory}" install
