#!/bin/bash
#
# pango - text layout.
#
# The layer that takes a string, a font description and a width, and produces
# positioned glyphs on lines: it picks fonts through fontconfig, shapes runs
# through harfbuzz, orders them with fribidi, and draws through cairo. sway
# uses it for every piece of text it puts on screen.
#
# The last package of the text stack, and the one that needed all the others.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'pango-*.tar.xz' 'pango-1.56.4')
cd "${directory}"

# -Dxft=disabled and -Dlibthai=disabled are the auto-detected backends: Xft is
# X11 font rendering, and libthai is word breaking for Thai, which needs a
# dictionary this image does not carry.
#
# -Dcairo=enabled is not optional here despite the name -- sway calls
# pango_cairo_show_layout, which does not exist without it.
meson_setup build              \
      -Dxft=disabled           \
      -Dlibthai=disabled       \
      -Dcairo=enabled          \
      -Dfreetype=enabled       \
      -Dfontconfig=enabled     \
      -Dintrospection=disabled \
      -Ddocumentation=false    \
      -Dbuild-testsuite=false  \
      -Dbuild-examples=false

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
