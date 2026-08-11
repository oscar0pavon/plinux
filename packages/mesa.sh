#!/bin/bash
#
# mesa - OpenGL, EGL, GBM and Vulkan.
#
# The largest package in the image and the one the compositor stands on:
# wlroots opens the GPU through GBM, renders with GLES2 through EGL, and
# scans out through DRM. radeonsi is the driver for the Navi 23 in this
# machine, RADV is its Vulkan counterpart.
#
# Built without LLVM, which is worth explaining because every distribution
# builds it with one.
#
# LLVM has two consumers here. llvmpipe is a JIT and cannot exist without it
# -- mesa's meson.build says so outright. radeonsi used LLVM's AMDGPU backend
# for years, but ACO, the compiler Valve wrote for RADV, now handles graphics
# shaders, and mesa switches radeonsi over by itself when LLVM is absent:
#
#   src/gallium/drivers/radeonsi/si_pipe.c
#     #if !AMD_LLVM_AVAILABLE
#        sctx->shader.vs.key.ge.use_aco = 1;
#
# So the only reason to carry LLVM would be llvmpipe, and llvmpipe's only job
# here would be the VM -- where it is software rendering, and where wlroots
# already has a software renderer in pixman. libLLVM is 121M unstripped on
# this host; the root partition is 922M and the image is past 460M before the
# text stack, wlroots and sway are built. Adding llvmpipe later is one
# package and a rebuild, not a redesign.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'mesa-*.tar.xz' 'mesa-25.2.4')
cd "${directory}"

# platforms=wayland alone. There is no X server, no libX11 and no libxcb, so
# glx has to be disabled too rather than left at 'auto', which means "look for
# X11 and use it if you find it".
#
# gles1 is the 2003 API; wlroots renders with GLES2. gbm and egl are not
# optional -- they are how wlroots gets a buffer and a context at all.
#
# The 'disabled' lines at the end are the point of being explicit. Those
# options default to 'auto', which resolves against whatever the build machine
# happens to have installed. That is how vim ended up linking the host's GTK
# and how libinput would have. A dependency should be a decision.
#
# lmsensors is the one that proved it. mesa finds it with cc.find_library,
# and --sysroot does not stop that: gcc's own search path includes
# .../x86_64-pc-linux-gnu/lib/../lib, which resolves to the host's /usr/lib
# and is not sysroot-relative. So the link test succeeded against the host's
# libsensors, HAVE_LIBSENSORS was defined, and the build then failed on
# sensors/sensors.h -- which the sysroot *did* block. Headers are covered,
# libraries are not; ./build.sh check is what covers the rest.
meson_setup build                      \
      -Dplatforms=wayland              \
      -Degl-native-platform=wayland    \
      -Dgallium-drivers=radeonsi       \
      -Dvulkan-drivers=amd             \
      -Dllvm=disabled                  \
      -Damd-use-llvm=false             \
      -Dopengl=true                    \
      -Dgles1=disabled                 \
      -Dgles2=enabled                  \
      -Degl=enabled                    \
      -Dgbm=enabled                    \
      -Dglx=disabled                   \
      -Dglvnd=disabled                 \
      -Dvideo-codecs=all               \
      -Dgallium-va=disabled            \
      -Dgallium-vdpau=disabled         \
      -Dvalgrind=disabled              \
      -Dlibunwind=disabled             \
      -Dlmsensors=disabled

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
