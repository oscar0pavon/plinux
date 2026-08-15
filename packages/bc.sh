#!/bin/bash
#
# bc - arbitrary precision calculator. LFS 12.4 section 8.14.
#
# A build tool rather than a convenience: the kernel's build system runs bc
# to compute constants, and several configure scripts use it for arithmetic
# the shell cannot do.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'bc-*.tar.xz' 'bc-7.0.3')
cd "${directory}"

# This is not autoconf. bc ships its own configure taking single-letter
# options: -G omits the parts of the test suite that need bc installed
# first, -O3 is the optimisation level, and -r links readline for line
# editing. The book passes CC explicitly with -std=c99, so it does too.
CC='gcc -std=c99' ./configure --prefix=/usr -G -O3 -r

make

make DESTDIR="${build_directory}" install
