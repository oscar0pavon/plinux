#!/bin/bash
#
# e2fsprogs - e2fsck, mke2fs, tune2fs, dumpe2fs, resize2fs and the rest.
#
# LFS 12.4 section 8.80. The root filesystem is ext4 and until now nothing in
# the image could check or create one: mount hands a dirty filesystem to the
# kernel and there was no fsck.ext4 to repair it, so a power cut meant fixing
# the disk from another machine.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'e2fsprogs-*.tar.gz' 'e2fsprogs-1.47.3')
cd "${directory}"

# glibc, not musl: the programs here link libblkid and libuuid from
# util-linux, which is a glibc build, so this has to agree with it.
export CC=gcc

# The package documentation asks for a separate build directory
mkdir -p build
cd build

# libblkid, libuuid, uuidd and the fsck wrapper are all disabled because
# util-linux already staged newer copies of them. Building them here would
# put a second libblkid.so.1 in /usr/lib and whichever landed last would be
# the one every other program resolved to.
#
# fuse2fs is off because configure finds libfuse3 on the build host and
# builds against it, but the image has no FUSE at all: the program installs
# and then cannot start. "./build.sh check" catches exactly this.
../configure --prefix=/usr       \
             --sysconfdir=/etc   \
             --enable-elf-shlibs \
             --disable-libblkid  \
             --disable-libuuid   \
             --disable-uuidd     \
             --disable-fuse2fs   \
             --disable-fsck

make

make DESTDIR="${build_directory}" install

# Nothing in the image links statically
rm -fv "${build_directory}"/usr/lib/{libcom_err,libe2p,libext2fs,libss}.a

# The book's remaining steps unzip and register the .info files. Skipped:
# there is no info reader in the image, so they would only be dead weight.
