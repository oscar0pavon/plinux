#!/bin/bash
# uses [ "$1" == ... ] and local, so it needs bash and not plain sh
#
# Write the rescue system to a USB disk, by building usb.img from lfs/ and
# pouring it on with dd.
#
# Lived in build.sh as "./build.sh usb" and was lifted out whole. Nothing here
# builds anything: it reads the tree build.sh leaves in lfs/ and turns it into
# a disk, which is a different job from compiling one, and it is the only path
# in this repository that can destroy something the build cannot make again --
# the wrong device. That is worth a file of its own rather than four hundred
# lines in the middle of a build script, and build.sh still forwards
# "./build.sh usb" here so the command that was documented keeps working.
#
# Needs root: losetup, mount, mkfs and dd on a raw device.

# Resolve to the repository root rather than the caller's directory, as
# build.sh does and for the same reason: lfs/ is named relative to the script.
cd "$(dirname "$(readlink -f "$0")")" || exit 1

working_directory=$(pwd)

# The tree that becomes the disk. The same name and the same default as
# build.sh, and $LFS overrides it in both.
lfs_directory=${LFS:-${working_directory}/lfs}
build_directory=${lfs_directory}

usb_target=$1

if [ -z "${usb_target}" ] || [ "${usb_target}" == "help" ] || [ "${usb_target}" == "-h" ] || [ "${usb_target}" == "--help" ]; then
  echo "usage: ./usb.sh /dev/sdX   write the rescue disk to a stick" >&2
  echo "       ./usb.sh image      build usb.img and stop there" >&2
  echo "no default device: this erases the one it is given" >&2
  exit 1
fi

# Where the image is built, and what "usb image" leaves behind. USB_IMAGE
# moves it, for keeping a known-good one while a new one is unproven, the
# way IMAGE does for the VM disk.
usb_image=${USB_IMAGE:-${working_directory}/usb.img}

# Everything the paths below have to undo, in one place, so that a Ctrl-C
# leaves nothing mounted and nothing attached.
#
# An interrupted write used to leave the ESP and the root filesystem mounted
# on a temporary directory, and the next run then refused to start because
# it found the device mounted -- the reason being a directory under /tmp
# whose name said nothing about where it came from. Worse, the pages already
# written were the kernel's by then and went on reaching the stick for an
# hour after the script that wrote them had gone.
#
# Each variable is cleared as it is dealt with, because this runs from the
# INT and TERM traps and then again from the EXIT trap on the way out.
usb_mount=
usb_loop=
usb_partial=
usb_writing=

usb_cleanup(){
  if [ -n "${usb_mount}" ]; then
    umount "${usb_mount}/boot" 2>/dev/null
    umount "${usb_mount}/root" 2>/dev/null
    rmdir "${usb_mount}/boot" "${usb_mount}/root" "${usb_mount}" 2>/dev/null
    usb_mount=
  fi

  if [ -n "${usb_loop}" ]; then
    losetup -d "${usb_loop}" 2>/dev/null
    usb_loop=
  fi

  # A half-built image is not an image. It is written under .new and renamed
  # only when it is finished, so usb.img is either complete or absent --
  # which is the whole point of a file whose purpose is to be handed to
  # somebody else.
  if [ -n "${usb_partial}" ]; then
    rm -f "${usb_partial}"
    usb_partial=
  fi
}

usb_cancelled(){
  local signal=$1

  usb_cleanup

  echo >&2
  echo "cancelled" >&2

  # Said plainly, because a stick that is half an image looks exactly like a
  # stick that is a whole one until it is booted.
  if [ -n "${usb_writing}" ]; then
    echo "${usb_writing} was part written and will not boot; write it again" >&2
  fi

  exit "${signal}"
}

trap 'usb_cancelled 130' INT
trap 'usb_cancelled 143' TERM
trap 'usb_cleanup' EXIT

# Build usb.img from lfs/.
#
# Sized from the tree rather than fixed. The image is poured onto the stick
# byte for byte, so a megabyte of slack here is a megabyte written for
# nothing; the root filesystem is grown to fill the stick after the write
# instead, which costs no transfer at all.
usb_build_image(){
  local content_mb root_mb total_mb
  local usb_esp usb_root usb_root_partuuid usb_esp_uuid

  content_mb=$(du -sB1M "${build_directory}" | cut -f1)

  # A quarter over the tree, and 256M on top of that. ext4 needs room for
  # what it keeps about the tree -- 49,000 inodes, the journal, the block
  # and inode bitmaps -- and a rescue system with no space to write a file
  # is not much of a rescue system.
  root_mb=$(( content_mb + content_mb / 4 + 256 ))

  # 1M of GPT and alignment at the front, 256M of ESP, 1M at the end for the
  # backup GPT header.
  total_mb=$(( 1 + 256 + root_mb + 1 ))

  echo "Building ${usb_image}: ${total_mb}M for ${content_mb}M of system"

  usb_partial=${usb_image}.new
  rm -f "${usb_partial}"

  # Sparse, so the file occupies what is written into it and not its length.
  # dd reads the holes back as zeros, which is what the stick needs anyway.
  if ! truncate -s "${total_mb}M" "${usb_partial}"; then
    echo "cannot create ${usb_partial}" >&2
    return 1
  fi

  # The same 256M ESP and the same two type GUIDs the stick was partitioned
  # with directly before this: C12A7328 is what firmware looks for to find
  # an EFI system partition, 0FC63DAF is a plain Linux filesystem.
  sfdisk --quiet "${usb_partial}" <<'PARTITIONS'
label: gpt
size=256M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI System"
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="plinux root"
PARTITIONS

  # -P so the kernel reads the partition table and gives us loopNp1 and
  # loopNp2, and a free device rather than a fixed one, as in the virt step.
  usb_loop=$(losetup -f --show -P "${usb_partial}")

  if [ -z "${usb_loop}" ]; then
    echo "cannot attach ${usb_partial} to a loop device" >&2
    return 1
  fi

  # The partition nodes are created asynchronously
  for _ in $(seq 50); do
    [ -b "${usb_loop}p1" ] && [ -b "${usb_loop}p2" ] && break
    sleep 0.1
  done

  usb_esp=${usb_loop}p1
  usb_root=${usb_loop}p2

  if [ ! -b "${usb_esp}" ] || [ ! -b "${usb_root}" ]; then
    echo "partitions did not appear on ${usb_loop}" >&2
    return 1
  fi

  echo "  making filesystems"

  # mkfs.fat, not mkfs.vfat: dosfstools installs the vfat name only as a
  # compatibility symlink, and this build host does not have it. FAT32
  # because it is what UEFI implementations agree on for removable media.
  mkfs.fat -F 32 -n PLINUXESP "${usb_esp}" > /dev/null || return 1
  mkfs.ext4 -q -F -L plinuxroot "${usb_root}" || return 1

  # Read back what the filesystems and the partition table actually got,
  # rather than assuming a value and writing it into the configuration.
  #
  # These are two different kinds of identifier and they are not
  # interchangeable. The kernel resolves root=PARTUUID= on its own, from the
  # GPT, before any filesystem is mounted -- root=UUID= would need an
  # initramfs to run blkid, which this system does not have. /etc/fstab is
  # read later by mount(8), which does have libblkid, so UUID= is right
  # there.
  usb_root_partuuid=$(blkid -s PARTUUID -o value "${usb_root}")
  usb_esp_uuid=$(blkid -s UUID -o value "${usb_esp}")

  if [ -z "${usb_root_partuuid}" ] || [ -z "${usb_esp_uuid}" ]; then
    echo "cannot read the identifiers back from ${usb_loop}" >&2
    return 1
  fi

  echo "  root PARTUUID ${usb_root_partuuid}"
  echo "  ESP UUID      ${usb_esp_uuid}"

  usb_mount=$(mktemp -d)
  mkdir -p "${usb_mount}/boot" "${usb_mount}/root"

  mount "${usb_esp}"  "${usb_mount}/boot"
  mount "${usb_root}" "${usb_mount}/root"

  # If a mount silently failed the writes below would land in the plain
  # directories under the mount points, filling the build host's /tmp with
  # a copy of the system and leaving the image empty.
  if ! mountpoint -q "${usb_mount}/boot" || ! mountpoint -q "${usb_mount}/root"; then
    echo "mount failed, refusing to write" >&2
    return 1
  fi

  mkdir -p "${usb_mount}/boot/EFI/BOOT"
  cp "${build_directory}/pboot"   "${usb_mount}/boot/EFI/BOOT/BOOTX64.EFI"
  cp "${build_directory}/vmlinuz" "${usb_mount}/boot/vmlinuz"

  # Written here rather than copied from virtual_machine/pboot.conf, which
  # names the VM's disk.
  #
  # The PARTUUID is the image's, so every stick written from this image
  # answers to the same one. Against the machine this was built on that is
  # still distinct -- a fresh GPT gets random UUIDs and will not collide
  # with the internal disk -- but two sticks from one image plugged into the
  # same machine would, and the kernel would take whichever it enumerated
  # first. For a rescue disk handed to somebody else that is the right
  # trade: the image has to name a root that exists before it is written.
  cat > "${usb_mount}/boot/pboot.conf" <<CONFIGURATION
m 0
e 0
n "plinux"
k "vmlinuz"
p "root=PARTUUID=${usb_root_partuuid} rw init=/pinit rootwait console=tty0 console=ttyS0,115200"
CONFIGURATION

  echo "  copying the system"

  # -a for the same reason as the virt step: bin, lib and lib64 have to stay
  # symlinks and the permissions have to survive.
  #
  # rsync when there is one, for --info=progress2. --no-inc-recursive makes
  # the percentage honest: rsync's default is to discover the tree as it
  # copies, so the total it reports a fraction of keeps growing and the
  # number walks backwards. Scanning first costs a few seconds and buys a
  # figure that only ever goes up.
  #
  # The same ${build_directory}/* glob cp used, deliberately, and not a
  # trailing slash: a slash would sweep in the dotfiles at the top of the
  # tree, and those are the build host's bookkeeping rather than part of the
  # system being written.
  #
  # cp is kept for the case where there is no rsync, and for when stdout is
  # not a terminal -- progress2 redraws itself with carriage returns, which
  # is noise once it has been captured into a file.
  if [ -t 1 ] && command -v rsync > /dev/null 2>&1; then
    rsync -a --info=progress2 --no-inc-recursive ${build_directory}/* "${usb_mount}/root" || return 1
  else
    cp -a ${build_directory}/* "${usb_mount}/root" || return 1
  fi

  # The rescue disk's own fstab. lfs/etc/fstab describes the VM disk, and
  # /dev/nvme0n1p1 does not exist on whatever this is plugged into.
  cat > "${usb_mount}/root/etc/fstab" <<FSTAB
# /etc/fstab for a plinux rescue disk, written by ./usb.sh
#
# UUID rather than a device name: this disk is /dev/sda on one machine and
# /dev/sdc on the next. mount(8) resolves UUID= through libblkid.
UUID=${usb_esp_uuid}  /boot  vfat  defaults,noauto  0 0
FSTAB

  # Unmounted here rather than left to usb_cleanup, because the image is not
  # finished until the filesystems are closed and the rename below must not
  # publish one that is still open.
  umount "${usb_mount}/boot"
  umount "${usb_mount}/root"
  rmdir "${usb_mount}/boot" "${usb_mount}/root" "${usb_mount}" 2>/dev/null
  usb_mount=

  losetup -d "${usb_loop}"
  usb_loop=

  mv "${usb_partial}" "${usb_image}"
  usb_partial=

  echo "${usb_image} is ready ($(du -h "${usb_image}" | cut -f1) on disk)"
}

# Grow the root partition and its filesystem to fill the stick.
#
# The image is sized to the system, so a 2G image on a 16G stick leaves 14G
# unreachable. Growing after the write costs nothing to transfer: the
# partition entry is one sector and resize2fs writes metadata, not data.
#
# Failure here is a warning and not an error. The stick already holds a
# complete bootable system at the image's size; the only thing lost is the
# space beyond it.
usb_grow(){
  local device=$1
  local root=$2
  local status

  # The backup GPT header sits at the end of the image, which is the middle
  # of the stick. Every tool that reads the table will complain until it is
  # moved to where the secondary header belongs.
  if ! sfdisk --quiet --relocate gpt-bak-std "${device}"; then
    echo "  warning: cannot move the backup GPT header to the end of ${device}" >&2
    return 1
  fi

  # ", +" is sfdisk's way of saying "same start, all the space there is".
  # -N 2 edits that one entry and leaves the rest of the table alone, which
  # is what keeps the root PARTUUID that pboot.conf names.
  if ! echo ', +' | sfdisk --quiet --no-reread --force -N 2 "${device}"; then
    echo "  warning: cannot grow partition 2 on ${device}" >&2
    return 1
  fi

  partprobe "${device}" 2>/dev/null || true
  udevadm settle 2>/dev/null || true

  # resize2fs refuses a filesystem that has not been checked since it was
  # last written, and the write it has just had was a byte-for-byte copy
  # rather than a clean unmount. -p fixes what can be fixed without asking.
  #
  # 1 means it corrected something, which after an image write it will:
  # anything above that is a filesystem this should not be resizing.
  e2fsck -fp "${root}" > /dev/null 2>&1
  status=$?

  if [ "${status}" -gt 1 ]; then
    echo "  warning: e2fsck ${root} returned ${status}; not resizing" >&2
    return 1
  fi

  if ! resize2fs "${root}" > /dev/null 2>&1; then
    echo "  warning: cannot resize the filesystem on ${root}" >&2
    return 1
  fi

  return 0
}

if [ "${usb_target}" == "image" ]; then
  usb_build_image || exit 1
  exit
fi

usb_device=${usb_target}

if [ ! -b "${usb_device}" ]; then
  echo "${usb_device} is not a block device" >&2
  exit 1
fi

# Refuse a partition. Handing this /dev/sdb1 and having it repartition
# /dev/sdb would be a surprise worth avoiding.
#
# -d matters: without it lsblk reports the device and its children, and
# every child names this disk as its parent, so a whole disk looks like a
# partition and nothing could ever be written.
if [ -n "$(lsblk -dno PKNAME "${usb_device}" 2>/dev/null)" ]; then
  echo "${usb_device} is a partition; give the whole disk" >&2
  exit 1
fi

# The disk this machine is running from, which is the one mistake that
# cannot be undone
usb_name=${usb_device#/dev/}
root_source=$(findmnt -no SOURCE / 2>/dev/null)
root_disk=$(lsblk -dno PKNAME "${root_source}" 2>/dev/null | head -1)

if [ -n "${root_disk}" ] && [ "${root_disk}" == "${usb_name}" ]; then
  echo "${usb_device} is the disk this system is running from" >&2
  exit 1
fi

if findmnt -rno SOURCE | grep -q "^${usb_device}"; then
  echo "${usb_device} has mounted partitions; unmount them first" >&2
  findmnt -rno SOURCE,TARGET | grep "^${usb_device}" >&2
  exit 1
fi

usb_size=$(lsblk -dno SIZE "${usb_device}" 2>/dev/null | tr -d ' ')
usb_model=$(lsblk -dno MODEL "${usb_device}" 2>/dev/null | sed 's/ *$//')
usb_removable=$(lsblk -dno RM "${usb_device}" 2>/dev/null | tr -d ' ')

echo "About to erase ${usb_device}"
echo "  model     ${usb_model:-unknown}"
echo "  size      ${usb_size:-unknown}"
echo "  removable ${usb_removable:-unknown}"

if [ "${usb_removable}" != "1" ]; then
  echo "  warning: this device does not report itself as removable" >&2
fi

# USB_YES=1 for a scripted run. Typed confirmation otherwise, and not y/n:
# the whole point is that it should not be reachable by leaning on return.
if [ "${USB_YES:-}" != "1" ]; then
  printf "Type ERASE to continue: "
  read -r usb_answer
  if [ "${usb_answer}" != "ERASE" ]; then
    echo "cancelled"
    exit 1
  fi
fi

# Built if it is not there, and rebuilt if the system is newer than it.
# -newer against the tree itself rather than against a stamp, because the
# question is exactly whether this copy of lfs/ is behind lfs/. -print -quit
# stops at the first file that answers it.
if [ ! -f "${usb_image}" ]; then
  usb_build_image || exit 1
elif [ -n "$(find "${build_directory}" -newer "${usb_image}" -print -quit 2>/dev/null)" ]; then
  echo "${usb_image} is older than ${build_directory}; building it again"
  usb_build_image || exit 1
else
  echo "Using ${usb_image}, which is newer than ${build_directory}"
fi

usb_image_bytes=$(stat -c %s "${usb_image}")
usb_device_bytes=$(blockdev --getsize64 "${usb_device}")

if [ "${usb_image_bytes}" -gt "${usb_device_bytes}" ]; then
  echo "${usb_image} is $(( usb_image_bytes / 1024 / 1024 ))M and ${usb_device} holds $(( usb_device_bytes / 1024 / 1024 ))M" >&2
  exit 1
fi

echo "Writing $(( usb_image_bytes / 1024 / 1024 ))M to ${usb_device}"

# oflag=direct is what makes this cancellable. Without it the write lands in
# the page cache at memory speed and the kernel spends the next hour handing
# it to the stick, owning data the script cannot take back: killing the
# script then cancels nothing, and the only way to stop it is to make the
# device disappear. With it, every block goes to the device before dd asks
# for the next one, so a Ctrl-C stops the write where it stands.
#
# It is also the faster path here by a wide margin. This is one sequential
# stream, which is the access pattern a flash controller is built for --
# against the 49,000 small scattered writes of a file-by-file copy, which is
# the one it is worst at.
#
# conv=fsync for the device's own cache, which direct I/O does not reach.
usb_writing=${usb_device}

if [ -t 1 ]; then
  dd if="${usb_image}" of="${usb_device}" bs=4M oflag=direct conv=fsync status=progress || exit 1
else
  dd if="${usb_image}" of="${usb_device}" bs=4M oflag=direct conv=fsync status=none || exit 1
fi

usb_writing=

partprobe "${usb_device}" 2>/dev/null || true
udevadm settle 2>/dev/null || true

# p1/p2 on nvme, mmc and loop devices, 1/2 on everything else
if [ -b "${usb_device}p1" ]; then
  usb_esp=${usb_device}p1
  usb_root=${usb_device}p2
else
  usb_esp=${usb_device}1
  usb_root=${usb_device}2
fi

for _ in $(seq 50); do
  [ -b "${usb_esp}" ] && [ -b "${usb_root}" ] && break
  sleep 0.1
done

echo "Growing the root filesystem to fill ${usb_device}"

if usb_grow "${usb_device}" "${usb_root}"; then
  echo "  $(lsblk -no SIZE "${usb_root}" 2>/dev/null | tr -d ' ') of root filesystem"
else
  echo "  left at the image's size; the disk is bootable either way"
fi

sync

echo "${usb_device} is ready"
exit
