#!/bin/bash
#
# LFS 5.4. Linux API Headers: the kernel's side of every system call, which
# glibc is written against and will not configure without.
#
# The book's linux-6.16.1 tarball, and not src/linux -- the 7.2 kernel this
# image actually boots. That looks like the wrong way round. It was tried the
# other way twice and failed twice, so the reasoning is worth writing down.
#
# The appealing argument for src/linux is that the C library should be
# compiled against headers describing the kernel that will run underneath it.
# The argument is wrong in both directions, for different reasons.
#
# Newer headers can *collide* with what a package declares itself. glibc
# 2.42's sys/mount.h defines OPEN_TREE_CLONE as 1 after including
# <linux/mount.h>; 7.x spells the same value (1 << 0), which is a
# redefinition rather than a duplicate, and glibc compiles -Werror. That one
# is fixable -- the values are equal, so an #ifndef is a no-op -- and it was
# fixed, which is what made the second failure a surprise.
#
# Newer headers can also simply *not have* a header an older package
# includes. gcc 15.2.0's libsanitizer includes <linux/scc.h>. It is in
# 6.16.1. It was removed from the kernel before 7.2. Nothing can guard around
# that: the file does not exist, and the package was written when it did.
#
# So the rule is not "newer headers are riskier", it is that a package is
# written against a kernel vintage and wants that vintage. The syscall ABI is
# forward compatible by policy, so binaries built against 6.16 headers run on
# 7.2 forever, and glibc is configured --enable-kernel=5.4 either way. Old
# headers under a new kernel cost nothing. The reverse costs two days.
#
# src/linux stays the kernel that gets built and booted. It is simply not
# what a C library and a compiler get compiled against.
#
# (The book also runs "make mrproper" first, to clear stale files out of a
# tree that might have been built in. This unpacks a fresh tarball, so there
# is nothing to clear -- and running it against src/linux, which was the
# other reason this script once pointed there, would have deleted
# src/linux/.config, this workstation's kernel configuration.)

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

directory=$(unpack 'linux-6.16.1.tar.xz' 'linux-6.16.1')
cd "${directory}"

make headers

# "make headers" leaves the .cmd files and other residue of the kernel's own
# build system behind; headers_install would have filtered them itself.
find usr/include -type f ! -name '*.h' -delete

# Anything left from a previous run has to go first -- in particular the 7.x
# set that earlier versions of this script installed. A copy only adds and
# overwrites, so a header present in 7.x and absent from 6.16 would survive
# and still be found, which is the same class of problem as the two above and
# harder to see than either.
#
# scsi/ is deliberately not in this list, and it is the one directory here
# that must not be. It is *shared*: glibc installs scsi.h, scsi_ioctl.h and
# sg.h into it, the kernel installs scsi_bsg_fc.h, scsi_netlink.h and the fc
# family. Deleting the directory takes glibc's three with it, and the copy
# below does not put them back -- so gcc's libsanitizer, which includes
# <scsi/scsi.h>, stops exactly the way it stopped on linux/scc.h.
#
# In a build that runs in order this is invisible, because chapter 8's glibc
# reinstalls its headers long after this step. It only surfaces when this
# step is re-run against a tree that already has a glibc in it, which is
# precisely when someone is changing the header version and least wants a
# second puzzle.
#
# Every other directory here belongs to the kernel alone.
rm -rf "${LFS}"/usr/include/{asm,asm-generic,drm,linux,misc,mtd,rdma,sound,video,xen}

cp -r usr/include "${LFS}/usr"

# linux/limits.h is what glibc's configure reaches for first, so its absence
# is the failure that would otherwise surface two steps later as something
# unrecognisable.
if [ ! -f "${LFS}/usr/include/linux/limits.h" ]; then
  echo "linux-headers installed nothing into ${LFS}/usr/include" >&2
  exit 1
fi

# And the two specific headers that sent this script back and forth. Both are
# cheap to check and each stands for a whole class: scc.h for headers a
# package includes and a newer kernel has dropped, mount.h's OPEN_TREE_CLONE
# spelling for constants a newer kernel has redefined.
if [ ! -f "${LFS}/usr/include/linux/scc.h" ]; then
  echo "linux-headers: linux/scc.h is missing" >&2
  echo "gcc's libsanitizer includes it; these headers are too new" >&2
  exit 1
fi

# Matched as "1 followed by whitespace or end of line", not "1 at end of
# line": the definition carries a trailing comment. The point is to tell 1
# apart from (1 << 0), and this does that without caring what follows.
if ! grep -qE '^#define[[:space:]]+OPEN_TREE_CLONE[[:space:]]+1([[:space:]]|$)' \
       "${LFS}/usr/include/linux/mount.h"; then
  echo "linux-headers: linux/mount.h does not spell OPEN_TREE_CLONE the way" >&2
  echo "glibc 2.42 expects; these headers are too new for this glibc" >&2
  exit 1
fi
