#!/bin/bash
#
# freetype - the font engine: turns an outline into pixels.
#
# Built twice. harfbuzz needs freetype to read a font, and freetype uses
# harfbuzz to improve the autohinter's decisions on scripts where the hints
# depend on how glyphs join. The way out of the circle is to build freetype
# once without harfbuzz, build harfbuzz against it, then build freetype again
# with harfbuzz present. PLINUX_FREETYPE_PASS=2 is the second pass, and
# packages/freetype-harfbuzz.sh is what sets it.
#
# It needs a second script rather than a second line in packages/order,
# because the stamp is keyed on the package name: a repeated "freetype" line
# would find obj/.packages/freetype already there and report "have freetype".

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'freetype-*.tar.xz' 'freetype-2.14.1')
cd "${directory}"

# The first pass has to say so explicitly. Left to itself, configure would
# find harfbuzz if a previous build had already installed it, which would make
# the result depend on whether obj was clean.
if [ "${PLINUX_FREETYPE_PASS:-1}" = "2" ]; then
  harfbuzz_option=--with-harfbuzz=yes

  # unpack() reuses a tree that is already there, so the second pass would
  # otherwise reconfigure on top of the first pass's objects.
  make distclean > /dev/null 2>&1 || true
else
  harfbuzz_option=--with-harfbuzz=no
fi

# --enable-freetype-config installs the freetype-config script some packages
# still look for. --without-librsvg: SVG glyph rendering, which would want
# librsvg and everything under it.
./configure --prefix=/usr           \
            --disable-static        \
            --enable-freetype-config \
            --without-librsvg       \
            ${harfbuzz_option}

make

make DESTDIR="${build_directory}" install
