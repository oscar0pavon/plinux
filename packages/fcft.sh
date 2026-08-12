#!/bin/bash
#
# fcft - the font library foot renders with.
#
# It sits on top of the text stack that is already staged: fontconfig picks
# the file, freetype rasterises the glyphs, harfbuzz shapes them, and the
# result comes back as pixman images, which is what a terminal blits into
# its cells. fcft's contribution is the cache in the middle, so a screenful
# of text does not rasterise the same glyph a thousand times.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'fcft-*.tar.gz' 'fcft')
cd "${directory}"

# -Dgrapheme-shaping=enabled: harfbuzz is staged, and without it a combining
# accent or an emoji sequence renders one code point at a time. Enabled
# explicitly rather than left at auto, so losing it is a configure error
# instead of a silent downgrade.
#
# -Drun-shaping=disabled: shaping whole text runs additionally needs
# utf8proc, which is not staged. foot shapes cell by cell, so a terminal
# does not miss it.
#
# -Ddocs=disabled: needs scdoc, and nothing in the image can read a man page.
#
# The SVG backend is left at its default, the bundled nanosvg -- it is
# vendored in the tarball, not a meson wrap, so nodownload does not block it.
# That is what draws color emoji fonts whose glyphs are SVG documents.
meson_setup build                 \
      -Dgrapheme-shaping=enabled  \
      -Drun-shaping=disabled      \
      -Ddocs=disabled

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
