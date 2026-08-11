#!/bin/bash
#
# libinput - input device handling for compositors.
#
# Pointer acceleration, tap-to-click, scroll methods, disable-while-typing,
# gestures, button mapping, and the quirks database that says which of those a
# given device needs. Every Wayland compositor uses it, because the
# alternative is each one reimplementing the same wrong pointer acceleration.
#
# It sits on libevdev for reading events and udev for finding devices, both of
# which are already staged.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'libinput-*.tar.gz' 'libinput-1.30.0')
cd "${directory}"

# -Ddebug-gui=false is the important one, and it defaults to *true*. Left
# alone it looks for gtk4, then gtk+-3.0, to build a diagnostic window. That
# is the trap vim fell into: configure finds the host's GTK, the build
# succeeds, and the result names libraries the image does not have. The
# sysroot would catch it now, but as a build failure rather than as a
# decision, and this is a decision.
#
# -Dlibwacom=false: also defaults true. Tablet support, and it drags in
# libgudev, glib and libxml2. There is no tablet on this machine.
#
# -Dlua-plugins=disabled: 1.30 added a Lua plugin system for writing device
# quirks as scripts, and the option defaults to 'auto', which silently enables
# it if lua-5.4 is found. There is no Lua in this image and sway does not need
# one; 'auto' would make the result depend on what the build host happens to
# have.
#
# -Dtests=false: they need the check framework and build litest, which is
# larger than libinput itself.
#
# mtdev is left enabled, and mtdev is built before this.
meson_setup build          \
      -Ddebug-gui=false    \
      -Dlibwacom=false     \
      -Dlua-plugins=disabled \
      -Dmtdev=true         \
      -Dtests=false        \
      -Dinstall-tests=false \
      -Ddocumentation=false

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
