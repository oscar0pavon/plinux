#!/bin/bash
#
# LFS 5.3. GCC-15.2.0 - Pass 1: a compiler with no C library.
#
# This one is strange if you have not met it before. It is built
# --without-headers --with-newlib --disable-shared --disable-libstdcxx, which
# is to say it cannot compile a program that calls printf. That is not a
# limitation being worked around, it is the point: glibc has to be compiled by
# something, and the something cannot be linked against the glibc it is going
# to produce. So pass 1 builds exactly one artifact that matters -- libgcc --
# and is thrown away in chapter 7 once pass 2 and the real chapter 8 GCC have
# replaced it.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

directory=$(unpack 'gcc-*.tar.xz' 'gcc-15.2.0')
cd "${directory}"

# GMP, MPFR and MPC: GCC's arbitrary-precision arithmetic, used by the
# compiler itself to fold constant expressions at build time to the target's
# precision rather than the host's.
#
# They are not packages here and never reach the image. GCC's build system
# looks for them by these exact directory names inside its own tree and, if
# they are there, builds them in-tree against its own configuration. The host
# has its own copies; using those would mean pass 1 depends on this
# workstation's libgmp at build time, which is the class of thing chapter 5
# exists to stop.
#
# Guarded individually rather than as a group: a failed run leaves whichever
# ones it got to already renamed.
unpack_into_gcc(){
  local pattern=$1
  local unpacked=$2
  local final=$3
  local archive

  if [ -d "${final}" ]; then
    echo "already in tree: ${final}" >&2
    return 0
  fi

  archive=$(ls ${sources_directory}/${pattern} 2>/dev/null | head -1)

  if [ -z "${archive}" ]; then
    echo "no ${pattern} in ${sources_directory}" >&2
    return 1
  fi

  echo "unpacking ${archive##*/} into gcc" >&2
  tar -xf "${archive}"
  mv "${unpacked}" "${final}"
}

unpack_into_gcc 'mpfr-*.tar.xz' 'mpfr-4.2.2' 'mpfr'
unpack_into_gcc 'gmp-*.tar.xz'  'gmp-6.3.0'  'gmp'
unpack_into_gcc 'mpc-*.tar.gz'  'mpc-1.3.1'  'mpc'

# x86_64 GCC defaults to putting 64-bit libraries in lib64. LFS does not have
# a /usr/lib64 -- the book is emphatic that one appearing will break the
# system -- and neither does this image, where lib64 is a symlink onto
# usr/lib. Left alone, the compiler would emit -L paths into a directory that
# resolves back to where the real libraries already are, or on a host that
# grew a real /usr/lib64, somewhere much worse.
#
# -i.orig keeps the original beside it, which is the book's own suggestion and
# is worth having: "diff -u gcc/config/i386/t-linux64{.orig,}" is the whole
# change. Skipped when the .orig is already there, since these scripts re-run
# and the sed is not idempotent in any useful sense.
if [ ! -f gcc/config/i386/t-linux64.orig ]; then
  sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
fi

build=$(fresh_build_dir "${directory}")
cd "${build}"

# --with-glibc-version=2.42
#   The glibc that will exist on the target, matching sources/glibc-2.42.
#   Says nothing about this host's glibc: everything pass 1 compiles runs in
#   the chroot, never here.
#
# --with-sysroot=$LFS, --target=$LFS_TGT
#   As for binutils, and for the same reason.
#
# --with-newlib, --without-headers
#   There is no C library and no headers describing one. These two tell GCC
#   to stop looking and to define inhibit_libc so libgcc builds without any
#   part of it that would call into libc.
#
# --enable-default-pie, --enable-default-ssp
#   Hardening on by default. Not needed for temporary binaries, but it costs
#   nothing and keeps pass 1's output shaped like chapter 8's.
#
# --disable-shared
#   GCC's internal libraries linked statically, because a shared one would
#   need the glibc that is not built yet.
#
# --disable-multilib
#   No 32-bit support. This image is x86_64 only.
#
# --disable-threads --disable-libatomic --disable-libgomp --disable-libquadmath
# --disable-libssp --disable-libvtv --disable-libstdcxx
#   Everything that needs a libc. libstdc++ comes back in the last step of
#   this chapter, once glibc is in place.
#
# --enable-languages=c,c++
#   C++ is here because parts of GCC itself are written in it, not because
#   anything in chapter 6 is.
../configure --target="${LFS_TGT}"        \
             --prefix="${LFS}/tools"      \
             --with-glibc-version=2.42    \
             --with-sysroot="${LFS}"      \
             --with-newlib                \
             --without-headers            \
             --enable-default-pie         \
             --enable-default-ssp         \
             --disable-nls                \
             --disable-shared             \
             --disable-multilib           \
             --disable-threads            \
             --disable-libatomic          \
             --disable-libgomp            \
             --disable-libquadmath        \
             --disable-libssp             \
             --disable-libvtv             \
             --disable-libstdcxx          \
             --enable-languages=c,c++

make

make install

cd "${directory}"

# LFS 5.3.1, the last step: a complete internal limits.h.
#
# GCC installs its own limits.h, which in a normal build is a wrapper that
# includes the system's $LFS/usr/include/limits.h and adds to it. There is no
# system limits.h yet, so what got installed above is the self-contained
# fallback -- enough to build glibc, and missing everything glibc's own header
# would have contributed. Assembling the full version now is exactly what
# GCC's build system does when the system header does exist.
#
# The nested substitution is the book's: -print-libgcc-file-name gives the
# path of libgcc.a, whose directory has the include/ that limits.h belongs in.
limits_include=$(dirname "$("${LFS_TGT}-gcc" -print-libgcc-file-name)")/include

if [ ! -d "${limits_include}" ]; then
  echo "gcc-pass1: no ${limits_include} to install limits.h into" >&2
  exit 1
fi

cat gcc/limitx.h gcc/glimits.h gcc/limity.h > "${limits_include}/limits.h"

if [ ! -x "${LFS}/tools/bin/${LFS_TGT}-gcc" ]; then
  echo "gcc-pass1 installed no ${LFS_TGT}-gcc" >&2
  exit 1
fi
