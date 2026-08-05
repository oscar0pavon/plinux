#!/bin/bash
#
# sed - stream editor. LFS 12.4 section 8.31.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'sed-*.tar.xz' 'sed-4.9')
cd "${directory}"

./configure --prefix=/usr

make

# The book also runs "make html" and installs doc/sed.html. Skipped: it needs
# makeinfo, and nothing in this image reads HTML.

make DESTDIR="${build_directory}" install
