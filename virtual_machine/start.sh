#!/bin/sh

cd "$(dirname "$(readlink -f "$0")")" || exit 1

usage(){
  cat <<'USAGE'
Usage: ./run [headless]

Boots virtual_machine/disk.raw under QEMU with a machine close to the
workstation: q35, the host CPU, an NVMe disk, xHCI and virtio devices.

  (none)      GTK window, with the console on the emulated display
  headless    No window; console on serial, which is what scripted runs
              and this session's boot tests use

Environment:
  MEMORY      guest RAM                     (default 8G)
  CPUS        guest cpu count               (default 8)
  VGA         display adapter               (default virtio)
  USB_DISK    host block device to pass in  (default none)

USB_DISK hands a real disk to the guest, which can write to it. It is
deliberately not set by default: /dev/sdb is whatever was plugged in last,
and passing the wrong one through is not recoverable.
USAGE
}

memory=${MEMORY:-8G}
cpus=${CPUS:-8}
vga=${VGA:-virtio}
usb_disk=${USB_DISK:-}

case "${1:-}" in
  help|-h|--help) usage; exit 0 ;;
  headless)       headless=1 ;;
  "")             headless= ;;
  *)              echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
esac

# The disk is attached as NVMe rather than IDE, so the guest sees
# /dev/nvme0n1 exactly as the workstation does. pboot.conf and /etc/fstab
# name the partitions that way; changing the interface here means changing
# both of them.
set -- \
  -enable-kvm \
  -machine q35 \
  -cpu host \
  -smp "${cpus}" \
  -m "${memory}" \
  -bios ./uefi.bios \
  -drive file=./disk.raw,format=raw,if=none,id=nvme0 \
  -device nvme,drive=nvme0,serial=plinux0 \
  -device qemu-xhci,id=xhci \
  -device virtio-keyboard-pci

# The kernel config dropped e1000 when it was refreshed from the workstation,
# which has no such card. virtio-net is built in, so the guest has a network
# device either way.
set -- "$@" -device virtio-net-pci,netdev=net0 -netdev user,id=net0

if [ -n "${usb_disk}" ]; then
  if [ ! -b "${usb_disk}" ]; then
    echo "USB_DISK=${usb_disk} is not a block device" >&2
    exit 1
  fi
  echo "passing ${usb_disk} through to the guest, which can write to it"
  set -- "$@" \
    -drive "file=${usb_disk},format=raw,if=none,id=usbdisk0" \
    -device usb-storage,drive=usbdisk0,bus=xhci.0
fi

if [ -n "${headless}" ]; then
  # -display none only drops the window. The adapter stays, so OVMF still
  # publishes a GOP and pboot's graphics keep working; its text goes to serial
  # along with the rest of the firmware output.
  # Do not add -vga none: that would remove the GOP pboot draws on.
  set -- "$@" -vga "${vga}" -display none -serial stdio
else
  # gl=on hands rendering to the host GPU. show-tabs and show-menubar off keep
  # the window to just the guest display.
  set -- "$@" \
    -vga "${vga}" \
    -display gtk,gl=on,show-tabs=off,show-menubar=off \
    -boot menu=on,splash-time=10000
fi

exec qemu-system-x86_64 "$@"
