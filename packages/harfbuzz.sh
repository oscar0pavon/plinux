#!/bin/bash
#
# harfbuzz - text shaping.
#
# Turning a string into positioned glyphs. Which is not one glyph per
# character: ligatures, contextual forms, marks that reposition over the
# letter they attach to, and scripts where the shape of a letter depends on
# its neighbours. pango calls it for every run of text.
#
# Built between the two freetype passes.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'harfbuzz-*.tar.xz' 'harfbuzz-11.5.1')
cd "${directory}"

# -Dglib=enabled is what pango needs: pango passes GLib types across the
# boundary, and a harfbuzz built without glib gives pango a link error rather
# than a fallback.
#
# -Dicu=disabled: harfbuzz can use ICU for Unicode properties, but its own
# implementation covers what is needed and ICU is 30M of data tables.
#
# -Ddocs=disabled wants gtk-doc; -Dtests=disabled wants the test fonts.
meson_setup build          \
      -Dglib=enabled       \
      -Dfreetype=enabled   \
      -Dcairo=disabled     \
      -Dicu=disabled       \
      -Dgraphite2=disabled \
      -Dchafa=disabled     \
      -Ddocs=disabled      \
      -Dtests=disabled     \
      -Dintrospection=disabled

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
