#!/bin/bash
#
# Create the virtual machine disk image: a GPT with an EFI system partition
# and an ext4 root, matching what pboot and build.sh expect.

cd "$(dirname "$(readlink -f "$0")")" || exit 1

image=${IMAGE:-disk.raw}
size_mb=${SIZE_MB:-4096}
esp_mb=${ESP_MB:-100}

loop=

usage(){
  cat <<'USAGE'
Usage: ./configure.sh [command]

Creates disk.raw with an EFI system partition and an ext4 root partition.

Commands:
  (none)      Create the image; refuses if one already has partitions
  reformat    Destroy and recreate an existing image
  help        This message

Environment:
  IMAGE       image file    (default disk.raw)
  SIZE_MB     total size    (default 4096)
  ESP_MB      EFI partition (default 100)

The loop device is released before exiting. Populate the image with
../build.sh virt, which mounts it itself.
USAGE
}

cleanup(){
  if [ -n "${loop}" ]; then
    umount "${loop}p1" 2>/dev/null
    umount "${loop}p2" 2>/dev/null
    losetup -d "${loop}" 2>/dev/null
  fi
}
trap cleanup EXIT

case "${1:-}" in
  help|-h|--help) usage; exit 0 ;;
  ''|reformat)    ;;
  *)
    echo "unknown command: $1" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac

if [ "$(id -u)" -ne 0 ]; then
  echo "must run as root: losetup, mkfs and mount all need it" >&2
  exit 1
fi

# Refuse to destroy a populated image by accident. The old version ran mkfs
# unconditionally, so re-running it wiped whatever had been built into it.
if [ -e "${image}" ] && [ "${1:-}" != "reformat" ]; then
  if sfdisk -l "${image}" 2>/dev/null | grep -q "^${image}1"; then
    echo "${image} already has a partition table." >&2
    echo "Run './configure.sh reformat' to destroy and recreate it." >&2
    exit 1
  fi
fi

if [ ! -e "${image}" ]; then
  echo "creating ${image} (${size_mb}M)"
  if ! dd if=/dev/zero of="${image}" bs=1M count="${size_mb}" status=none; then
    echo "cannot create ${image}" >&2
    exit 1
  fi
fi

# The partition table was never written here before, which is why mkfs was
# handed a p1 that did not exist on a fresh image.
echo "writing partition table"
if ! sfdisk --quiet "${image}" <<EOF
label: gpt
start=2048, size=$((esp_mb * 1024 * 2)), type=uefi, name="EFI System"
start=$((2048 + esp_mb * 1024 * 2)), type=linux, name="plinux root"
EOF
then
  echo "cannot partition ${image}" >&2
  exit 1
fi

# A free device rather than a hardcoded /dev/loop0, which fails with "Device
# or resource busy" whenever anything else is holding it.
loop=$(losetup -f --show -P "${image}")
if [ -z "${loop}" ]; then
  echo "cannot attach ${image} to a loop device" >&2
  exit 1
fi
echo "attached ${loop}"

# Partition nodes are created asynchronously, so they are not there the
# instant losetup returns
for _ in $(seq 50); do
  [ -e "${loop}p1" ] && [ -e "${loop}p2" ] && break
  sleep 0.1
done

if [ ! -e "${loop}p1" ] || [ ! -e "${loop}p2" ]; then
  echo "partition devices ${loop}p1 and ${loop}p2 did not appear" >&2
  exit 1
fi

echo "formatting ${loop}p1 as fat"
if ! mkfs.fat "${loop}p1" > /dev/null; then
  echo "cannot format the EFI partition" >&2
  exit 1
fi

echo "formatting ${loop}p2 as ext4"
if ! mkfs.ext4 -q "${loop}p2"; then
  echo "cannot format the root partition" >&2
  exit 1
fi

mkdir -p disk/boot disk/root

echo
echo "${image} is ready; populate it with ../build.sh virt"
