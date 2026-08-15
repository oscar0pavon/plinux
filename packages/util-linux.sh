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
#
# --without-udev, and it cannot be otherwise: udev links libblkid and
# libmount from here, so it is built after this package and its headers are
# not in the image yet. The cycle is only optional on this side -- lsblk and
# findmnt use libudev to read properties out of the udev database, and fall
# back to probing the device with libblkid without it.
#
# Naming it matters because the default is to look, and looking escapes the
# sysroot: AC_CHECK_LIB does not honour --sysroot, so configure found the
# build machine's libudev, set HAVE_UDEV, and the compile then stopped on a
# libudev.h that is not staged. Same for libmagic, which nothing here builds
# at all.
./configure --without-udev        \
            --without-libmagic    \
            --bindir=/usr/bin     \
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
