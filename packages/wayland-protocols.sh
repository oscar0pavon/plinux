#!/bin/bash
#
# wayland-protocols - the XML for everything the core protocol does not cover.
#
# Data only: no libraries, no programs. xdg-shell is in here, which is how a
# client gets a window at all, along with the pointer, output and idle
# extensions that a compositor is expected to implement. wlroots and sway both
# read these files at build time and generate code from them with
# wayland-scanner.
#
# It installs into /usr/share/wayland-protocols and a .pc file that says where
# that is. Nothing links it, and nothing in the running image reads it -- it
# is staged because the packages built after it look for it through
# pkg-config, and PKG_CONFIG_LIBDIR points at obj.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'wayland-protocols-*.tar.xz' 'wayland-protocols-1.45')
cd "${directory}"

# -Dtests=false: the tests validate every protocol file against the DTD, which
# needs libxml2 and wayland-scanner's validation, disabled in wayland.sh.
meson_setup build -Dtests=false

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
