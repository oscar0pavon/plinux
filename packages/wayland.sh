#!/bin/bash
#
# wayland - the display protocol library, and the scanner that generates code
# from its XML.
#
# Two things in one tarball. libwayland-client and libwayland-server go into
# the image; wayland-scanner is a build tool, run on this machine by every
# package that has protocol XML to turn into C. Both are built, because the
# scanner has to match the libraries it generates code for.
#
# From BLFS. Not in the LFS book, which stops at a console system.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'wayland-*.tar.xz' 'wayland-1.24.0')
cd "${directory}"

# -Ddocumentation=false skips the manual, which wants doxygen, xsltproc and
# the docbook stylesheets -- none of which this image will ever have, and none
# of which produce anything that runs.
#
# -Ddtd_validation=false drops the one remaining dependency, libxml2. It only
# validates protocol XML against the DTD while scanning, so it catches
# mistakes in protocol files being written, not in the ones being consumed.
# Worth revisiting if protocols are ever authored here.
#
meson_setup build              \
      -Ddocumentation=false    \
      -Ddtd_validation=false   \
      -Dtests=false

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
