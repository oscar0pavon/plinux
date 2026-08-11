#!/bin/bash
#
# libglvnd - vendor-neutral OpenGL dispatch.
#
# Without it, mesa's libEGL and libGLESv2 *are* the driver, and there is no
# desktop OpenGL library at all: mesa gates its own libGL on GLX, and there is
# no X here. With it, libOpenGL, libEGL and the GLES libraries are thin
# dispatch layers and mesa installs itself behind them as a vendor, named in a
# JSON file under /usr/share/glvnd. That is what an application linking
# -lOpenGL gets.
#
# Built without GLX, which is not a preference. libglvnd's meson.build:
#
#   if get_option('glx').enabled() and not dep_x11.found()
#     error('Cannot build GLX support without X11.')
#
# and libGL.so.1 is built only inside "if with_glx". So libGL.so.1 is not
# reachable on this system without adding libX11, libxcb, libXext and
# xorgproto -- the X client stack, for link compatibility with programs that
# say -lGL, on a system with no X server. That is a real decision and not one
# to make as a side effect of wanting desktop OpenGL, which libOpenGL.so.0
# already provides.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'libglvnd-*.tar.gz' 'libglvnd-v1.7.0')
cd "${directory}"

meson_setup build     \
      -Dx11=disabled  \
      -Dglx=disabled  \
      -Degl=true      \
      -Dgles1=true    \
      -Dgles2=true    \
      -Dasm=enabled

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
