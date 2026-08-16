#!/bin/bash
#
# musl - the system C library.
#
# Until this is installed the image has no dynamic loader at all and every
# package has to be linked statically, which does not scale past a handful of
# small programs.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'musl-*.tar.gz' 'musl-1.2.5')
cd "${directory}"

# Built with the host compiler: musl-gcc is a wrapper around an existing musl
# installation, so using it to build musl itself would be circular.
#
# Everything under /musl, which is where this workstation keeps it too, and
# the one exception that cannot be.
#
# --prefix, --libdir and --includedir put the headers, the libraries, the crt
# files, the specs and musl-gcc itself in /musl. Nothing of musl is in /usr
# after this, which is the arrangement the build host uses and the reason it
# has never had the collisions the image did:
#
#   glibc installs a linker script at /usr/lib/libc.so and musl installs its
#   loader at $libdir/libc.so, so with both under /usr/lib whichever built
#   second destroyed the other's. That was worked around by putting musl in
#   /usr/lib/musl, and then again in /usr/include/musl when it turned out two
#   C libraries were also describing themselves in one /usr/include -- four
#   headers outlived glibc that way, stropts.h among them, which vim's
#   configure found and included next to glibc's declarations.
#
# Both were the same problem answered one directory at a time. /musl answers
# it once.
#
# --syslibdir is the exception and stays /usr/lib. It is where the *loader*
# goes, and the loader's path is not a matter of preference: it is written
# into the PT_INTERP of every musl binary ever linked here, and the kernel
# resolves it before any of this tree's arrangement exists. Moving it would
# invalidate every musl binary already built. The host has exactly the same
# single escape -- one symlink at /usr/lib/ld-musl-x86_64.so.1 -- for exactly
# the same reason.
CC=gcc ./configure --prefix=/musl \
                   --includedir=/musl/include \
                   --libdir=/musl/lib \
                   --syslibdir=/usr/lib

make

make DESTDIR="${build_directory}" install

# The tree musl used to install into. Staging adds and overwrites but never
# deletes, so without this an image built before the move keeps a second,
# older copy of every musl header and library -- and musl-gcc's specs named
# those paths, so the stale set is exactly the one a mistake would find.
rm -rf "${build_directory}/usr/lib/musl" "${build_directory}/usr/include/musl"
