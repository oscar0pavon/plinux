#!/bin/bash
#
# coreutils - ls, cp, mv, rm, mkdir, cat, chmod and the rest.
#
# LFS 12.4 section 8.59.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'coreutils-*.tar.xz' 'coreutils-9.7')
cd "${directory}"

apply_patch 'coreutils-*-upstream_fix-*.patch'

# The book also applies coreutils-9.7-i18n-1.patch. It is skipped here: it
# rewrites the build system so autoreconf and automake have to be re-run, and
# what it buys is correct character handling in multibyte locales, which musl
# does not implement beyond UTF-8. The book itself notes the patch is a
# frequent source of bugs.

# coreutils refuses to configure as root without this. --enable-no-install-
# program keeps kill and uptime out of the way of util-linux and procps-ng,
# which provide better versions later.
FORCE_UNSAFE_CONFIGURE=1 ./configure \
  --prefix=/usr                      \
  --enable-no-install-program=kill,uptime

make

make DESTDIR="${build_directory}" install
