#!/bin/bash
#
# LFS 5.4. Linux API Headers: the kernel's side of every system call, which
# glibc is written against and will not configure without.
#
# Two deviations from the book here, both because plinux already has a kernel
# and the book does not.
#
# The book unpacks linux-6.16.1.tar.xz. This uses src/linux, the shallow clone
# ./configure makes, which is the kernel this image actually boots -- 7.2, not
# 6.16 -- so there is one kernel source in this repository and it is the one
# that gets built. glibc 2.42 does not compile against these headers without a
# one-line guard; see the OPEN_TREE_CLONE note in toolchain/glibc.sh for what
# that is and why it is a no-op. sources/linux-6.16.1.tar.xz is kept as the
# fallback if that ever stops being true.
#
# The book then runs "make mrproper" to clear stale files out of a freshly
# unpacked tarball. That would be actively destructive here: mrproper deletes
# .config, and src/linux/.config is this workstation's kernel configuration,
# copied in by ./configure from sys/kernel_config. Recovering it is one
# ./configure away, but a step that silently resets the kernel config is not
# one to leave lying in a build script. A git clone has no stale files to
# clear in the first place.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

if [ ! -d "${src_directory}/linux" ]; then
  echo "no ${src_directory}/linux; run ./configure first" >&2
  exit 1
fi

cd "${src_directory}/linux"

# Anything left from a previous run has to go first. A copy only adds and
# overwrites, so a header that existed in an older run and not in this one
# would survive and still be found -- the same class of problem as a stale
# library in obj/, and harder to see.
rm -rf "${LFS}"/usr/include/{asm,asm-generic,drm,linux,misc,mtd,rdma,scsi,sound,video,xen}

# headers_install rather than the book's "make headers" plus a find that
# deletes everything not ending in .h.
#
# The book avoids this target because it needs rsync, which it will not assume
# a host has. This one does, and build.sh's own stage_kernel_headers has been
# using headers_install into obj/usr since the sysroot went in -- so this is
# the arrangement already in service here, pointed at $LFS instead.
#
# INSTALL_HDR_PATH ends in /usr because the kernel appends "include" to it.
make headers_install INSTALL_HDR_PATH="${LFS}/usr"

# linux/limits.h is the one glibc's configure reaches for first, so its
# absence is the failure that would otherwise surface two steps later as
# something unrecognisable.
if [ ! -f "${LFS}/usr/include/linux/limits.h" ]; then
  echo "linux-headers installed nothing into ${LFS}/usr/include" >&2
  exit 1
fi
