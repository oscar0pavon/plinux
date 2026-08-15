#!/bin/bash
#
# LFS 5.2. Binutils-2.45 - Pass 1: the cross assembler and linker.
#
# First of everything, because both glibc and gcc run tests against whatever
# "as" and "ld" they can find and enable their own features on the strength
# of the answers. Build these second and those tests describe this
# workstation's binutils 2.45 instead of the target's, which happen to be the
# same version today and will not stay that way.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

directory=$(unpack 'binutils-*.tar.xz' 'binutils-2.45')
cd "${directory}"

# The binutils documentation requires a separate build directory; it is not a
# preference here, the build fails without one.
build=$(fresh_build_dir "${directory}")
cd "${build}"

# --prefix=$LFS/tools
#   Out of the way of $LFS/usr, so chapter 7.13 can delete the whole
#   toolchain with one rm once the system it built can rebuild itself.
#
# --with-sysroot=$LFS
#   The line that does the work this project has been faking. The linker
#   prefixes its search paths with $LFS and looks nowhere else, so the
#   host's /usr/lib stops being reachable rather than being outranked by a
#   -L. Everything packages/common.sh explains about -L not covering
#   indirect dependencies and AC_CHECK_LIB not honouring --sysroot stops
#   applying, because there is no second tree to find.
#
# --target=$LFS_TGT
#   x86_64-lfs-linux-gnu, one vendor field away from what config.guess says
#   about this machine. That is enough for the build system to configure a
#   cross linker and install it as $LFS_TGT-ld.
#
# --disable-nls
#   No translations in a toolchain that gets deleted in chapter 7.
#
# --enable-gprofng=no
#   A profiler the temporary tools have no use for.
#
# --disable-werror
#   So a warning from this host's gcc 15 does not stop the build.
#
# --enable-new-dtags
#   Makes the linker write DT_RUNPATH rather than DT_RPATH. RUNPATH is
#   overridable by LD_LIBRARY_PATH and does not apply to indirect
#   dependencies, which is the behaviour anything debugging this image will
#   expect.
#
# --enable-default-hash-style=gnu
#   Only the GNU-style hash table. glibc's loader never reads the classic
#   ELF one, so generating it costs build time and image size to produce
#   something nothing will ever look at.
../configure --prefix="${LFS}/tools" \
             --with-sysroot="${LFS}" \
             --target="${LFS_TGT}"   \
             --disable-nls           \
             --enable-gprofng=no     \
             --disable-werror        \
             --enable-new-dtags      \
             --enable-default-hash-style=gnu

make

make install

# Nothing installs into $LFS/usr at this stage, so the only evidence the step
# worked is the cross linker existing under the name everything after this
# will call it by.
if [ ! -x "${LFS}/tools/bin/${LFS_TGT}-ld" ]; then
  echo "binutils-pass1 installed no ${LFS_TGT}-ld" >&2
  exit 1
fi
