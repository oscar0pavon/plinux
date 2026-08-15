#!/bin/bash
#
# LFS 6.5. Coreutils-9.7.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

directory=$(unpack_cross 'coreutils-*.tar.xz' 'coreutils-9.7')
cd "${directory}"

# --enable-install-program=hostname
#   Off by default; Perl's test suite in chapter 8 needs it.
#
# --enable-no-install-program=kill,uptime
#   Both come from util-linux and procps-ng instead, and whichever installs
#   second would otherwise overwrite the other.
cross_configure --enable-install-program=hostname \
                --enable-no-install-program=kill,uptime

make

make DESTDIR="${LFS}" install

# Programs that hardcode where chroot lives expect /usr/sbin, and one of them
# is the chroot invocation in chapter 7. Not strictly needed for a temporary
# system, but getting it wrong is only discovered later.
mv -v "${LFS}/usr/bin/chroot" "${LFS}/usr/sbin"

mkdir -pv "${LFS}/usr/share/man/man8"
mv -v "${LFS}/usr/share/man/man1/chroot.1" "${LFS}/usr/share/man/man8/chroot.8"
sed -i 's/"1"/"8"/' "${LFS}/usr/share/man/man8/chroot.8"
