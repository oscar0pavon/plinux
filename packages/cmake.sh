#!/bin/bash
#
# cmake - a build system. BLFS, not LFS.
#
# Here for glslang, which builds with nothing else, which is here for mesa's
# Vulkan driver. Nothing else in this image uses cmake today; it is likely to
# be wanted by whatever BLFS package comes next, which is part of why the
# 3.x line is chosen over 4.x below.
#
# cmake bootstraps: it compiles a minimal copy of itself with make and a C++
# compiler, then uses that to configure the real build. So it does not need a
# cmake to exist first, which is the only reason this ordering is possible.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'cmake-*.tar.gz' 'cmake-3.31.6')
cd "${directory}"

export CC=gcc

# cmake's GNUInstallDirs puts 64-bit libraries in lib64 when it thinks the
# system wants that. This image has no /usr/lib64 as a real directory -- it is
# a symlink onto usr/lib, and the book is emphatic that a real one breaks
# things -- so every project cmake ever configures would otherwise be told to
# install somewhere nothing searches. BLFS makes the same edit.
#
# Idempotent: after the first run there is no "lib64" left on those lines.
sed -i '/"lib64"/s/64//' Modules/GNUInstallDirs.cmake

# --system-libs is deliberately not passed.
#
# It would have cmake link the system copies of curl, libarchive, libuv,
# nghttp2, jsoncpp, cppdap and librhash -- seven packages this image does not
# have and would have to gain to build one build tool that exists to build one
# other build tool. The bundled copies are what cmake ships and tests against,
# and they are statically linked into the cmake binary rather than installed,
# so nothing else in the image is affected by the choice.
./bootstrap --prefix=/usr                        \
            --parallel="$(nproc)"                \
            --docdir=/share/doc/cmake-3.31.6

make

make DESTDIR="${build_directory}" install
