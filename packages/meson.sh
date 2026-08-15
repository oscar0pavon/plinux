#!/bin/bash
#
# meson - the build system. LFS 12.4 section 8.57.
#
# The package that unblocks the rest of the list. kmod is configured with
# meson, and so is nearly everything after it: wayland, wayland-protocols,
# libdrm, pixman, libinput, libdisplay-info, libxkbcommon, mesa, wlroots and
# sway. Until this existed, every one of those was configured by the build
# host's meson and the image had none.
#
# Pure python, so nothing is compiled; ninja above is what actually runs the
# builds meson describes. Built with pip; packages/flit-core.sh explains the
# invocation.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'meson-*.tar.gz' 'meson-1.8.3')
cd "${directory}"

pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "${PWD}"

pip3 install ${build_directory:+--root="${build_directory}"} \
     --no-index --find-links dist meson
