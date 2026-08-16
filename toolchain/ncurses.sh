#!/bin/bash
#
# LFS 6.3. Ncurses-6.5-20250809: terminal handling.
#
# The dated snapshot, not the 6.5 release in sources/ that packages/ncurses.sh
# builds. Plain 6.5 does not compile its C++ binding under gcc 15 -- the
# reasoning is in packages/ncurses.sh, which drops the binding entirely to get
# around it -- and this chapter configures --with-cxx-shared, so it needs the
# snapshot where that is fixed.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

# Fresh, because the cross build below configures in the tree and leaves its
# generated sources there, where the native build above it picks them up on
# the next run. unpack_cross_fresh has the details.
directory=$(unpack_cross_fresh 'ncurses-6.5-2025*.tgz' 'ncurses-6.5-20250809')
cd "${directory}"

# tic, built to run on *this* machine rather than on the target.
#
# tic compiles terminfo descriptions, and ncurses' own install runs it to
# generate the terminfo database. A cross-compiled tic cannot be executed by
# the build that needs it, so a native one is built first and put in
# $LFS/tools/bin, which is at the front of PATH.
#
# Removed and rebuilt rather than reused: this is a native build living inside
# a tree that is about to be configured for cross-compilation, and the two
# leave incompatible objects in the same place.
rm -rf build
mkdir -p build
pushd build > /dev/null
  ../configure --prefix="${LFS}/tools" AWK=gawk
  make -C include
  make -C progs tic
  install progs/tic "${LFS}/tools/bin"
popd > /dev/null

# --with-manpage-format=normal
#   Uncompressed manual pages, whatever this host does with its own.
#
# --with-shared / --without-normal
#   Shared libraries, no static ones.
#
# --with-cxx-shared
#   The C++ binding, shared. This is the option that needs the snapshot.
#
# --without-ada
#   The host has no Ada compiler in the chroot, and configure would otherwise
#   notice one here and build against it.
#
# --disable-stripping
#   Never strip a cross-compiled binary with the host's strip.
#
# --without-debug
#   No debug libraries.
#
# AWK=gawk
#   Some mawk versions cannot build this package, and configure will take
#   whichever awk it finds first.
cross_configure --mandir=/usr/share/man      \
                --with-manpage-format=normal \
                --with-shared                \
                --without-normal             \
                --with-cxx-shared            \
                --without-debug              \
                --without-ada                \
                --disable-stripping          \
                AWK=gawk

make

make DESTDIR="${LFS}" install

# Everything here links libncursesw, the wide-character library. Packages that
# ask for -lncurses get this symlink and the wide build behind it.
ln -sfv libncursesw.so "${LFS}/usr/lib/libncurses.so"

# curses.h defines its data structures two ways behind _XOPEN_SOURCE_EXTENDED:
# an 8-bit layout matching libncurses.so and a wide layout matching
# libncursesw.so. Since the symlink above makes every -lncurses a libncursesw,
# the header has to stop offering the 8-bit layout -- otherwise a program
# compiled without the macro gets structures that do not match the library it
# will be linked against.
sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "${LFS}/usr/include/curses.h"
