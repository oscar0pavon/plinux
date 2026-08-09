#!/bin/bash
#
# dosfstools - fsck.fat, mkfs.fat and fatlabel.
#
# Not an LFS package; this one is from BLFS. The ESP is FAT and the image
# could not check it: Linux marks a FAT volume dirty on mount and refuses to
# clear that flag on unmount once it is already set, so a single power cut
# leaves /boot reporting "Volume was not properly unmounted" on every boot
# afterwards. Only a filesystem check clears it, and until now that meant
# borrowing fsck.fat from the build host.
#
# e2fsprogs is the same argument for the ext4 root.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'dosfstools-*.tar.gz' 'dosfstools-4.2')
cd "${directory}"

# musl, like the other standalone programs: nothing links against these.

# --enable-compat-symlinks is what installs the names the kernel and fsck(8)
# actually look for. fsck(8) dispatches on the filesystem type in /etc/fstab,
# so a vfat entry sends it looking for fsck.vfat, and without the symlinks it
# would find only fsck.fat.
./configure --prefix=/usr            \
            --enable-compat-symlinks \
            --mandir=/usr/share/man  \
            --docdir=/usr/share/doc/dosfstools-4.2

make

make DESTDIR="${build_directory}" install
