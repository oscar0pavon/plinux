#!/bin/bash
#
# LFS 7.10. Python-3.13.7.
#
# The tarball is Python-3.13.7.tar.xz with a capital P. There is a lowercase
# python-3.13.7-docs-html.tar.bz2 in the book's list as well, which is
# documentation and is not downloaded here.

set -e

source /toolchain/common.sh

directory=$(unpack 'Python-*.tar.xz' 'Python-3.13.7')
cd "${directory}"

# --enable-shared
#   libpython as a shared library, which is what meson and everything else
#   embedding python will want.
#
# --without-ensurepip
#   No pip. Chapter 8 installs what is needed through the book's own steps,
#   and a package installer that reaches the network is the last thing this
#   build wants.
#
# --without-static-libpython
#   A large static library nothing here links against.
./configure --prefix=/usr       \
            --enable-shared     \
            --without-ensurepip \
            --without-static-libpython

# Several optional modules cannot be built yet, because their dependencies are
# chapter 8 packages: the ssl module in particular prints "Python requires a
# OpenSSL 1.1.1 or newer" and is skipped. That is expected here and chapter 8
# builds python again with them. What matters is that make itself succeeds,
# which set -e is watching.
make

make install
