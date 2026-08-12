#!/bin/bash
#
# tllist - a typed linked list, as a single C header.
#
# fcft and foot are by the same author and both say dependency('tllist') in
# their meson.build. There is nothing to compile; the whole install is one
# header and the .pc file that lets the other two find it.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

# Codeberg's generated archives name their top directory after the
# repository alone, so this unpacks to src/tllist with no version in it.
# The same goes for fcft, foot and wmenu.
directory=$(unpack 'tllist-*.tar.gz' 'tllist')
cd "${directory}"

meson_setup build

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
