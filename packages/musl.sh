#!/bin/bash
#
# musl - the system C library.
#
# Until this is installed the image has no dynamic loader at all and every
# package has to be linked statically, which does not scale past a handful of
# small programs.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

cd "${src_directory}/musl"

# Built with the host compiler: musl-gcc is a wrapper around an existing musl
# installation, so using it to build musl itself would be circular.
#
# --syslibdir has to stay inside the staged tree. obj/lib is a relative
# symlink to ../../../usr/lib which, evaluated here in the build tree,
# resolves to the *host* /usr/lib -- so --syslibdir=/lib would install this
# loader over the one the running system uses. In the image that same symlink
# resolves to /usr/lib, so binaries asking for /lib/ld-musl-x86_64.so.1 still
# find it.
CC=gcc ./configure --prefix=/usr --syslibdir=/usr/lib

make

make DESTDIR="${build_directory}" install
