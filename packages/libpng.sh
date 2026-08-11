#!/bin/bash
#
# libpng - PNG reading and writing.
#
# cairo uses it for image surfaces, which is how a compositor loads anything
# that is not a solid colour. It also closes one of the two dependencies
# ./build.sh check has been reporting since glibc was staged: memusagestat
# wants libpng16 and libgd. libgd is still missing and still not worth a
# package.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc

directory=$(unpack 'libpng-*.tar.gz' 'libpng-1.6.50')
cd "${directory}"

# The GitHub archive is the git tree, not a release tarball, so it has no
# configure script. autogen.sh generates one.
if [ ! -x configure ]; then
  ./autogen.sh --maintainer > /dev/null
fi

./configure --prefix=/usr --disable-static

make

make DESTDIR="${build_directory}" install
