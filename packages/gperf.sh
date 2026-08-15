#!/bin/bash
#
# gperf - perfect hash function generator. LFS 12.4 section 8.39.
#
# Here for udev. systemd's meson.build declares gperf a hard requirement --
# it generates the lookup tables udev matches its rules with -- and stops at
# configure time without it, which is what it did.
#
# Another tool the build host supplied silently, like pkgconf, automake and
# meson before it.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'gperf-*.tar.gz' 'gperf-3.3')
cd "${directory}"

export CC=gcc

./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.3

make

make DESTDIR="${build_directory}" install
