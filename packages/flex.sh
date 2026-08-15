#!/bin/bash
#
# flex - the lexical analyser generator. LFS 12.4 section 8.15.
#
# Wanted by build systems rather than by the running image. After m4 and
# bison, both of which it uses.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'flex-*.tar.gz' 'flex-2.6.4')
cd "${directory}"

export CC=gcc

./configure --prefix=/usr                     \
            --docdir=/usr/share/doc/flex-2.6.4 \
            --disable-static

make

make DESTDIR="${build_directory}" install

# Some build systems still call the predecessor by name. lex is flex run in
# emulation mode.
ln -sfv flex   "${build_directory}/usr/bin/lex"
ln -sfv flex.1 "${build_directory}/usr/share/man/man1/lex.1"
