#!/bin/bash
# uses pushd/popd and [ "$1" == ... ], so it needs bash and not plain sh

export MAKEFLAGS=-j32

# Resolve to the repository root rather than the caller's directory, so the
# script works from anywhere. Taking $(pwd) meant running it as
# ../build.sh from virtual_machine/ looked for virtual_machine/obj.
cd "$(dirname "$(readlink -f "$0")")" || exit 1

working_directory=$(pwd)
src_directory=${working_directory}/src
build_directory=${working_directory}/obj
sources_directory=${working_directory}/sources

# Where the redistributable firmware blobs are taken from, and which ones.
# The build host is the machine the image is for, so what it loads is what
# the image needs.
#
#   amdgpu       the Radeon card. DRM_AMDGPU is a module and will not
#                initialise without these, 57M of them
#   iwlwifi-so-a0-gf-a0-*
#                Intel Wi-Fi 6E AX211. CONFIG_IWLWIFI is built in, so there
#                is no module to load, but the firmware still has to be here
#                or the radio never comes up and iwd has nothing to drive.
#                The whole API-version family, not just the -89 this kernel
#                asks for today: the driver walks down from the newest it
#                knows to the first one present, so a kernel change would
#                otherwise silently lose the adapter
#   regulatory.db
#                cfg80211 loads it separately from any driver; without it
#                the regulatory domain falls back to the most restrictive
#                set of channels
firmware_source=${FIRMWARE_SOURCE:-/usr/lib/firmware}
firmware_wanted=(amdgpu iwlwifi-so-a0-gf-a0-*.ucode regulatory.db regulatory.db.p7s)

pushd(){
  command pushd "$@" > /dev/null
}

popd(){
  command popd "$@" > /dev/null
}

usage(){
  cat <<'USAGE'
Usage: ./build.sh [command]

Builds plinux into obj/, which is the staged root filesystem.

Commands:
  (none)      Build this project's own components: pboot, kernel, pinit,
              pgetty, plogin and bash, installing each into obj/. The LFS
              packages are a separate step, see "packages" below
  virt        Copy obj/ and the bootloader into virtual_machine/disk.raw.
              Builds nothing, so run a plain ./build.sh first if any
              source changed
  usb <dev>   Write obj/ to a USB disk as a bootable rescue system. Erases
              the device, which must be named in full: there is no default.
              Partitions it GPT, makes the filesystems, then writes a
              pboot.conf and an /etc/fstab carrying that disk's own
              identifiers, so the stick boots itself and not the machine it
              is plugged into. USB_YES=1 skips the typed confirmation
  packages    Build the LFS packages listed in packages/order into obj/.
              Already-installed ones are skipped. On a terminal the package
              being built is shown on a line pinned to the top of the screen

                packages <name>   rebuild just that one, skipped or not
                packages force    rebuild every one of them

              "Installed" means a stamp in obj/.packages, so "clean all"
              makes the next run build everything again. Cleaning the
              source trees does not: they unpack again when needed
  quiet       Not a command: add it to any of the above, or set VERBOSE=0,
              to only log build output instead of streaming it. Output is
              streamed by default; "verbose" is accepted and is the default
  check       Report installed binaries whose shared libraries are missing
              from obj/. Those programs build and install cleanly but fail
              at startup, so nothing else notices. Exits non-zero if any
  clean       Clean the cloned source trees and bash's configure output,
              and delete the unpacked package trees, which unpack again
              from sources/ on the next build
  clean all   As above, and delete obj/ entirely
  tools       Accepted but does nothing; the cross toolchain section at
              the end of this script is unreachable
  help        This message

Notes:
  Can be run from any directory; paths resolve relative to the script.
  virt needs root: it uses losetup and mount.
  Components are built with MAKEFLAGS=-j32.

Examples:
  ./build.sh              # full build into obj/
  ./build.sh virt         # push obj/ into the VM image
  ./build.sh clean all    # start over
USAGE
}

if [ "$1" == "help" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
  usage
  exit 0
fi

# Without this an unrecognised argument falls through to a full build, so a
# typo like "./build.sh vrit" rebuilds everything instead of staging the image
case "${1:-}" in
  ""|virt|usb|clean|tools|packages|check|verbose|quiet) ;;
  *)
    echo "unknown command: $1" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac

# Build output is streamed by default. It still goes to logs/ either way, but
# watching a compile happen is worth more than a clean screen, and a build that
# has silently stalled is otherwise indistinguishable from one that is working.
#
# "quiet" turns it off, and either word may appear as any argument, so both
# combine with force and all. VERBOSE=0 in the environment also silences it.
verbose=1

if [ "${VERBOSE:-1}" == "0" ]; then
  verbose=
fi

for argument in "$@"; do
  case "${argument}" in
    verbose) verbose=1 ;;
    quiet)   verbose=  ;;
  esac
done

log_directory=${working_directory}/logs
mkdir -p "${log_directory}"

failed=0
skipped=0

# Output goes to a log rather than /dev/null, and only the tail is shown when
# something breaks. Discarding it meant a failed build was reported as nothing
# more than the "cp" that came after it.
run(){
  local name=$1
  shift

  local status

  if [ -n "${verbose}" ]; then
    # tee so the log is still written for later. The status has to come from
    # PIPESTATUS: in a pipeline $? is tee's, which succeeds even when the
    # build it is printing has failed.
    "$@" 2>&1 | tee "${log_directory}/${name}.log"
    status=${PIPESTATUS[0]}
  else
    "$@" > "${log_directory}/${name}.log" 2>&1
    status=$?
  fi

  if [ "${status}" -eq 0 ]; then
    return 0
  fi

  echo "  FAILED: $*" >&2

  # in verbose mode the output has already gone past
  if [ -z "${verbose}" ]; then
    echo "  last lines of ${log_directory}/${name}.log:" >&2
    sed 's/^/    /' <<< "$(tail -15 "${log_directory}/${name}.log")" >&2
  fi

  return 1
}

# A line pinned to the top of the terminal naming the package being built.
# Build output scrolls underneath it: the terminal's scroll region is set to
# everything below row 1, so nothing can overwrite the status.
#
# Only when stdout is a terminal. Redirected to a file or a pipe these escapes
# would just be noise in the log.
status_active=

status_start(){
  [ -t 1 ] || return 0

  status_rows=$(tput lines 2>/dev/null) || status_rows=${LINES:-24}
  status_active=1

  printf '\e[2;%dr' "${status_rows}"   # scroll region: row 2 to the bottom
  printf '\e[%d;1H' "${status_rows}"   # park the cursor inside it

  # restore the terminal however this exits, including Ctrl-C: a shell left
  # with a scroll region set behaves as if the top line were stuck
  trap status_stop EXIT
  trap 'status_stop; exit 130' INT
  trap 'status_stop; exit 143' TERM
}

status_stop(){
  [ -n "${status_active}" ] || return 0
  status_active=

  printf '\e[r'                        # whole screen scrolls again
  printf '\e[1;1H\e[2K'                # wipe the status row
  printf '\e[%d;1H' "${status_rows}"
}

# \e7 and \e8 save and restore the cursor, so writing the status does not
# disturb where the build output is being written
status_set(){
  [ -n "${status_active}" ] || return 0
  printf '\e7\e[1;1H\e[2K\e[7m %s \e[0m\e8' "$1"
}

mkdir -p obj/usr/bin obj/usr/lib obj/usr/sbin

# The /bin -> /usr/bin merge, as four symlinks.
#
# The target is "usr/bin", not "../../../usr/bin". Both resolve to /usr/bin
# once the tree is the root filesystem -- ".." at "/" is "/" -- but only the
# relative form also resolves correctly when the tree is read from here, as
# obj/usr/bin. The ../../.. form escapes obj entirely and lands on the build
# machine's own /usr, which is why "ls obj/bin" once reported tar and ps as
# installed when neither was: it was listing the host's /usr/bin.
#
# That escape is not only a reporting problem. Anything that searches the
# staged tree by path -- a --sysroot link, INSTALL_MOD_PATH, a check against
# the image's libraries -- silently reaches the host through it, and succeeds,
# because this machine runs plinux and its libraries are the right ones. It
# would only fail in the VM or off the rescue USB.
#
# Repaired unconditionally: trees built before this still hold the old form.
for link in bin:usr/bin sbin:usr/sbin lib:usr/lib lib64:usr/lib;do
  link_name=obj/${link%%:*}
  link_target=${link#*:}

  # obj/sbin used to be a real directory, which left /sbin/ip and /sbin/udevd
  # unreachable. Only replaced when empty, so nothing installed there is lost.
  if [ -d "${link_name}" ] && [ ! -L "${link_name}" ];then
    rmdir "${link_name}" 2>/dev/null || {
      echo "${link_name} is a non-empty directory; expected a symlink to ${link_target}" >&2
      exit 1
    }
  fi

  if [ "$(readlink "${link_name}" 2>/dev/null)" != "${link_target}" ];then
    ln -sfn "${link_target}" "${link_name}"
  fi
done

# Mount points and standard directories. pinit mounts tmpfs on /run and
# sysfs on /sys, and a mount whose target does not exist just fails, which is
# how udev ended up unable to create /run/udev. Done unconditionally so trees
# made before these were listed get them too.
mkdir -p obj/{dev,proc,sys,run,var,var/log,boot,mnt,etc,root}

# /var/run is where programs written before /run existed still look. iwd is
# one: the ell it bundles compiles in unix:path=/var/run/dbus/system_bus_socket
# while dbus listens on /run/dbus/system_bus_socket, so without this iwd
# reports "Failed to initialize D-Bus" and exits. Relative, like /bin and
# /lib, so it resolves in the image rather than in obj.
if [ ! -e obj/var/run ]; then
  ln -sf ../run obj/var/run
fi
mkdir -p obj/tmp && chmod 1777 obj/tmp

# The kernel's userspace API headers -- linux/, asm/, asm-generic/, drm/ and
# the rest of uapi. Every package that speaks to the kernel by structure
# rather than through libc needs them, and the GUI stack is nothing but: DRM
# ioctls, evdev, memfd_create.
#
# These were never staged. Everything built so far found them in the build
# machine's /usr/include instead, and nothing complained, because that is a
# copy of the same headers. Under --sysroot it is the first thing to fail,
# and correctly so: obj was never a complete place to compile against.
#
# INSTALL_HDR_PATH ends in /usr because the kernel appends "include" to it.
stage_kernel_headers(){
  [ -d "${src_directory}/linux" ] || return 0

  local status=0

  pushd "${src_directory}/linux"
  make headers_install INSTALL_HDR_PATH="${build_directory}/usr" > /dev/null || status=$?
  popd

  return ${status}
}

# Cheap, but not free, so only when they are absent -- the kernel step below
# refreshes them whenever the kernel itself is rebuilt. input.h is the check
# because it is the one libinput and libevdev fail on.
if [ ! -f obj/usr/include/linux/input.h ];then
  echo "Installing kernel headers into obj/usr/include"
  stage_kernel_headers || echo "kernel headers not installed" >&2
fi

if [ -d obj ];then

  musl_directory=${build_directory}

  target=$(uname -m)-plinux-gnu
fi

# Every shared library an installed binary names has to be in the image too.
# Getting this wrong is silent: the package builds against the host's copy,
# installs cleanly, and the program only fails when someone runs it. That is
# how kmod shipped unable to start, and how dmesg and lsblk went unnoticed.
if [ "$1" == "check" ]; then
  echo "Checking installed binaries against the image's libraries"

  unresolved=0
  checked=0

  for binary in ${build_directory}/usr/bin/* ${build_directory}/usr/sbin/* \
                ${build_directory}/usr/lib/*.so*; do
    [ -f "${binary}" ] || continue

    # skips scripts, symlinks and the static ones, which have no NEEDED
    readelf -d "${binary}" > /dev/null 2>&1 || continue

    checked=$((checked + 1))

    for library in $(readelf -d "${binary}" 2>/dev/null |
                     sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
      # the loader itself is named by absolute path and lives in /usr/lib
      case "${library}" in ld-*) continue ;; esac

      if [ ! -e "${build_directory}/usr/lib/${library}" ]; then
        echo "  ${binary#${build_directory}} needs ${library}"
        unresolved=$((unresolved + 1))
      fi
    done
  done

  echo
  echo "checked ${checked} binaries"

  if [ "${unresolved}" -ne 0 ]; then
    echo "${unresolved} unresolved dependencies" >&2
    echo "each of those programs fails at startup in the image" >&2
    exit 1
  fi

  echo "every dependency resolves inside the image"
  exit
fi

if [ "$1" == "packages" ]; then
  echo "Building packages"

  # A package that installed successfully leaves a stamp, so a rerun picks up
  # where it stopped instead of rebuilding everything. "packages force"
  # ignores them.
  #
  # The stamps live inside obj because that is what they are a statement
  # about: this package is installed in *this* tree. Keeping them under logs/
  # meant "clean all" removed obj and left the stamps behind, so every package
  # reported "have" while the tree stayed empty. The leading dot keeps them
  # out of the "cp -a obj/*" that populates the image.
  stamp_directory=${build_directory}/.packages
  mkdir -p "${stamp_directory}"

  # The second argument selects what to rebuild: "force" for everything, a
  # package name for just that one. verbose and quiet are not names, they are
  # the output setting handled above.
  package_force=
  package_only=

  case "${2:-}" in
    ''|verbose|quiet) ;;
    force)            package_force=1 ;;
    *)                package_only=$2 ;;
  esac

  package_total=$(grep -cv -e '^[[:space:]]*$' -e '^[[:space:]]*#' \
                    "${working_directory}/packages/order")
  package_number=0
  package_matched=

  status_start
  status_set "starting"

  while read -r package; do
    case "${package}" in ''|\#*) continue ;; esac

    package_number=$((package_number + 1))

    # naming one package builds only it, whatever its stamp says
    if [ -n "${package_only}" ]; then
      if [ "${package}" != "${package_only}" ]; then
        continue
      fi
      package_matched=1
    fi

    script=${working_directory}/packages/${package}.sh

    if [ ! -x "${script}" ]; then
      echo "  ${package}: no ${script}" >&2
      failed=$((failed + 1))
      continue
    fi

    if [ -f "${stamp_directory}/${package}" ] &&
       [ -z "${package_force}" ] && [ -z "${package_only}" ]; then
      echo "  have ${package}"
      continue
    fi

    echo "  ${package}"
    status_set "${package}   [${package_number}/${package_total}]"

    if run "package-${package}" "${script}"; then
      touch "${stamp_directory}/${package}"
    else
      failed=$((failed + 1))
      status_set "${package}   [${package_number}/${package_total}]   FAILED"
      # later packages link against earlier ones, so carrying on would only
      # produce a second, more confusing failure
      break
    fi
  done < "${working_directory}/packages/order"

  status_stop

  echo

  # a name that is in no order file is a typo, not a request to build nothing
  if [ -n "${package_only}" ] && [ -z "${package_matched}" ]; then
    echo "no such package: ${package_only}" >&2
    echo "packages are listed in ${working_directory}/packages/order" >&2
    exit 1
  fi

  if [ "${failed}" -ne 0 ]; then
    echo "${failed} package(s) failed; logs are in ${log_directory}" >&2
    exit 1
  fi

  echo "packages installed into ${build_directory}"
  exit
fi

if [ "$1" == "virt" ]; then
  echo "Virtual Machine"

  pushd virtual_machine

  if [ ! -e disk.raw ]; then
    echo "disk.raw does not exist; create it with ./configure.sh" >&2
    exit 1
  fi

  mkdir -p disk/boot disk/root

  # A free device rather than a hardcoded /dev/loop0, which fails with "Device
  # or resource busy" whenever anything else holds it. This also drops the two
  # unconditional umounts that used to run first and always complained about
  # having no mount point.
  loop=$(losetup -f --show -P disk.raw)
  if [ -z "${loop}" ]; then
    echo "cannot attach disk.raw to a loop device" >&2
    exit 1
  fi

  # Partition nodes are created asynchronously, so they are not there the
  # instant losetup returns
  for _ in $(seq 50); do
    [ -e "${loop}p1" ] && [ -e "${loop}p2" ] && break
    sleep 0.1
  done

  mount "${loop}p1" disk/boot
  mount "${loop}p2" disk/root

  # If a mount silently failed, the writes below would land in the plain
  # directories under the mountpoints instead of the image, and the rm would
  # delete the working tree rather than the image contents.
  if ! mountpoint -q disk/boot || ! mountpoint -q disk/root; then
    echo "mount failed, refusing to touch disk/" >&2
    umount disk/boot 2>/dev/null
    umount disk/root 2>/dev/null
    losetup -d "${loop}"
    exit 1
  fi

  ##### Boot
  mkdir -p disk/boot/EFI/BOOT
  cp ${build_directory}/pboot disk/boot/EFI/BOOT/BOOTX64.EFI
  cp pboot.conf disk/boot

  cp ${build_directory}/vmlinuz disk/boot/vmlinuz

  ##### Root filesystem
  rm -rf disk/root/*

  # -a, not -r: the root filesystem depends on bin/lib/lib64 staying symlinks
  # and on permissions being preserved
  cp -a ${build_directory}/* disk/root

  umount disk/boot
  umount disk/root

  losetup -d "${loop}"

  popd

  echo "disk.raw updated"

  exit
fi

if [ "$1" == "usb" ]; then
  usb_device=$2

  if [ -z "${usb_device}" ]; then
    echo "usage: ./build.sh usb /dev/sdX" >&2
    echo "no default: this erases the device it is given" >&2
    exit 1
  fi

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

  echo "Partitioning ${usb_device}"

  # 256M ESP, the rest for the root filesystem. The partition type GUIDs are
  # what the firmware looks for: C12A7328 marks the EFI system partition and
  # 0FC63DAF is a plain Linux filesystem.
  sfdisk --quiet --wipe always --wipe-partitions always "${usb_device}" <<'PARTITIONS'
label: gpt
size=256M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI System"
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="plinux root"
PARTITIONS

  partprobe "${usb_device}" 2>/dev/null || true
  udevadm settle 2>/dev/null || true

  # Partition nodes appear asynchronously, the same way they do for the loop
  # device in the virt step. p1/p2 on nvme and mmc, 1/2 on everything else.
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

  if [ ! -b "${usb_esp}" ] || [ ! -b "${usb_root}" ]; then
    echo "partitions did not appear on ${usb_device}" >&2
    exit 1
  fi

  echo "Making filesystems"

  # mkfs.fat, not mkfs.vfat: dosfstools installs the vfat name only as a
  # compatibility symlink, and this build host does not have it. FAT32
  # because it is what UEFI implementations agree on for removable media.
  mkfs.fat -F 32 -n PLINUXESP "${usb_esp}" > /dev/null
  mkfs.ext4 -q -F -L plinuxroot "${usb_root}"

  udevadm settle 2>/dev/null || true

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
    echo "cannot read the identifiers back from ${usb_device}" >&2
    exit 1
  fi

  echo "  root PARTUUID ${usb_root_partuuid}"
  echo "  ESP UUID      ${usb_esp_uuid}"

  usb_mount=$(mktemp -d)
  mkdir -p "${usb_mount}/boot" "${usb_mount}/root"

  mount "${usb_esp}"  "${usb_mount}/boot"
  mount "${usb_root}" "${usb_mount}/root"

  if ! mountpoint -q "${usb_mount}/boot" || ! mountpoint -q "${usb_mount}/root"; then
    echo "mount failed, refusing to write" >&2
    umount "${usb_mount}/boot" 2>/dev/null
    umount "${usb_mount}/root" 2>/dev/null
    rmdir "${usb_mount}/boot" "${usb_mount}/root" "${usb_mount}" 2>/dev/null
    exit 1
  fi

  echo "Copying the system"

  mkdir -p "${usb_mount}/boot/EFI/BOOT"
  cp ${build_directory}/pboot   "${usb_mount}/boot/EFI/BOOT/BOOTX64.EFI"
  cp ${build_directory}/vmlinuz "${usb_mount}/boot/vmlinuz"

  # Written here rather than copied from virtual_machine/pboot.conf, which
  # names the VM's disk. Every stick gets its own root=, so one that is
  # plugged into a machine that already runs plinux still boots itself:
  # sharing a PARTUUID with the internal disk would leave the kernel to pick
  # whichever it enumerated first, which for a rescue disk is the wrong one.
  cat > "${usb_mount}/boot/pboot.conf" <<CONFIGURATION
m 0
e 0
n "plinux"
k "vmlinuz"
p "root=PARTUUID=${usb_root_partuuid} rw init=/pinit rootwait console=tty0 console=ttyS0,115200"
CONFIGURATION

  # -a for the same reason as the virt step: bin, lib and lib64 have to stay
  # symlinks and the permissions have to survive
  cp -a ${build_directory}/* "${usb_mount}/root"

  # This stick's own fstab. The image ships one describing the VM disk, and
  # /dev/nvme0n1p1 does not exist here.
  cat > "${usb_mount}/root/etc/fstab" <<FSTAB
# /etc/fstab for a plinux rescue disk, written by ./build.sh usb
#
# UUID rather than a device name: this disk is /dev/sda on one machine and
# /dev/sdc on the next. mount(8) resolves UUID= through libblkid.
UUID=${usb_esp_uuid}  /boot  vfat  defaults,noauto  0 0
FSTAB

  sync

  umount "${usb_mount}/boot"
  umount "${usb_mount}/root"
  rmdir "${usb_mount}/boot" "${usb_mount}/root" "${usb_mount}" 2>/dev/null

  echo "${usb_device} is ready"
  exit
fi

if [ "$1" == "tools" ]; then
  echo "building tools"
else
  echo "Building standard"
fi

if [ "$1" == "clean" ]; then
  echo "Cleaning source trees"

  for component in pboot linux pinit pgetty plogin; do
    if [ -d ${src_directory}/${component} ]; then
      echo "  ${component}"
      pushd ${src_directory}/${component}
      make clean &> /dev/null
      popd
    fi
  done

  # bash keeps a configure-generated Makefile; distclean removes it so the
  # next build reconfigures with the right prefix
  if [ -f ${src_directory}/bash/Makefile ]; then
    echo "  bash"
    pushd ${src_directory}/bash
    make distclean &> /dev/null
    popd
  fi

  # The package trees are unpacked tarballs, not clones, so they are removed
  # rather than "make clean"ed: the tarball is the source of truth and the
  # unpacked directory is itself a build artifact. This also drops any patches
  # applied in place, which "make clean" would leave behind.
  #
  # Only directories that can be recreated are removed. A versioned name with
  # no matching tarball in sources/ is left alone, so nothing unrecoverable
  # goes: re-extracting it would be impossible without downloading again.
  #
  # Installed packages are not affected. Their stamps live in obj and say the
  # package is installed in *that* tree, which is still true; "clean all"
  # removes obj and takes the stamps with it.
  removed=0

  for tree in ${src_directory}/*-[0-9]*/; do
    [ -d "${tree}" ] || continue

    name=$(basename "${tree}")

    if ! ls "${sources_directory}/${name}".tar.* > /dev/null 2>&1; then
      echo "  keeping ${name}, no tarball to unpack it from again"
      continue
    fi

    echo "  ${name}"
    rm -rf "${tree}"
    removed=$((removed + 1))
  done

  if [ "${removed}" -ne 0 ]; then
    echo "removed ${removed} package tree(s); they unpack again on the next build"
  fi

  # "clean all" also discards the staged root filesystem
  if [ "$2" == "all" ]; then
    if [ -n "${build_directory}" ] && [ -d "${build_directory}" ]; then
      echo "Removing ${build_directory}"
      rm -rf "${build_directory}"
    fi
  fi

  exit

fi

################## Build ###################

stage(){
  if [ ! -f "$1" ]; then
    echo "  FAILED: $1 was not produced" >&2
    return 1
  fi

  if ! cp "$1" "$2"; then
    echo "  FAILED: cannot copy $1 to $2" >&2
    return 1
  fi

  return 0
}

# Sources come and go as components move to their own repositories, so a
# missing tree is reported and skipped instead of aborting the whole build.
have_source(){
  echo "$1"
  status_set "$1"

  if [ ! -d "$2" ]; then
    echo "  skipping, $2 is not present" >&2
    status_set "$1   skipped, no source"
    skipped=$((skipped + 1))
    return 1
  fi

  return 0
}

# Every component below announces itself through have_source, so the status
# line follows the build without each step having to set it.
status_start

if have_source "Building bootloader" ${src_directory}/pboot; then
  pushd ${src_directory}/pboot
  # the Makefile's target is pboot.efi; pboot alone is the raw pboot.bin stage
  if run pboot make; then
    stage pboot.efi ${build_directory}/pboot || failed=$((failed + 1))
  else
    failed=$((failed + 1))
  fi
  popd
fi

if have_source "Building kernel" ${src_directory}/linux; then
  pushd ${src_directory}/linux

  # ./configure normally puts this in place; do it here too so a build works on
  # a tree that was cloned by hand
  if [ ! -f .config ]; then
    cp ${working_directory}/sys/kernel_config .config
  fi

  # The config was saved from 6.14.6 and the clone tracks mainline, so it will
  # be missing symbols the current kernel has added. olddefconfig takes the
  # default for each of them instead of prompting and stalling the build.
  # Refreshed with the kernel, so a config or version change that adds an
  # ioctl or a structure field reaches the packages built against it.
  run kernel-headers make headers_install INSTALL_HDR_PATH=${build_directory}/usr \
    || failed=$((failed + 1))

  if run kernel-config make olddefconfig && run kernel make; then
    # x86_64 was merged into arch/x86 in 2.6.24; arch/x86_64 has not existed
    # for a very long time
    stage arch/x86/boot/bzImage ${build_directory}/vmlinuz || failed=$((failed + 1))

    # The config builds around 40 modules, amdgpu among them, and none of
    # them used to be installed: the image booted with no GPU driver at all
    # on real hardware. The VM hid this, because virtio-gpu is built in.
    #
    # INSTALL_MOD_PATH ends in /usr on purpose. The kernel appends
    # "lib/modules" to it, and obj/lib is a symlink; back when it pointed at
    # ../../../usr/lib, passing obj alone here installed this kernel's modules
    # over the build machine's own. The symlink is relative now, so both spell
    # the same directory, but naming the real path leaves nothing to resolve.
    if ! run kernel-modules make modules_install       \
             INSTALL_MOD_PATH=${build_directory}/usr   \
             INSTALL_MOD_STRIP=1; then
      failed=$((failed + 1))
    fi
  else
    failed=$((failed + 1))
  fi

  popd
fi

# Firmware the drivers ask the kernel for at probe time. Not built from
# anything here: these are redistributable blobs, taken from the build host,
# which is the machine the image is for.
#
# Only what this hardware loads. All of /usr/lib/firmware is 1.1G against a
# 922M root partition, so copying the lot is not an option even if it were
# worth it.
if [ -d "${firmware_source}" ]; then
  echo "Installing firmware"

  mkdir -p ${build_directory}/usr/lib/firmware

  for entry in "${firmware_wanted[@]}"; do
    # A glob that matches nothing expands to itself, which would then be
    # reported as a missing file. Let the shell tell us instead.
    for match in ${firmware_source}/${entry}; do
      if [ -e "${match}" ]; then
        cp -a "${match}" ${build_directory}/usr/lib/firmware/
      else
        echo "  no firmware matching ${entry}" >&2
      fi
    done
  done
fi

if have_source "Building init PID 1" ${src_directory}/pinit; then
  pushd ${src_directory}/pinit
  if run pinit make; then
    stage pinit ${build_directory}/pinit || failed=$((failed + 1))
  else
    failed=$((failed + 1))
  fi
  popd
fi

# The daemon supervisor. Into /usr/sbin rather than / like pinit: pinit has
# to be at a path the kernel is told about in pboot.conf, this one only has
# to be on a path pinit can exec.
if have_source "Building daemon supervisor" ${src_directory}/pdaemon; then
  pushd ${src_directory}/pdaemon
  if run pdaemon make; then
    stage pdaemon ${build_directory}/usr/sbin/pdaemon || failed=$((failed + 1))
  else
    failed=$((failed + 1))
  fi
  popd
fi

if have_source "Building getty" ${src_directory}/pgetty; then
  pushd ${src_directory}/pgetty
  if run pgetty make; then
    stage pgetty ${build_directory}/usr/bin/pgetty || failed=$((failed + 1))
  else
    failed=$((failed + 1))
  fi
  popd
fi

if have_source "Building login" ${src_directory}/plogin; then
  pushd ${src_directory}/plogin
  if run plogin make; then
    # must match LOGIN_PROGRAM in src/pgetty/main.c
    stage plogin ${build_directory}/usr/bin/plogin || failed=$((failed + 1))
  else
    failed=$((failed + 1))
  fi
  popd
fi

# bash is a package now, in packages/order. It was a component here, and the
# component steps have no stamps: every ./build.sh reran build_static.sh,
# which began by throwing away its own objects, so bash reconfigured and
# recompiled from zero each time. That was seventeen seconds of a
# twenty-five-second no-op build, for a tree that never changes.


# glibc is built by packages/glibc.sh, from the tarball download.sh fetches.
# The step that used to be here worked on src/glibc, a clone that no longer
# exists, so every build printed "Building glibc" and then skipped it. It also
# predated the fhs patch and the configparms rootsbindir the package sets.


echo "Installing system configuration"
status_set "Installing system configuration"

mkdir -p ${build_directory}/root
mkdir -p ${build_directory}/etc

# Everything under sys/etc, whatever it is, rather than a cp line per file.
# There are two sources of /etc in this image and they are not the same kind
# of thing:
#
#   packages install their own defaults straight into obj/etc through
#   DESTDIR -- mke2fs.conf, vimrc, dbus-1/, ssl/, xattr.conf, udev/. Those
#   are build output. "clean all" deletes them and rebuilding puts them back,
#   so editing one there does not survive
#
#   sys/etc is this machine's configuration, kept in the repository. Adding a
#   file here used to mean adding a cp line as well, which is why it held
#   only passwd, group and fstab
#
# Copied last so the machine's version wins over a package default of the
# same name. Note that packages only build when asked for ("./build.sh
# packages"), so running that after a plain build puts the package defaults
# back on top; run the plain build again afterwards.
#
# What is in there today:
#   passwd, group  without a user database getpwuid(0) fails and bash's \u
#                  shows "I have no name!". Nothing authenticates yet: plogin
#                  execs the shell directly, and the x defers to an
#                  /etc/shadow that does not exist, so no password is valid
#                  rather than none being needed
#   fstab          pinit runs "mount -a -F" over it, so this decides what the
#                  image mounts. The workstation keeps its own; this one
#                  describes the VM disk
cp -a ${working_directory}/sys/etc/. ${build_directory}/etc/

# plogin sets HOME=/root and chdir()s there, so without these the login shell
# falls back to bash's default prompt and none of this configuration loads.
cp ${working_directory}/sys/root/.bash_profile ${build_directory}/root/
cp ${working_directory}/sys/root/.bashrc       ${build_directory}/root/

# .bashrc looks for the repo copy first and this one second; on the target
# there is no /root/plinux, so this is the one that gets sourced
cp ${working_directory}/sys/root/shell_config.sh ${build_directory}/root/

# on the workstation these are reached through /root/plinux/sys/scripts on
# PATH, which does not exist on the target
cp ${working_directory}/sys/scripts/* ${build_directory}/usr/bin/

status_stop

echo
if [ "${skipped}" -ne 0 ]; then
  echo "${skipped} component(s) skipped for missing sources"
fi

if [ "${failed}" -ne 0 ]; then
  echo "${failed} component(s) failed; logs are in ${log_directory}" >&2
  exit 1
fi

echo "SUCCESS you have plinux"
exit


################## Toolchain ###################

build_directory=""
src_directory=""
musl_directory=""

if [ -d obj ];then

  pushd ${src_directory}

  echo "############# Building Binutils"
  pushd ${src_directory}/binutils
  mkdir obj
  pushd ${src_directory}/binutils/obj
  ../configure --prefix=${build_directory}/tools \
             --with-sysroot=${build_directory} \
             --target=${target}       \
             --disable-nls       \
             --enable-gprofng=no \
             --disable-werror    \
             --enable-new-dtags  \
             --enable-default-hash-style=gnu
  make -j32
  make -j32 install

  popd #src


  pushd ${src_directory}/gcc

  mkdir obj
  pushd ${src_directory}/gcc/obj

  ../configure                              \
    --target=${target}                      \
    --prefix=${build_directory}/tools       \
    --with-glibc-version=2.41               \
    --with-sysroot=${build_directory}       \
    --with-newlib             \
    --without-headers         \
    --enable-default-pie      \
    --enable-default-ssp      \
    --disable-nls             \
    --disable-shared          \
    --disable-multilib        \
    --disable-threads         \
    --disable-libatomic       \
    --disable-libgomp         \
    --disable-libquadmath     \
    --disable-libssp          \
    --disable-libvtv          \
    --disable-libstdcxx       \
    --enable-languages=c,c++

  make -j32
  make install


  popd #src

else
  mkdir -p obj/tools
fi
