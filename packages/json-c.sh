#!/bin/bash
#
# json-c - JSON parsing and generation.
#
# sway's IPC is JSON over a unix socket: this is what swaymsg speaks and what
# swaybar reads its status from. The only cmake package in the tree; json-c
# dropped autotools and never adopted meson.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc

directory=$(unpack 'json-c-*.tar.gz' 'json-c-json-c-0.18-20240915')
cd "${directory}"

# CMAKE_INSTALL_LIBDIR=lib for the same reason meson_setup names libdir:
# cmake's GNUInstallDirs picks lib64 on x86_64 when it sees one on the build
# machine, and this host has one.
#
# CMAKE_SYSROOT rather than trusting CFLAGS: cmake assembles its own compile
# lines and this is where it expects to be told.
#
# CMAKE_POLICY_VERSION_MINIMUM because json-c's apps/CMakeLists.txt still says
# cmake_minimum_required(VERSION 2.8) and cmake 4 removed compatibility with
# anything below 3.5. This is cmake's own escape hatch for exactly that, and
# the alternative is patching upstream's build files.
rm -rf build
cmake -S . -B build                             \
      -DCMAKE_INSTALL_PREFIX=/usr               \
      -DCMAKE_INSTALL_LIBDIR=lib                \
      -DCMAKE_BUILD_TYPE=Release                \
      -DCMAKE_SYSROOT="${build_directory}"      \
      -DBUILD_SHARED_LIBS=ON                    \
      -DBUILD_STATIC_LIBS=OFF                   \
      -DBUILD_TESTING=OFF                       \
      -DDISABLE_WERROR=ON                       \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5

cmake --build build

DESTDIR="${build_directory}" cmake --install build
