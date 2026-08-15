#!/bin/bash
#
# LFS 7.8. Bison-3.8.2: the parser generator.

set -e

source /toolchain/common.sh

directory=$(unpack 'bison-*.tar.xz' 'bison-3.8.2')
cd "${directory}"

./configure --prefix=/usr \
            --docdir=/usr/share/doc/bison-3.8.2

make

make install
