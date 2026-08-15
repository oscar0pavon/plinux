#!/bin/bash
#
# binutils - the assembler, linker and object tools. LFS 12.4 section 8.20.
#
# The third and final build of these. Chapter 5 built a cross assembler and
# linker into $LFS/tools, chapter 6 cross-compiled a set into $LFS/usr that
# runs in the chroot, and this is the native one the image keeps.
#
# Before gcc, because gcc's configure probes the assembler and linker it can
# find and enables its own features on the strength of the answers.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'binutils-*.tar.xz' 'binutils-2.45')
cd "${directory}"

export CC=gcc

# A build directory of its own; binutils fails without one. Removed first
# because these scripts are re-run after failures and a configure that ran
# with different options leaves cached answers behind.
rm -rf build-native
mkdir -p build-native
cd build-native

# --enable-ld=default installs the bfd linker as both ld and ld.bfd.
# --enable-plugins is what lets the linker load gcc's LTO plugin.
# --with-system-zlib uses the zlib built earlier rather than the bundled one.
# --enable-64-bit-bfd and --enable-new-dtags and the gnu hash style are the
# same choices chapters 5 and 6 made, for the same reasons.
../configure --prefix=/usr       \
             --sysconfdir=/etc   \
             --enable-ld=default \
             --enable-plugins    \
             --enable-shared     \
             --disable-werror    \
             --enable-64-bit-bfd \
             --enable-new-dtags  \
             --with-system-zlib  \
             --enable-default-hash-style=gnu

# tooldir=/usr, both times.
#
# Binutils otherwise installs into $(exec_prefix)/$(target_alias) --
# /usr/x86_64-pc-linux-gnu -- which is where a cross-compilation setup wants
# its target tools. This is not one: the image compiles for itself, so the
# tools belong in /usr where everything looks for them.
make tooldir=/usr

make tooldir=/usr DESTDIR="${build_directory}" install

# Static libraries nothing here links, and gprofng's documentation.
rm -rfv "${build_directory}"/usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a \
        "${build_directory}/usr/share/doc/gprofng"
