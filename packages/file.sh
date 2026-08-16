#!/bin/bash
#
# file - identifies a file by its contents. LFS 12.4 section 8.11.
#
# Replaces chapter 6's copy, which was built twice: once natively so it could
# compile its own magic database, and once cross-compiled. Neither of those is
# needed here -- this is a native build in a chroot, so the file being built
# and the file compiling the database are the same version on the same
# machine, which is the condition chapter 6 had to work around.
#
# libmagic is what util-linux's --with-libmagic would want, and packages/
# util-linux.sh currently declines it.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'file-*.tar.gz' 'file-5.46')
cd "${directory}"

export CC=gcc

./configure --prefix=/usr

make

make DESTDIR="${build_directory}" install
