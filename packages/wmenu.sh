#!/bin/bash
#
# wmenu - the launcher sway's default configuration binds to $mod+d.
#
# A dmenu for Wayland: choices on stdin, a bar across the top of the output,
# the selection on stdout. The wmenu-run wrapper is what sway actually
# invokes -- it feeds wmenu the binaries in $PATH and execs whatever was
# picked. Everything it links against -- cairo, pango, wayland, xkbcommon --
# was staged by the tiers before it.
#
# Its one man page needs scdoc, which meson marks optional and the host does
# not have, so none is built; there is no option to set.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'wmenu-*.tar.gz' 'wmenu')
cd "${directory}"

meson_setup build

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
