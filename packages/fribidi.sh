#!/bin/bash
#
# fribidi - the Unicode bidirectional algorithm.
#
# Deciding the order glyphs appear in when a string mixes left-to-right and
# right-to-left text. pango requires it, and requires it even for text that is
# entirely Latin, because the algorithm is what decides that too.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc

directory=$(unpack 'fribidi-*.tar.xz' 'fribidi-1.0.16')
cd "${directory}"

meson_setup build -Ddocs=false

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
