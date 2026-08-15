#!/bin/bash
#
# LFS 6.17. Binutils-2.45 - Pass 2.
#
# Pass 1 installed a cross linker into $LFS/tools, which runs on this machine
# and produces target objects. This installs binutils into $LFS/usr instead:
# programs that will run *inside* the chroot, built by the cross compiler.
# Chapter 8 rebuilds them a third and final time, natively.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

# The same tree pass 1 unpacked. Its build directory is build-cross and this
# one is build-pass2, so the two configurations do not meet.
directory=$(unpack 'binutils-*.tar.xz' 'binutils-2.45')
cd "${directory}"

# Binutils links against its own bundled static libraries through the libtool
# copy it ships, but the libiberty and zlib copies in the same tarball do not
# go through libtool. Where they disagree, libtool can add a -L pointing at
# the host's library directory, and the result links against the build
# machine. The sed removes the offending $add_dir.
#
# Anchored to line 6031, which is what the book specifies for this version.
# In binutils 2.45 that line reads
#
#   add_dir="$add_dir -L$inst_prefix_dir$libdir"
#
# and dropping the $add_dir stops it accumulating whatever was already there.
#
# Checked rather than applied blindly. A line number is a fragile thing to
# anchor an edit to, and a sed that silently rewrites the wrong line of
# ltmain.sh produces exactly the sort of host link that nothing notices until
# the binary is somewhere else. The same text also appears at line 5958, so a
# search would not disambiguate; the line number is all there is to go on, and
# that is worth verifying rather than trusting.
ltmain_line=$(sed -n '6031p' ltmain.sh)

case "${ltmain_line}" in
  *'add_dir="$add_dir -L$inst_prefix_dir$libdir"'*)
    sed '6031s/$add_dir//' -i ltmain.sh
    ;;
  *'add_dir=" -L$inst_prefix_dir$libdir"'*)
    echo "already applied: ltmain.sh \$add_dir removal" >&2
    ;;
  *)
    echo "binutils-pass2: ltmain.sh line 6031 is not the line the book edits" >&2
    echo "  expected: add_dir=\"\$add_dir -L\$inst_prefix_dir\$libdir\"" >&2
    echo "  found:    ${ltmain_line}" >&2
    exit 1
    ;;
esac

build=$(fresh_build_dir "${directory}" 'build-pass2')
cd "${build}"

# --prefix=/usr, not $LFS/tools: these are the chroot's binutils.
#
# --host=$LFS_TGT with --build=this machine is what cross-compiles them.
#
# --enable-shared builds libbfd as a shared library; --enable-64-bit-bfd is
# harmless here and the book carries it. The remaining options are pass 1's,
# for the same reasons.
../configure --prefix=/usr                   \
             --build="$(../config.guess)"    \
             --host="${LFS_TGT}"             \
             --disable-nls                   \
             --enable-shared                 \
             --enable-gprofng=no             \
             --disable-werror                \
             --enable-64-bit-bfd             \
             --enable-new-dtags              \
             --enable-default-hash-style=gnu

make

make DESTDIR="${LFS}" install

# The .la files record this workstation's paths, and the static libraries are
# not wanted in a temporary system that is about to be rebuilt natively.
rm -v "${LFS}"/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
