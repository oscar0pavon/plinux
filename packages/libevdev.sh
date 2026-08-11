#!/bin/bash
#
# libevdev - a wrapper over the kernel's input event protocol.
#
# Reading /dev/input/event* directly means handling event frames, SYN_DROPPED
# resynchronisation and the difference between what a device advertises and
# what it sends. libevdev does that once, correctly, and libinput in tier 3 is
# built on it.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc

directory=$(unpack 'libevdev-*.tar.xz' 'libevdev-1.13.4')
cd "${directory}"

# -Dtests=disabled: they need the check unit test framework, and valgrind.
# -Ddocumentation=disabled: doxygen.
#
# -Dtools=enabled is kept. libevdev-tweak-device and touchpad-edge-detector
# are small, and on a machine where the input stack is being brought up for
# the first time, being able to dump what a device actually reports is worth
# more than the space.
meson_setup build              \
      -Dtests=disabled         \
      -Ddocumentation=disabled \
      -Dtools=enabled

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
