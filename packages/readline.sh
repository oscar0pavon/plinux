#!/bin/bash
#
# readline - command line editing. LFS 12.4 section 8.12.
#
# fdisk and sfdisk from util-linux link libreadline and could not start
# without it. Needs ncurses, which provides the terminal handling it uses.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'readline-*.tar.gz' 'readline-8.3')
cd "${directory}"

export CC=gcc

# Reinstalling moves the old libraries aside as <name>.old, which can trigger
# a linking bug in ldconfig. These two seds drop that, as the book does.
sed -i '/MV.*old/d' Makefile.in
sed -i '/{OLDSUFF}/c:' support/shlib-install

# No rpath: the libraries install to the standard location, so a hardcoded
# search path buys nothing and can be actively harmful.
sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf

./configure --prefix=/usr    \
            --disable-static \
            --with-curses    \
            --docdir=/usr/share/doc/readline-8.3

# SHLIB_LIBS makes readline link libncursesw rather than looking for a
# separate termcap, which is not installed here
make SHLIB_LIBS="-lncursesw"

make DESTDIR="${build_directory}" SHLIB_LIBS="-lncursesw" install
