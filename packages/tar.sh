#!/bin/bash
#
# tar - the archiver.
#
# LFS 12.4 section 8.71. With this and gzip the image can finally unpack a
# tarball, which is the difference between a system that has to be built
# from outside and one that can install something into itself.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'tar-*.tar.xz' 'tar-1.35')
cd "${directory}"

# musl, like coreutils and the text tools: nothing links against tar.

# The mknod test refuses to run as root. The book overrides it for the same
# reason it does for coreutils: this is a partially built system and there is
# no unprivileged user to drop to.
FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr

make

make DESTDIR="${build_directory}" install

# The book also runs "make -C doc install-html". Skipped: that needs texinfo,
# and the image has nothing to read HTML with.
