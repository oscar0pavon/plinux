#!/bin/bash
#
# gawk - awk. LFS 12.4 section 8.61.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'gawk-*.tar.xz' 'gawk-5.3.2')
cd "${directory}"

# keeps the extras/ directory out of the install
sed -i 's/extras//' Makefile.in

./configure --prefix=/usr

make

# gawk-5.3.2 is a hard link to gawk, and the build system leaves an existing
# one alone rather than repointing it. Removing it first means a rebuild
# installs the binary just built instead of keeping the previous one.
rm -f "${build_directory}/usr/bin/gawk-5.3.2"

make DESTDIR="${build_directory}" install

# the install creates awk as a symlink to gawk; the man page needs the same
ln -sf gawk.1 "${build_directory}/usr/share/man/man1/awk.1"
