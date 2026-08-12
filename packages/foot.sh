#!/bin/bash
#
# foot - the terminal, so sway can open a shell.
#
# sway's default configuration already binds it: $mod+Return execs foot by
# name. Until now the binding pointed at nothing, which made the compositor
# a wallpaper. foot is Wayland-native and single-purpose -- no GTK, no
# daemon required -- so it costs only fcft and tllist beyond what the
# compositor already staged.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'foot-*.tar.gz' 'foot')
cd "${directory}"

# -Dterminfo=disabled: ncurses already ships foot's terminfo -- the image's
# database has both foot and foot-direct -- and building foot's own copy
# would run the host's tic to install a duplicate of it.
#
# -Dgrapheme-clustering=disabled: wants utf8proc, which is not staged.
#
# -Ddocs=disabled: needs scdoc, and nothing in the image can read a man page.
#
# -Dutmp-backend=none: at 'auto' this builds a setuid helper that logs
# sessions to utmp through libutempter. Neither is here: no libutempter
# staged, and nothing on this system -- not pinit, not plogin -- maintains
# utmp in the first place.
#
# -Dtests=false: they build test binaries that install nothing; meson would
# only run them under 'meson test', which the package walk never does.
meson_setup build                     \
      -Dterminfo=disabled             \
      -Dgrapheme-clustering=disabled  \
      -Ddocs=disabled                 \
      -Dutmp-backend=none             \
      -Dtests=false

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
