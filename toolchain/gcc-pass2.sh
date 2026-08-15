#!/bin/bash
#
# LFS 6.18. GCC-15.2.0 - Pass 2: the compiler the chroot will use.
#
# Pass 1 was a compiler with no C library, built to produce glibc and nothing
# else. This one is built against that glibc and installed into $LFS/usr, so
# chapter 7 has a working C and C++ compiler the moment it chroots. Chapter 8
# then builds GCC a third time, natively, and that one is the image's.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

# The tree gcc-pass1 already prepared: mpfr, gmp and mpc are unpacked inside
# it under those names and the t-linux64 sed is applied. Both are idempotent
# and both are still needed here, so this reuses that work rather than
# unpacking a second 100M copy.
directory=$(unpack 'gcc-*.tar.xz' 'gcc-15.2.0')
cd "${directory}"

for arithmetic in mpfr gmp mpc; do
  if [ ! -d "${arithmetic}" ]; then
    echo "gcc-pass2: ${arithmetic} is not in the gcc tree; run gcc-pass1 first" >&2
    exit 1
  fi
done

if [ ! -f gcc/config/i386/t-linux64.orig ]; then
  echo "gcc-pass2: t-linux64 has not been edited; run gcc-pass1 first" >&2
  exit 1
fi

# POSIX threads for libgcc and libstdc++.
#
# The thread_header variable is normally substituted by the build system from
# a configure test. Cross-compiling, that test cannot run, so it is set
# directly to the POSIX header -- without which libstdc++ is built with thread
# support disabled and every C++ program in chapter 8 that uses std::thread
# links against stubs.
#
# Not idempotent as a sed against @...@, so it is skipped once it has run.
if grep -q 'thread_header = @thread_header@' libgcc/Makefile.in; then
  sed '/thread_header =/s/@.*@/gthr-posix.h/' \
      -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
else
  echo "already applied: gthr-posix.h" >&2
fi

build=$(fresh_build_dir "${directory}" 'build-pass2')
cd "${build}"

# --host=$LFS_TGT --target=$LFS_TGT --build=this machine
#   Both host and target, which looks redundant and is not. --host makes the
#   compiler itself cross-compiled, so it runs in the chroot. --target says
#   what it compiles *for*, and naming it stops the build system reaching for
#   this workstation's gcc to build the target libraries -- libgcc and
#   libstdc++ -- which it would otherwise do, because the compiler being built
#   cannot run here. Building those with a different GCC is unsupported.
#
# --with-build-sysroot=$LFS
#   --host already tells the compiler to look in $LFS. The auxiliary tools
#   GCC's build system runs along the way do not know that, and this tells
#   them.
#
# --disable-libsanitizer
#   Not wanted in a temporary system. Pass 1 got this implicitly from
#   --disable-libstdcxx; here it has to be said.
#
# LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc
#   Point libstdc++ at the libgcc being built right now rather than pass 1's.
#   Pass 1's was compiled without a C library, so its exception handling is
#   incomplete, and C++ exceptions in the chroot would not unwind.
../configure --build="$(../config.guess)"           \
             --host="${LFS_TGT}"                    \
             --target="${LFS_TGT}"                  \
             --prefix=/usr                          \
             --with-build-sysroot="${LFS}"          \
             --enable-default-pie                   \
             --enable-default-ssp                   \
             --disable-nls                          \
             --disable-multilib                     \
             --disable-libatomic                    \
             --disable-libgomp                      \
             --disable-libquadmath                  \
             --disable-libsanitizer                 \
             --disable-libssp                       \
             --disable-libvtv                       \
             --enable-languages=c,c++               \
             LDFLAGS_FOR_TARGET="-L${PWD}/${LFS_TGT}/libgcc"

make

make DESTDIR="${LFS}" install

# Many configure scripts and makefiles run cc rather than gcc.
ln -sfv gcc "${LFS}/usr/bin/cc"

if [ ! -x "${LFS}/usr/bin/gcc" ]; then
  echo "gcc-pass2 installed no ${LFS}/usr/bin/gcc" >&2
  exit 1
fi
