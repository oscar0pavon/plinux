#!/bin/bash
#
# texinfo - the info reader, and makeinfo. LFS 12.4 section 8.72.
#
# Replaces chapter 7's copy. After perl, which makeinfo is written in, and
# after ncurses, which the info reader links for terminal handling.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'texinfo-*.tar.xz' 'texinfo-7.2')
cd "${directory}"

export CC=gcc

# A perl 5.42 incompatibility: "! $output_file eq" parses differently under
# the newer perl than it did when it was written, and the negation lands on
# the wrong operand. The book's sed makes it the string inequality it always
# meant. Idempotent -- after the first run the pattern is gone.
sed 's/! $output_file eq/$output_file ne/' -i tp/Texinfo/Convert/*.pm

./configure --prefix=/usr

make

make DESTDIR="${build_directory}" install
