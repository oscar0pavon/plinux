#!/bin/bash
#
# packaging - version and requirement parsing for python. LFS 12.4 section 8.53.
#
# Built with pip; packages/flit-core.sh explains the invocation.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'packaging-*.tar.gz' 'packaging-25.0')
cd "${directory}"

pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "${PWD}"

pip3 install ${build_directory:+--root="${build_directory}"} \
     --no-index --find-links dist packaging
