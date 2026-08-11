#!/bin/bash
#
# seatd - hands out the DRM and input devices.
#
# A compositor has to open /dev/dri/card0 and the evdev nodes, and give them
# up again when the session switches away. Doing that as root is the thing
# everyone is trying to stop doing; the alternative on most systems is
# logind, which is part of systemd, which this image does not have. seatd is
# the third option: a small daemon that holds the devices and passes file
# descriptors over a socket, plus libseat, which is what wlroots links.
#
# init_os already starts it if it is present, and sys/root/shell_config.sh
# already sets LIBSEAT_BACKEND=seatd. Until now neither did anything, because
# the binary was never built.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'seatd-*.tar.gz' 'seatd-0.9.1')
cd "${directory}"

# -Dlibseat-logind=disabled: there is no logind here and there will not be
# one. Left at 'auto' it would find the host's libsystemd through pkg-config
# if that were ever staged, and produce a libseat that prefers a backend the
# image cannot provide.
#
# -Dlibseat-builtin=enabled compiles the server into the library as well, so a
# compositor can drive the devices itself when no seatd daemon is running.
# That is what makes the console fallback work: sway started from the tty1
# login has a seat either way.
#
# -Dman-pages=disabled: needs scdoc, and nothing in the image can read a man
# page yet in any case.
meson_setup build               \
      -Dlibseat-logind=disabled \
      -Dlibseat-seatd=enabled   \
      -Dlibseat-builtin=enabled \
      -Dserver=enabled          \
      -Dexamples=disabled       \
      -Dman-pages=disabled

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
