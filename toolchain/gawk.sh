#!/bin/bash
#
# LFS 6.9. Gawk-5.3.2.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

directory=$(unpack_cross 'gawk-*.tar.xz' 'gawk-5.3.2')
cd "${directory}"

# The extras directory holds optional shared-library extensions that this
# temporary gawk has no use for. Dropped from the makefile rather than built
# and deleted.
sed -i 's/extras//' Makefile.in

# --disable-mpfr, which the book does not need and this tree does.
#
# At this point in the book $LFS holds chapter 5 and nothing else, so gawk's
# check for "-lmpfr -lgmp" fails and MPFR support is simply off. Here lfs/ is
# also the staged root filesystem, so GMP and MPFR are already installed in
# it, the check succeeds, and the extension directory tries to link against
# them. That link then dies:
#
#   libtool: error: '/usr/lib/libgmp.la' is not a valid libtool archive
#
# because lfs/usr/lib/libmpfr.la records its dependency as the absolute path
# /usr/lib/libgmp.la with no sysroot marker on it. libtool reads that path
# literally, on the build machine, where only a .so exists -- the one host
# file this chapter is built to never touch.
#
# Turning the check off is the honest fix rather than the expedient one: this
# gawk is a temporary tool that exists to run configure scripts and awk
# fragments until chapter 8 replaces it, arbitrary-precision arithmetic is
# not what it is for, and off is what the book gets anyway. The final gawk is
# built by packages/, after GMP and MPFR, and keeps its MPFR support.
cross_configure --disable-mpfr

make

make DESTDIR="${LFS}" install
