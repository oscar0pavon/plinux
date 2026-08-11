#!/bin/bash
#
# hwdata - the hardware identifier tables.
#
# Data only: pci.ids, usb.ids, and pnp.ids. The one that matters here is
# pnp.ids, the three-letter monitor manufacturer codes that libdisplay-info
# resolves EDID against -- without it a display reports its vendor as "SAM"
# rather than "Samsung". The pci and usb tables are what lspci and lsusb
# print names from.
#
# Autotools, and one of the few packages here that installs no binary at all.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc

directory=$(unpack 'hwdata-*.tar.gz' 'hwdata-0.402')
cd "${directory}"

# --disable-blacklist skips the modprobe blacklist files, which are a
# distribution policy this system does not have.
#
# The datadir is named explicitly because the default is ${prefix}/share and
# hwdata's configure puts the tables under ${datadir}/hwdata; libdisplay-info
# finds them through the .pc file either way, but the path ends up in that
# file, so it should be the image's path and not a guess.
./configure --prefix=/usr        \
            --datadir=/usr/share \
            --disable-blacklist

make

make DESTDIR="${build_directory}" install
