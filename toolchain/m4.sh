#!/bin/bash
#
# LFS 6.2. M4-1.4.20: the macro processor autoconf is written in.
#
# First of chapter 6 because it is the first thing chapter 8 will need and
# because it has no dependencies beyond the C library chapter 5 just built.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

directory=$(unpack_cross 'm4-*.tar.xz' 'm4-1.4.20')
cd "${directory}"

cross_configure

make

make DESTDIR="${LFS}" install
