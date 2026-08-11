#!/bin/bash
#
# fontconfig - finding a font by description rather than by filename.
#
# "monospace 11" has to become a file on disk, and that is this. pango asks
# it, cairo asks it, and sway's font setting goes through both.
#
# It builds a cache at install time and again on first use; the image has no
# fonts installed yet, so the cache will be empty until one is added. That is
# a gap worth remembering: text will render as boxes until there is a font.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc

directory=$(unpack 'fontconfig-*.tar.gz' 'fontconfig-2.17.1')
cd "${directory}"

# -Ddoc=disabled: the documentation wants docbook and gperf output.
# -Dtests=disabled: they need fonts, which the build tree does not have.
#
# --sysconfdir=/etc because fontconfig's configuration lives in
# /etc/fonts/local.conf and the path is compiled in.
meson_setup build              \
      --sysconfdir=/etc        \
      --localstatedir=/var     \
      -Ddoc=disabled           \
      -Dtests=disabled         \
      -Dtools=enabled

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
