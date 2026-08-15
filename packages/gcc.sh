#!/bin/bash
#
# gcc - the compiler. LFS 12.4 section 8.29.
#
# The third build, and the one that stays. Chapter 5's pass 1 was a compiler
# with no C library, built only to produce glibc. Chapter 6's pass 2 was
# cross-compiled into $LFS/usr so the chroot had something to compile with.
# This is the native one, built by pass 2 against the image's own glibc, and
# it is what makes the image able to rebuild itself rather than being
# something only this workstation can produce.
#
# It also replaces packages/gcc-runtime.sh's reason for existing. That script
# copies libstdc++, libgcc_s and libgomp out of the host toolchain because
# building them meant building GCC. This builds GCC.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'gcc-*.tar.xz' 'gcc-15.2.0')
cd "${directory}"

export CC=gcc

# x86_64 gcc defaults to installing 64-bit libraries in lib64. This image has
# no /usr/lib64 -- obj/lib64 is a symlink onto usr/lib and the book is
# emphatic that a real one breaks things -- so the multilib directory name is
# changed to lib.
#
# Guarded on the .orig the book's -i.orig leaves behind, because chapters 5
# and 6 unpack this same tarball into src/gcc-15.2.0 and may have applied it
# already. The sed is not idempotent.
if [ ! -f gcc/config/i386/t-linux64.orig ]; then
  sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
fi

# A build directory of its own, and not the build-cross or build-pass2 that
# toolchain/ uses in this same tree.
rm -rf build-native
mkdir -p build-native
cd build-native

# LD=ld
#   Use the binutils ld installed just before this, rather than the
#   cross-built one from chapter 6 that would otherwise be found first.
#
# --disable-bootstrap
#   Build gcc once with the existing compiler rather than three times with
#   itself. The three-stage bootstrap is a compiler self-check; the compiler
#   doing the building here is chapter 6's gcc-pass2, which is the same
#   version from the same source.
#
# --disable-fixincludes
#   gcc otherwise "fixes" system headers at install time. That is for old
#   proprietary unixes, and on a modern system it is actively harmful --
#   reinstalling a package after gcc leaves the fixed copies stale.
#
# --enable-host-pie, --enable-default-pie, --enable-default-ssp
#   Position-independent executables and stack protection, for gcc itself
#   and for what it compiles.
#
# --with-system-zlib
#   The zlib built earlier rather than gcc's bundled copy.
#
# gmp, mpfr and mpc are not named: they are installed packages by now, and
# gcc finds them the ordinary way. That is the difference between this and
# the two earlier passes, which unpacked them inside the source tree.
../configure --prefix=/usr            \
             LD=ld                    \
             --enable-languages=c,c++ \
             --enable-default-pie     \
             --enable-default-ssp     \
             --enable-host-pie        \
             --disable-multilib       \
             --disable-bootstrap      \
             --disable-fixincludes    \
             --with-system-zlib

make

make DESTDIR="${build_directory}" install

# LFS 8.29's finishing touches.
#
# cpp is expected in /usr/lib by some programs -- the book calls it a
# "historical" location and creates the link rather than arguing.
mkdir -p "${build_directory}/usr/lib"
ln -sfv ../bin/cpp "${build_directory}/usr/lib/cpp"

ln -sfv gcc.1 "${build_directory}/usr/share/man/man1/cc.1"

# The LTO plugin, where binutils looks for it. ar, nm and ranlib load it to
# read object files gcc compiled with -flto, and without this link they
# report such files as having no symbols.
#
# gcc -dumpmachine rather than a hardcoded triplet: outside the chroot this
# is the host's gcc reporting x86_64-pc-linux-gnu, inside it is the image's.
gcc_triplet=$(gcc -dumpmachine)
mkdir -p "${build_directory}/usr/lib/bfd-plugins"
ln -sfv "../../libexec/gcc/${gcc_triplet}/15.2.0/liblto_plugin.so" \
        "${build_directory}/usr/lib/bfd-plugins/"

# gdb's python pretty-printers for libstdc++ install beside the library,
# where gdb will not look for them.
if ls "${build_directory}"/usr/lib/*gdb.py > /dev/null 2>&1; then
  mkdir -pv "${build_directory}/usr/share/gdb/auto-load/usr/lib"
  mv -v "${build_directory}"/usr/lib/*gdb.py \
        "${build_directory}/usr/share/gdb/auto-load/usr/lib"
fi
