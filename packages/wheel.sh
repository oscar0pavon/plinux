#!/bin/bash
#
# wheel - the reference implementation of the python wheel format.
# LFS 12.4 section 8.54.
#
# Built with pip; packages/flit-core.sh explains the invocation.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'wheel-*.tar.gz' 'wheel-0.46.1')
cd "${directory}"

pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "${PWD}"

pip3 install ${build_directory:+--root="${build_directory}"} \
     --no-index --find-links dist wheel
