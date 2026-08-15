#!/bin/bash
#
# markupsafe - string escaping for jinja2. LFS 12.4 section 8.74.
#
# Here only because jinja2 needs it, and jinja2 is here only because udev
# needs it. Built with pip; packages/flit-core.sh explains the invocation.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'markupsafe-*.tar.gz' 'markupsafe-3.0.2')
cd "${directory}"

pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "${PWD}"

pip3 install ${build_directory:+--root="${build_directory}"} \
     --no-index --find-links dist Markupsafe
