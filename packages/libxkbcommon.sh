#!/bin/bash
#
# libxkbcommon - turning key codes into symbols.
#
# The compositor gets a scancode from the kernel and has to decide what
# character that is, given the layout, the modifiers held, and any dead keys
# in flight. That is this library. It replaced the equivalent code inside the
# X server, and wlroots and sway both depend on it.
#
# It reads its data from xkeyboard-config at run time, so that package is
# built first and this one is pointed at where it landed.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'libxkbcommon-*.tar.gz' 'libxkbcommon-xkbcommon-1.11.0')
cd "${directory}"

# -Denable-x11=false: the X11 half needs libxcb, and there is no X server
# here. -Denable-docs=false wants doxygen.
#
# -Denable-xkbregistry=false is the one worth explaining. libxkbregistry is
# how a desktop environment enumerates the available layouts to put them in a
# menu; it parses the rules XML and so needs libxml2, which this image does
# not have. sway does not use it -- the layout is named in the config file --
# so this drops a dependency rather than a capability.
#
# -Denable-wayland=true builds the interactive-wayland tool, which is a
# genuinely useful way to check what a layout actually produces.
#
# -Ddefault-layout=us matches this machine. It is only the fallback for a
# caller that names no layout; sway's xkb_layout overrides it.
meson_setup build                            \
      -Dxkb-config-root=/usr/share/X11/xkb   \
      -Ddefault-layout=us                    \
      -Denable-x11=false                     \
      -Denable-docs=false                    \
      -Denable-xkbregistry=false             \
      -Denable-wayland=true                  \
      -Denable-tools=true                    \
      -Denable-bash-completion=false

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
