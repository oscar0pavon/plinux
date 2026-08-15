#!/bin/bash
#
# mako - a python template language. BLFS, not LFS.
#
# For mesa alone. mesa generates a great deal of its source at build time --
# the GL dispatch tables, the driver entry points, the format tables -- from
# mako templates, and its meson.build refuses to configure without it:
#
#   ERROR: Problem encountered: Python (3.x) mako module >= 0.8.0
#          required to build mesa.
#
# The second python module here that exists for one C package's build, after
# jinja2 for udev. Both were supplied by the build host's python until the
# build moved somewhere the host is not.
#
# Depends on markupsafe, which is built earlier for jinja2 and shared.
#
# Built with pip; packages/flit-core.sh explains the invocation.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'mako-*.tar.gz' 'mako-1.3.10')
cd "${directory}"

pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "${PWD}"

pip3 install ${build_directory:+--root="${build_directory}"} \
     --no-index --find-links dist Mako
