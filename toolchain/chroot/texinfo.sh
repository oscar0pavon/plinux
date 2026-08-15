#!/bin/bash
#
# LFS 7.11. Texinfo-7.2: makeinfo, and the info reader.

set -e

source /toolchain/common.sh

directory=$(unpack 'texinfo-*.tar.xz' 'texinfo-7.2')
cd "${directory}"

./configure --prefix=/usr

make

make install
