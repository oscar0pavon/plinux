#!/bin/bash
#
# cairo - 2D drawing.
#
# sway draws its title bars and swaybar into cairo surfaces, and pango renders
# text through cairo rather than producing pixels itself. pixman, already
# built for wlroots, is cairo's software rasteriser.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'cairo-*.tar.xz' 'cairo-1.18.4')
cd "${directory}"

# The backends are all named explicitly. Left at 'auto' cairo would look for
# X11, xcb, OpenGL and Qt on the build machine and enable whichever it found,
# which is how a package ends up with a dependency nobody chose.
#
# The image backend is the one that matters: it is cairo drawing into memory
# through pixman, which is what a Wayland client does. There is no X, and the
# GL backend is deprecated upstream.
meson_setup build           \
      -Dxlib=disabled       \
      -Dxcb=disabled        \
      -Dxlib-xcb=disabled   \
      -Dquartz=disabled     \
      -Dtee=disabled        \
      -Dsymbol-lookup=disabled \
      -Dgtk_doc=false       \
      -Dtests=disabled      \
      -Dspectre=disabled    \
      -Dfreetype=enabled    \
      -Dfontconfig=enabled  \
      -Dpng=enabled         \
      -Dzlib=enabled

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
