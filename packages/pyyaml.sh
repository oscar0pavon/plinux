#!/bin/bash
#
# pyyaml - YAML for python. BLFS, not LFS.
#
# For mesa, like mako beside it. mesa describes its drivers and pixel formats
# in YAML and generates C from them at build time, so meson refuses to
# configure without the module:
#
#   ERROR: Problem encountered: Python (3.x) yaml module (PyYAML)
#          required to build mesa.
#
# Built with pip; packages/flit-core.sh explains the invocation.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'pyyaml-*.tar.gz' 'pyyaml-6.0.2')
cd "${directory}"

# The C extension links libyaml when it finds one and falls back to the pure
# python parser when it does not. Nothing here builds libyaml, so this is the
# fallback -- which is slower and is of no consequence: it is read once per
# mesa build, by a generator, and never by the image.
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "${PWD}"

pip3 install ${build_directory:+--root="${build_directory}"} \
     --no-index --find-links dist PyYAML
