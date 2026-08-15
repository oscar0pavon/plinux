#!/bin/bash
#
# iwd - wireless daemon.
#
# Not an LFS package. init_os starts it through set_ip, and it is what brings
# the wireless interface up: it associates and then applies the address from
# /var/lib/iwd/<network>.psk itself, over rtnetlink. pinit does not configure
# wlan0 at all.
#
# The release tarball bundles ell, so --enable-external-ell is deliberately
# not passed and there is no separate ell package. The resulting binary links
# nothing but libc.
#
# The kernel needs AF_ALG for iwd's crypto: CONFIG_CRYPTO_USER_API_HASH and
# CONFIG_CRYPTO_USER_API_SKCIPHER, plus SHA1, DES and KEY_DH_OPERATIONS.
# sys/kernel_config carries all of them.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'iwd-*.tar.xz' 'iwd-3.12')
cd "${directory}"

export CC=gcc

# The daemon installs to libexecdir, which is where set_ip looks for it.
#
# --disable-systemd-service, which this comment used to claim was handled and
# was not: it said the unit directories were pointed inside the staging tree,
# and the configure line below passed no such option. Nothing noticed while
# iwd was unbuilt.
#
# Left alone, configure insists on somewhere to put a service unit:
#
#   if (test "${enable_systemd_service}" != "no" && test -z "${path_systemd_unitdir}")
#       path_systemd_unitdir=`$PKG_CONFIG --variable=systemdsystemunitdir systemd`
#       if empty: as_fn_error "systemd unit directory is required"
#
# and there is no systemd.pc here, because there is no systemd -- udev is
# carved out of the systemd tarball and nothing else from it is built. So the
# answer is not to find a directory for the unit but to not generate one:
# pinit starts pdaemon, pdaemon supervises iwd, and no part of that reads a
# systemd unit.
#
# The D-Bus directories need no such help. iwd asks pkg-config for them and
# dbus-1.pc answers, which it can because dbus is built before this.
./configure --prefix=/usr              \
            --sysconfdir=/etc          \
            --localstatedir=/var       \
            --libexecdir=/usr/libexec  \
            --disable-systemd-service

make

make DESTDIR="${build_directory}" install
