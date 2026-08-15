#!/bin/bash
#
# jinja2 - a python template language. LFS 12.4 section 8.75.
#
# systemd generates several of its sources from templates at build time, and
# its meson.build tests for the module by importing it:
#
#   ERROR: python3 is missing modules: jinja2
#
# which is what stopped udev. LFS builds this and markupsafe immediately
# before udev for the same reason.
#
# Built with pip; packages/flit-core.sh explains the invocation.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'jinja2-*.tar.gz' 'jinja2-3.1.6')
cd "${directory}"

pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "${PWD}"

pip3 install ${build_directory:+--root="${build_directory}"} \
     --no-index --find-links dist Jinja2
