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

# Makefile.in is declared current, because otherwise it is regenerated and
# the regeneration cannot succeed.
#
# The patch touches four files. Three are ordinary -- NEWS, src/sort.c and a
# test script -- but tests/local.mk is included by Makefile.am, so patching
# it leaves Makefile.in older than its own source and make sets out to
# rebuild it. The rule for that runs "automake-1.16": not automake, but the
# exact version this tarball's Makefile.in was generated with, named in
# build-aux/missing.
#
# This workstation has automake-1.16 installed beside 1.17 and 1.18, so the
# host build found it and regenerated without anyone knowing it happened. The
# chroot has 1.18 alone, and coreutils stopped there with "Error 127" --
# which is the useful outcome, because the alternative was a build that
# depended on which automake versions this particular machine had collected.
#
# Touching it is honest rather than a dodge. The only build-system change in
# the patch registers a new test case, and nothing here runs the test suite.
# The payload is the sort.c fix, and that compiles either way.
touch Makefile.in

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
