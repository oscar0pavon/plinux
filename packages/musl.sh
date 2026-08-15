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
# --syslibdir has to stay inside the staged tree. obj/lib is a relative
# symlink to ../../../usr/lib which, evaluated here in the build tree,
# resolves to the *host* /usr/lib -- so --syslibdir=/lib would install this
# loader over the one the running system uses. In the image that same symlink
# resolves to /usr/lib, so binaries asking for /lib/ld-musl-x86_64.so.1 still
# find it.
#
# --libdir keeps musl's own files out of /usr/lib. musl installs its loader
# as $libdir/libc.so, and glibc installs a linker script at exactly that
# path, so with both in /usr/lib whichever is built second destroys the
# other's loader. Under /usr/lib/musl they never share a filename, and
# $syslibdir/ld-musl-x86_64.so.1 still points at the real thing.
#
# --includedir is the same argument one directory over, and it was missing.
# Two C libraries were describing themselves in one /usr/include: the header
# set in the image was whichever of them installed last, plus whatever the
# other one shipped that its rival does not. Four files outlived glibc that
# way -- stropts.h, stddef.h, stdarg.h and bits/alltypes.h -- and stropts.h
# is the one that bites, because glibc dropped it in 2.30 while musl still
# has it. vim's configure found it, included it, and got musl's
# "int ioctl(int, int, ...)" next to glibc's
# "int ioctl(int, unsigned long, ...)".
#
# Nothing reads these at build time in any case: musl-gcc's specs name
# /musl/include on the build machine with -nostdinc, and an absolute -isystem
# path is not moved by --sysroot. They are in the image for completeness,
# which is a poor reason to let them shadow the C library everything else
# here is compiled against.
CC=gcc ./configure --prefix=/usr \
                   --includedir=/usr/include/musl \
                   --libdir=/usr/lib/musl \
                   --syslibdir=/usr/lib

make

make DESTDIR="${build_directory}" install
