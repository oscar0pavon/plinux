#!/bin/bash
#
# LFS 6.4. Bash-5.3: the shell chapter 7 will chroot into.
#
# Cross-compiled against glibc here, which is worth noting because the bash in
# the *image* is a different build entirely: packages/bash.sh builds it static
# against musl, so the login path survives a broken loader. That one is
# chapter 8's business. This one only has to run inside the chroot.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

directory=$(unpack_cross 'bash-*.tar.gz' 'bash-5.3')
cd "${directory}"

# --without-bash-malloc
#   Bash's own allocator makes assumptions that do not hold everywhere and is
#   a known source of segmentation faults. glibc's malloc instead.
cross_configure --without-bash-malloc

make

make DESTDIR="${LFS}" install

# /bin/sh. $LFS/bin is the symlink to usr/bin that toolchain_layout made, so
# this lands in $LFS/usr/bin next to bash itself.
ln -sfv bash "${LFS}/bin/sh"
