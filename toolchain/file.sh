#!/bin/bash
#
# LFS 6.7. File-5.46.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

# Fresh, because cross_configure below configures in the tree and the native
# configure above it then refuses the tree as already configured on the next
# run. unpack_cross_fresh has the details.
directory=$(unpack_cross_fresh 'file-*.tar.gz' 'file-5.46')
cd "${directory}"

# A native copy of file, built first and used by the cross build.
#
# The magic database is compiled by the file command itself, and it has to be
# the *same version* as the one being built -- an older host file produces a
# database this one cannot read. So a native 5.46 is built here and handed to
# the cross build below as FILE_COMPILE.
#
# The --disable options exist because this configure enables a feature when it
# finds the library, without checking for the header. On a host carrying
# libbz2 or libseccomp without their -devel files that fails to compile, and
# none of it is wanted in a throwaway binary anyway.
rm -rf build
mkdir -p build
pushd build > /dev/null
  ../configure --disable-bzlib      \
               --disable-libseccomp \
               --disable-xzlib      \
               --disable-zlib
  make
popd > /dev/null

cross_configure

make FILE_COMPILE="$(pwd)/build/src/file"

make DESTDIR="${LFS}" install

# The .la records link paths from this build, which are this workstation's.
# libtool follows them out of the sysroot given the chance.
rm -v "${LFS}/usr/lib/libmagic.la"
