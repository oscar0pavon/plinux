#!/bin/bash
#
# glib - GObject, GIO and the C utility layer under them.
#
# Here because pango is built on it: GObject is pango's type system, and every
# pango API takes or returns one. Nothing else in this image wants glib, and
# it is by some margin the largest thing pulled in by a decision about text
# rendering.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'glib-*.tar.xz' 'glib-2.86.0')
cd "${directory}"

# -Dintrospection=disabled: GObject introspection generates typelibs for
# language bindings, needs gobject-introspection, and nothing here has a
# binding to generate.
#
# -Dtests=false and -Dglib_debug=disabled keep the build to what ships.
#
# -Dselinux=disabled and -Dlibelf=disabled are the auto-detected ones. libelf
# is now staged for mesa, so leaving it alone would silently link glib against
# it for gresource inspection that nothing here does.
#
# -Dman-pages=disabled wants rst2man.
meson_setup build                \
      --sysconfdir=/etc          \
      --localstatedir=/var       \
      -Dintrospection=disabled   \
      -Dselinux=disabled         \
      -Dlibelf=disabled          \
      -Dman-pages=disabled       \
      -Ddtrace=disabled          \
      -Dsystemtap=disabled       \
      -Dsysprof=disabled         \
      -Dtests=false              \
      -Dglib_debug=disabled      \
      -Dnls=disabled

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
