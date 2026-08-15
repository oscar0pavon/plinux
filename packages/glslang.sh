#!/bin/bash
#
# glslang - the Khronos GLSL reference compiler. BLFS, not LFS.
#
# Here for one program: glslangValidator, which mesa runs at build time to
# compile the GLSL sources of RADV's internal shaders into SPIR-V. mesa's
# meson.build makes it a hard requirement whenever a Vulkan driver is
# enabled, and packages/mesa.sh enables -Dvulkan-drivers=amd.
#
# After cmake, which is the only build system it has.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'glslang-*.tar.gz' 'glslang-15.3.0')
cd "${directory}"

export CC=gcc

# Removed rather than reused: cmake caches the compiler and every path it
# found into CMakeCache.txt, and these scripts are re-run after failures.
rm -rf build
mkdir -p build
cd build

# -DENABLE_OPT=OFF drops the SPIR-V optimiser, which would pull in
# SPIRV-Tools as a separate package. mesa uses glslangValidator to *compile*
# GLSL, not to optimise the result, so the validator without it is the whole
# of what is wanted here.
#
# -DGLSLANG_TESTS=OFF: the test suite needs gtest.
#
# -DBUILD_SHARED_LIBS=ON so the libraries are shared like everything else in
# the image, rather than static archives nothing can use.
#
# CMAKE_INSTALL_PREFIX is /usr, and DESTDIR on the install below is what puts
# it in the right tree -- cmake honours DESTDIR the same way make does.
cmake -DCMAKE_INSTALL_PREFIX=/usr   \
      -DCMAKE_BUILD_TYPE=Release    \
      -DBUILD_SHARED_LIBS=ON        \
      -DGLSLANG_TESTS=OFF           \
      -DENABLE_OPT=OFF              \
      ..

make

make DESTDIR="${build_directory}" install

# The one binary mesa actually looks for. Checked, because a glslang that
# installs its libraries and not its driver program would fail mesa in
# exactly the way this package exists to prevent.
if [ ! -x "${build_directory}/usr/bin/glslangValidator" ]; then
  echo "glslang installed no glslangValidator" >&2
  exit 1
fi
