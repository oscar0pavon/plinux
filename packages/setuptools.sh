#!/bin/bash
#
# setuptools - the build backend most python packages declare.
# LFS 12.4 section 8.55.
#
# Last of the four, and the one meson's own pyproject.toml names. Built with
# pip; packages/flit-core.sh explains the invocation.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'setuptools-*.tar.gz' 'setuptools-80.9.0')
cd "${directory}"

pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "${PWD}"

pip3 install ${build_directory:+--root="${build_directory}"} \
     --no-index --find-links dist setuptools
