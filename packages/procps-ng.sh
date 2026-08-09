#!/bin/bash
#
# procps-ng - ps, top, free, uptime, pgrep, pkill, vmstat, sysctl.
#
# LFS 12.4 section 8.78. The image had kill from util-linux but nothing that
# would tell you what to kill: no way to list processes, read memory use or
# see how long the machine had been up.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'procps-ng-*.tar.xz' 'procps-ng-4.0.5')
cd "${directory}"

# glibc, not musl: top and watch link libncursesw, which is a glibc build.
export CC=gcc

# kill is off because util-linux already installed one; two of them in
# /usr/bin would leave PATH order deciding which ran. coreutils skipped its
# own kill and uptime for the same reason, and uptime arrives here.
./configure --prefix=/usr                           \
            --docdir=/usr/share/doc/procps-ng-4.0.5 \
            --disable-static                        \
            --disable-kill                          \
            --enable-watch8bit

make

make DESTDIR="${build_directory}" install
