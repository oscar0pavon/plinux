#!/bin/bash
#
# gettext - internationalization. LFS 12.4 section 8.33.
#
# Chapter 7 installed three programs out of this package by copying them into
# /usr/bin -- msgfmt, msgmerge and xgettext -- because that was all a build
# environment needed. This is the whole package: the libraries as well, which
# is what anything linking libintl wants.
#
# After perl, which its autopoint and several of its tools are written in.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'gettext-*.tar.xz' 'gettext-0.26')
cd "${directory}"

export CC=gcc

./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/gettext-0.26

make

make DESTDIR="${build_directory}" install

# Installed 644 by the makefile, which is wrong for something meant to be
# LD_PRELOADed. The book fixes it the same way.
chmod -v 0755 "${build_directory}/usr/lib/preloadable_libintl.so"
