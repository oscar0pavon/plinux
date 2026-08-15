#!/bin/bash
#
# bzip2 - the older block-sorting compressor. LFS 12.4 section 8.7.
#
# Here because four source tarballs are .tar.bz2 and tar cannot unpack them
# without it: mtdev, elfutils, pcre2 and dejavu-fonts. The build host has
# bzip2, so this never came up while packages were unpacked out there; in the
# chroot tar stopped with
#
#   tar (child): lbzip2: Cannot exec: No such file or directory
#
# which is tar reaching for a decompressor that is not installed.
#
# Placed with zlib, xz and zstd. Unlike those three, nothing in the image
# links libbz2 -- it is here to read tarballs -- but it is built as a shared
# library anyway because that is what the book does and what anything finding
# it later would expect.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'bzip2-*.tar.gz' 'bzip2-1.0.8')
cd "${directory}"

export CC=gcc

# Installs the documentation, which the tarball's Makefile does not.
apply_patch 'bzip2-*-install_docs-*.patch'

# bzip2 has no configure; both edits are to the Makefile.
#
# The first makes the symlinks it installs relative -- as shipped they are
# absolute $(PREFIX)/bin paths, which point at the build host when the
# install is staged under DESTDIR. The second moves the man pages from
# /usr/man to /usr/share/man.
#
# Both are idempotent: after the first run neither pattern matches.
sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
sed -i 's@(PREFIX)/man@(PREFIX)/share/man@g' Makefile

# The shared library is built by a separate makefile, and "make clean" between
# the two is the book's -- the object files from the shared build are compiled
# -fPIC and are not what the static targets want.
make -f Makefile-libbz2_so
make clean

make

make PREFIX="${build_directory}/usr" install

# The shared library and the shared-linked binary, neither of which the
# install target handles.
cp -av libbz2.so.* "${build_directory}/usr/lib"
ln -sfv libbz2.so.1.0.8 "${build_directory}/usr/lib/libbz2.so"
cp -v bzip2-shared "${build_directory}/usr/bin/bzip2"

for link in bzcat bunzip2; do
  ln -sfv bzip2 "${build_directory}/usr/bin/${link}"
done

rm -fv "${build_directory}/usr/lib/libbz2.a"
