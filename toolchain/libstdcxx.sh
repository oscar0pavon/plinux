#!/bin/bash
#
# LFS 5.6. Libstdc++ from GCC-15.2.0.
#
# Deferred out of gcc-pass1 with --disable-libstdcxx, because the C++ standard
# library is written against a C library and there was not one yet. There is
# now, so it can be built on its own out of the same GCC tree -- libstdc++-v3
# configures and builds standalone, which is exactly what this step relies on.
#
# Needed because parts of GCC are written in C++: chapter 6's binutils-pass2
# and gcc-pass2 are the first things that will not link without it.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

# The same tree gcc-pass1 unpacked, mpfr/gmp/mpc and the t-linux64 sed and
# all. unpack finds it already there and says so.
directory=$(unpack 'gcc-*.tar.xz' 'gcc-15.2.0')
cd "${directory}"

# gcc-pass1 left its own build-cross here and this needs a different one --
# they configure different source trees with different options into the same
# name otherwise.
build=$(fresh_build_dir "${directory}" 'build-libstdcxx')
cd "${build}"

# --host=$LFS_TGT
#   Build with the cross compiler, not this machine's g++.
#
# --build=$(../config.guess)
#   Note the path: config.guess sits at the top of the GCC tree, not under
#   scripts/ where glibc keeps its copy.
#
# --prefix=/usr
#   The eventual location, as everywhere in this chapter. DESTDIR below puts
#   it under $LFS for now.
#
# --disable-multilib, --disable-nls
#   As for gcc-pass1.
#
# --disable-libstdcxx-pch
#   Skip the precompiled headers. They are large, they are a build-time
#   optimisation for compiling C++, and nothing in chapter 6 compiles any.
#
# --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/15.2.0
#   Where $LFS_TGT-g++ will look for the standard C++ headers, and the one
#   option here worth reading twice. It is written as an absolute path
#   starting /tools, with no $LFS -- because the compiler prepends its
#   sysroot, which is $LFS, and so searches $LFS/tools/$LFS_TGT/include/c++/
#   15.2.0. DESTDIR=$LFS on the install below is what actually puts the
#   headers at that path. Writing $LFS into this option would produce
#   $LFS$LFS/tools and the headers would be invisible to the compiler that
#   needs them.
../libstdc++-v3/configure --host="${LFS_TGT}"           \
                          --build="$(../config.guess)"  \
                          --prefix=/usr                 \
                          --disable-multilib            \
                          --disable-nls                 \
                          --disable-libstdcxx-pch       \
                          --with-gxx-include-dir="/tools/${LFS_TGT}/include/c++/15.2.0"

make

make DESTDIR="${LFS}" install

# The .la files describe how to link the library using paths recorded at build
# time. Under cross-compilation those paths are this workstation's, and libtool
# will follow them out of the sysroot given the chance. The book removes them
# for that reason and BLFS keeps finding packages that break on the ones left
# behind elsewhere.
rm -fv "${LFS}"/usr/lib/lib{stdc++{,exp,fs},supc++}.la

# The headers are the half of this step that is easy to get wrong -- the
# --with-gxx-include-dir path above is unforgiving and a mistake in it
# installs everything successfully, somewhere the compiler will not look.
if [ ! -f "${LFS}/tools/${LFS_TGT}/include/c++/15.2.0/vector" ]; then
  echo "libstdcxx: headers are not at ${LFS}/tools/${LFS_TGT}/include/c++/15.2.0" >&2
  echo "check --with-gxx-include-dir; the compiler will not find them there" >&2
  exit 1
fi

if [ ! -f "${LFS}/usr/lib/libstdc++.so" ]; then
  echo "libstdcxx installed no ${LFS}/usr/lib/libstdc++.so" >&2
  exit 1
fi
