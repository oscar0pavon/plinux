#!/bin/bash
#
# LFS 6.6. Diffutils-3.12.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

directory=$(unpack_cross 'diffutils-*.tar.xz' 'diffutils-3.12')
cd "${directory}"

# gl_cv_func_strcasecmp_works=y
#
# gnulib checks strcasecmp by compiling a program and running it, which a
# cross-compile cannot do -- and this particular check has no fall-back value
# for that case, so configure stops rather than guessing. Upstream has fixed
# it, but applying the fix means re-running autoconf, which the book will not
# assume a host can do.
#
# y is the right answer: the strcasecmp being asked about is glibc 2.42's, and
# it works.
cross_configure gl_cv_func_strcasecmp_works=y

make

make DESTDIR="${LFS}" install
