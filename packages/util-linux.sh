#!/bin/bash
#
# util-linux - mount, blkid, lsblk, dmesg, losetup, fdisk and the rest.
#
# LFS 12.4 section 8.79. Also the source of libblkid, which udev uses for the
# persistent storage rules, so it is built before udev.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'util-linux-*.tar.xz' 'util-linux-2.41.1')
cd "${directory}"

# glibc, not musl: udev links against libblkid from here and is itself a
# glibc program, so the two have to agree.
export CC=gcc

# login, nologin, su, chfn and chsh are disabled because plogin covers what
# this system needs, and the rest want PAM. agetty still gets built; pgetty
# replaces it, so it simply goes unused.
./configure --bindir=/usr/bin     \
            --libdir=/usr/lib     \
            --runstatedir=/run    \
            --sbindir=/usr/sbin   \
            --disable-chfn-chsh   \
            --disable-login       \
            --disable-nologin     \
            --disable-su          \
            --disable-setpriv     \
            --disable-runuser     \
            --disable-pylibmount  \
            --disable-liblastlog2 \
            --disable-static      \
            --without-python      \
            --without-systemd     \
            --without-systemdsystemunitdir        \
            ADJTIME_PATH=/var/lib/hwclock/adjtime \
            --docdir=/usr/share/doc/util-linux-2.41.1

make

make DESTDIR="${build_directory}" install
