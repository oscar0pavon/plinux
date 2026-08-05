#!/bin/bash
#
# grep - grep, egrep, fgrep. LFS 12.4 section 8.35.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'grep-*.tar.xz' 'grep-3.12')
cd "${directory}"

# The book comments out the deprecation notice egrep and fgrep print, because
# it lands in the output of other packages' test suites and fails them.
# Guarded: this script is re-run after a failed build, and the substitution
# would otherwise comment out the already-commented line again.
if ! grep -q '^#echo' src/egrep.sh; then
  sed -i "s/echo/#echo/" src/egrep.sh
fi

./configure --prefix=/usr

make

make DESTDIR="${build_directory}" install
