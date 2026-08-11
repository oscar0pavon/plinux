#!/bin/bash
#
# pcre2 - Perl-compatible regular expressions.
#
# glib links it for GRegex, and sway uses it directly: window criteria like
# [app_id="foo.*"] in the config are pcre2 patterns.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc

directory=$(unpack 'pcre2-*.tar.bz2' 'pcre2-10.46')
cd "${directory}"

# --enable-pcre2-16 and -32 are what glib expects to find; without them a
# glib built against this fails to link. --enable-jit compiles patterns to
# machine code, which is the reason to use pcre2 over the alternatives.
./configure --prefix=/usr        \
            --disable-static     \
            --enable-unicode     \
            --enable-jit         \
            --enable-pcre2-16    \
            --enable-pcre2-32    \
            --enable-pcre2grep-libz

make

make DESTDIR="${build_directory}" install
