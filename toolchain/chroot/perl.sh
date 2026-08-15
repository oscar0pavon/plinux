#!/bin/bash
#
# LFS 7.9. Perl-5.42.0.
#
# Perl does not use autoconf. Its Configure is its own thing and takes -D
# options rather than --with ones, which is why this script looks unlike every
# other one here.

set -e

source /toolchain/common.sh

directory=$(unpack 'perl-*.tar.xz' 'perl-5.42.0')
cd "${directory}"

# -des
#   -d take the default for everything not named, -e run to completion,
#   -s keep quiet. Together: do not ask any of the several hundred questions
#   Configure would otherwise ask interactively.
#
# -D useshrplib
#   libperl as a shared library. Some modules will not build against a static
#   one.
#
# -D privlib, archlib, sitelib, sitearch, vendorlib, vendorarch
#   Module search paths keyed on the MAJOR.MINOR version (5.42) rather than
#   the full 5.42.0. A patch-level upgrade then does not orphan every
#   installed module.
sh Configure -des                                         \
             -D prefix=/usr                               \
             -D vendorprefix=/usr                         \
             -D useshrplib                                \
             -D privlib=/usr/lib/perl5/5.42/core_perl     \
             -D archlib=/usr/lib/perl5/5.42/core_perl     \
             -D sitelib=/usr/lib/perl5/5.42/site_perl     \
             -D sitearch=/usr/lib/perl5/5.42/site_perl    \
             -D vendorlib=/usr/lib/perl5/5.42/vendor_perl \
             -D vendorarch=/usr/lib/perl5/5.42/vendor_perl

make

make install
