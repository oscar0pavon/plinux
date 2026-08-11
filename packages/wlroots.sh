#!/bin/bash
#
# wlroots - the compositor library.
#
# Everything a Wayland compositor has to do that is not window management:
# driving DRM outputs, reading input through libinput, allocating buffers
# through GBM, rendering with GLES2, and implementing the protocol objects
# clients talk to. sway is what is left once this exists.
#
# The version is pinned by sway: sway 1.11's meson.build asks for
# wlroots-0.19, ">=0.19.0, <0.20.0".

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'wlroots-*.tar.gz' 'wlroots-0.19.1')
cd "${directory}"

# The backends and renderers are named rather than left at 'auto', which would
# decide from what the build machine has.
#
# backends=drm,libinput is the real hardware path: DRM for output, libinput
# for devices. The x11 backend -- running the compositor nested inside an X
# server -- is not built, there being no X server. The wayland backend, for
# running nested inside another compositor, comes in with the wayland-server
# dependency and is what would be used to test sway from inside sway.
#
# renderers=gles2 only. The vulkan renderer would want the Vulkan headers and
# glslang at build time; RADV is installed but wlroots does not need it to
# drive this display, and GLES2 is what sway is developed against.
#
# xwayland=disabled: X11 applications, which need an actual Xwayland binary
# and the X client libraries. Deliberately absent -- see the README.
#
# session=enabled is seatd. Without it wlroots would need to run as root to
# open the DRM device.
#
# color-management=disabled because it needs lcms2 to build, and lcms2 is not
# staged. It implements the wp_color_manager protocol -- ICC profiles and HDR
# metadata -- which nothing in this image asks for. Adding lcms2 is one small
# package if that changes.
meson_setup build              \
      -Dbackends=drm,libinput  \
      -Drenderers=gles2        \
      -Dallocators=gbm         \
      -Dsession=enabled        \
      -Dxwayland=disabled      \
      -Dexamples=false         \
      -Dcolor-management=disabled

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
