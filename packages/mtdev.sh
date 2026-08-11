#!/bin/bash
#
# mtdev - the multitouch protocol translator.
#
# The kernel has two multitouch protocols. Type B, the current one, reports
# each contact with a slot number and only sends what changed; type A, which
# predates it, sends every contact every frame with no identity. libinput
# understands type B and hands type A devices to mtdev to be converted.
#
# Nothing on this machine speaks type A -- there is no touchpad or
# touchscreen here at all, only a USB keyboard and a wireless mouse. It is
# built because the rescue USB is meant to boot other machines, and a laptop
# old enough to have a type A touchpad is exactly the kind of machine that
# needs rescuing. It is 40K.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc

directory=$(unpack 'mtdev-*.tar.bz2' 'mtdev-1.1.7')
cd "${directory}"

./configure --prefix=/usr --disable-static

make

make DESTDIR="${build_directory}" install
