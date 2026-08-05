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
# systemd unit directories are pointed inside the staging tree rather than
# left at their defaults, so nothing lands outside DESTDIR; nothing here reads
# them, since pinit and init_os start iwd directly.
./configure --prefix=/usr        \
            --sysconfdir=/etc    \
            --localstatedir=/var \
            --libexecdir=/usr/libexec

make

make DESTDIR="${build_directory}" install
