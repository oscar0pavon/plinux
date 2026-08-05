#!/bin/bash
#
# libcap - POSIX capabilities. LFS 12.4 section 8.26.
#
# udev links against libcap.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'libcap-*.tar.xz' 'libcap-2.76')
cd "${directory}"

export CC=gcc

# no configure script; the static library is not wanted
sed -i '/install -m.*STA/d' libcap/Makefile

make prefix=/usr lib=lib

make prefix=/usr lib=lib DESTDIR="${build_directory}" install
