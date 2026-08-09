#!/bin/bash
#
# gzip - gzip, gunzip, zcat and the z* wrapper scripts.
#
# LFS 12.4 section 8.65. Half of what tar needs to be useful: most of the
# tarballs in sources/ are .tar.gz, and nothing in the image could read one.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'gzip-*.tar.xz' 'gzip-1.14')
cd "${directory}"

# musl, like the other standalone programs: nothing links against gzip.

./configure --prefix=/usr

make

make DESTDIR="${build_directory}" install

# zless, zmore and zdiff are installed but call less, more and diff, none of
# which the image has yet. They are shell scripts and cost nothing sitting
# there; they start working when those packages arrive.
