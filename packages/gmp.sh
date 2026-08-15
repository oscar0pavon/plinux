#!/bin/bash
#
# gmp - arbitrary precision arithmetic. LFS 12.4 section 8.21.
#
# gcc's, mostly: the compiler folds constant expressions to the target's
# precision rather than the host's, and gmp is how. Also mpfr's and mpc's,
# which are built on it.
#
# Unlike chapters 5 and 6, where gmp is unpacked *inside* the gcc tree and
# built as part of it, this is a real package installing a shared library the
# image keeps. gcc below links against this one.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'gmp-*.tar.xz' 'gmp-6.3.0')
cd "${directory}"

export CC=gcc

# gmp's configure probes for a "long long" bug using a function declared
# with "()", which gcc 15 rejects: in C23 an empty parameter list means "no
# parameters" rather than "unspecified", so the probe fails to compile and
# configure draws the wrong conclusion. The book's sed makes it (...).
#
# Unguarded because it is idempotent by construction: after the first run
# there is no "()" left on that line for the pattern to match.
sed -i '/long long t1;/,+1s/()/(...)/' configure

# --enable-cxx because mpfr and gcc want the C++ interface.
#
# No -march here beyond what common.sh sets. gmp's own default is to detect
# the build CPU and emit code for it, which is the same thing this project
# does everywhere and is fine for an image that only runs on this machine or
# in its VM. PLINUX_MARCH=none is the escape for a portable image, and it
# leaves gmp's own detection in place -- --host=none-linux-gnu is the book's
# lever for that, and it is not pulled here.
./configure --prefix=/usr    \
            --enable-cxx     \
            --disable-static \
            --docdir=/usr/share/doc/gmp-6.3.0

make

make DESTDIR="${build_directory}" install
