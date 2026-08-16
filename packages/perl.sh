#!/bin/bash
#
# perl - LFS 12.4 section 8.43.
#
# Replaces chapter 7's copy. Not for the sake of tidiness: chapter 7's perl
# was configured without man pages, without threads, and without knowing where
# the pager is, because none of that matters to a temporary tool that only has
# to run other packages' build scripts. This one is the image's perl.
#
# Perl does not use autoconf. Its Configure takes -D options, which is why
# this script looks unlike its neighbours.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'perl-*.tar.xz' 'perl-5.42.0')
cd "${directory}"

export CC=gcc

# Use the zlib and bzip2 already in the image rather than the copies bundled
# in perl's Compress::Raw::* modules. Two fewer copies of the same code, and
# a security fix to either reaches perl without rebuilding it.
#
# bzip2 is a package here for tar's sake -- four sources ship .tar.bz2 -- so
# both libraries exist by the time this runs.
export BUILD_ZLIB=False
export BUILD_BZIP2=0

# -des: take the default for everything (-d), run to completion (-e), and
# keep quiet (-s). Without it Configure asks several hundred questions.
#
# The module paths are keyed on 5.42 rather than 5.42.0, so a patch-level
# upgrade does not orphan every installed module.
#
# -D pager names less, which is a package here. Chapter 7's perl had no
# opinion because nothing interactive ran in the chroot.
#
# -D usethreads is the difference that matters most: chapter 7's perl was
# built without them, and anything in the image expecting a threaded perl
# would have found one that is not.
#
# -D useshrplib is deliberately *not* passed, and this is the one place this
# script leaves the book. It builds libperl into the binary rather than as a
# shared library, because a shared one cannot be built on a system with two C
# libraries.
#
# perl's own build is what breaks. With a shared libperl it runs every step
# through a helper in its tree called preload:
#
#   #! /bin/sh
#   lib=$1
#   shift
#   test -r $lib && export LD_PRELOAD="$lib $LD_PRELOAD"
#   exec "$@"
#
# LD_PRELOAD is not scoped to the program it was set for. It is inherited by
# every child, and perl's build shells out constantly -- mkdir, rm, cp, sed,
# grep, hundreds of times. In this image those are musl binaries, because
# packages/order builds the standalone tools against musl, and libperl.so is
# glibc. So musl's loader is handed a glibc library and says so, several
# hundred times:
#
#   Error relocating .../libperl.so: __sprintf_chk: symbol not found
#   Error relocating .../libperl.so: getpwent_r: symbol not found
#
# every one of them a symbol musl does not have and glibc does.
#
# LFS cannot meet this: it has one C library, so a preloaded libperl.so is
# valid in every process that inherits it. Chapter 7's perl did not meet it
# either, and that is the part worth remembering -- at that point coreutils
# was still chapter 6's, cross-compiled against glibc. packages/coreutils.sh
# rebuilt it against musl later and moved the ground under a perl that had
# already been built.
#
# What a static libperl costs is embedding: a program that links -lperl to
# host an interpreter wants the shared one. Nothing here does. perl is here
# to run build scripts.
sh Configure -des                                         \
             -D prefix=/usr                               \
             -D vendorprefix=/usr                         \
             -D privlib=/usr/lib/perl5/5.42/core_perl     \
             -D archlib=/usr/lib/perl5/5.42/core_perl     \
             -D sitelib=/usr/lib/perl5/5.42/site_perl     \
             -D sitearch=/usr/lib/perl5/5.42/site_perl    \
             -D vendorlib=/usr/lib/perl5/5.42/vendor_perl \
             -D vendorarch=/usr/lib/perl5/5.42/vendor_perl \
             -D man1dir=/usr/share/man/man1               \
             -D man3dir=/usr/share/man/man3               \
             -D pager="/usr/bin/less -isR"                \
             -D usethreads

make

make DESTDIR="${build_directory}" install
