#!/bin/bash
#
# LFS 7.7. Gettext-0.26 -- three programs out of it, anyway.
#
# msgfmt, msgmerge and xgettext, copied into place by hand rather than
# installed. The libraries and the rest of the package come in chapter 8; what
# is needed now is that configure scripts stop reporting gettext as missing
# and quietly disabling things. glibc's configure did exactly that in chapter
# 5 -- "these auxiliary programs are missing: msgfmt" -- and the book says to
# ignore it there precisely because this step fixes it.

set -e

source /toolchain/common.sh

directory=$(unpack 'gettext-*.tar.xz' 'gettext-0.26')
cd "${directory}"

# --disable-shared: nothing links against these, they are just programs.
./configure --disable-shared

make

cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
