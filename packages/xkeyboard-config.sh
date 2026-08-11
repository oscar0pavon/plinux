#!/bin/bash
#
# xkeyboard-config - the keyboard layout data.
#
# Every layout, variant and option that libxkbcommon can be asked for is a
# file in here, under /usr/share/X11/xkb. "us" and "latam" are two of them.
# The name is misleading: X11 is where the format came from, but Wayland
# compositors read exactly the same files, through libxkbcommon rather than
# through an X server.
#
# Data only, like wayland-protocols and hwdata. Nothing links it.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc

directory=$(unpack 'xkeyboard-config-*.tar.xz' 'xkeyboard-config-2.45')
cd "${directory}"

# -Dxorg-rules-symlinks=false: those are compatibility links named xorg* for
# software that asks for the rules file by that name. There is no X server
# here and nothing asks.
#
# -Dcompat-rules=true is kept, because it is what maps the old layout names
# onto the current ones, and configurations in the wild are full of them.
meson_setup build                  \
      -Dxorg-rules-symlinks=false  \
      -Dcompat-rules=true

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
