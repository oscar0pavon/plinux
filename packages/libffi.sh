#!/bin/bash
#
# libffi - calling a function whose signature is only known at run time.
#
# An LFS package plinux never had a reason to build. Wayland is the reason:
# its protocol dispatch reads argument types out of the message signature that
# wayland-scanner generated from the XML, and builds the call from them.
#
# The first package of the Wayland stack, so the choice of C library is made
# here and everything after it follows: glibc, not musl. Mesa and LLVM are not
# realistically musl-buildable on this machine, a stack cannot be split
# between two C libraries, and udev -- which libinput will need -- is already
# glibc.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'libffi-*.tar.gz' 'libffi-3.5.2')
cd "${directory}"

# --disable-exec-static-tramp turns off the static trampolines, which need a
# mapping that is writable and then executable. Nothing here uses them, and
# the default probes the build machine for memfd_create, which makes the
# result depend on the host rather than on the image.
#
# --disable-multi-os-directory keeps the libraries in /usr/lib rather than a
# triplet subdirectory nothing in this image searches.
./configure --prefix=/usr                \
            --disable-static             \
            --disable-exec-static-tramp  \
            --disable-multi-os-directory

make

make DESTDIR="${build_directory}" install

# libffi installs its headers under /usr/lib/libffi-<version>/include and
# points its .pc at them. Nothing else looks there, and the path carries the
# version, so an update would silently strip every consumer of ffi.h. LFS
# moves them; do the same and correct the .pc to match, or the next package
# gets an -I to a directory that is no longer there.
if [ -d "${build_directory}"/usr/lib/libffi-* ]; then
  mv -v "${build_directory}"/usr/lib/libffi-*/include/*.h \
        "${build_directory}/usr/include/"
  rm -rf "${build_directory}"/usr/lib/libffi-*

  sed -i 's|^includedir=.*|includedir=${prefix}/include|; s|^toolexeclibdir=.*|toolexeclibdir=${libdir}|' \
         "${build_directory}/usr/lib/pkgconfig/libffi.pc"
fi
