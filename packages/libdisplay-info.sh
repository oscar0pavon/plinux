#!/bin/bash
#
# libdisplay-info - reading EDID and DisplayID.
#
# The blob a monitor hands back over DDC, turned into modes, physical size,
# colorimetry and a vendor name. wlroots uses it to decide what a connected
# display can actually do, instead of the guesswork the DRM connector
# properties alone allow.
#
# It wants hwdata at build time for pnp.ids, so hwdata comes first in
# packages/order. The dependency is declared "required: false", which means a
# build without hwdata succeeds and quietly produces a library that cannot
# name a manufacturer -- exactly the kind of silent degradation the sysroot
# work was meant to stop, so the .pc has to be there.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'libdisplay-info-*.tar.gz' 'libdisplay-info-0.3.0')
cd "${directory}"

meson_setup build

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
