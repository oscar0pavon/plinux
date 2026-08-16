#!/bin/sh

cd "$(dirname "$(readlink -f "$0")")" || exit 1

usage(){
  cat <<'USAGE'
Usage: ./run [headless]

Boots a raw disk image under QEMU with a machine close to the workstation:
q35, the host CPU, an NVMe disk, xHCI and virtio devices.

  (none)      GTK window, with the console on the emulated display
  headless    No window; console on serial, which is what scripted runs
              and this session's boot tests use

Environment:
  IMAGE       disk image to boot            (default disk.raw)
  MEMORY      guest RAM                     (default 8G)
  CPUS        guest cpu count               (default 8)
  VGA         display device                (default virtio-vga-gl)
  USB_DISK    host block device to pass in  (default none)

USB_DISK hands a real disk to the guest, which can write to it. It is
deliberately not set by default: /dev/sdb is whatever was plugged in last,
and passing the wrong one through is not recoverable.
USAGE
}

# Which image to boot. disk.raw is the one ./configure.sh makes by default,
# and stays the default here, so nothing that used to work changes. It exists
# because there is now more than one: a tree built the old way and a tree
# built in the chroot do not have to be the same size, and keeping a known
# good image while an unproven one is tested is worth a variable.
image=${IMAGE:-disk.raw}

if [ ! -e "${image}" ]; then
  echo "${image} does not exist; create it with ./configure.sh" >&2
  echo "  IMAGE=${image} SIZE_MB=4096 ./configure.sh" >&2
  exit 1
fi

memory=${MEMORY:-8G}
cpus=${CPUS:-8}
# virtio-vga-gl, not virtio-vga. The plain device gives the guest a
# virtio-gpu with no GL driver behind it, and mesa here has none for it:
# EGL fails with "virtio_gpu: driver missing", falls back to kms_swrast --
# llvmpipe, also not built -- and sway exits with "Failed to create renderer".
#
# The -gl device pairs with mesa's virgl gallium driver in the guest and
# serialises its GL to the host, where it runs on the real card. That makes
# the VM exercise the same EGL/GLES2 path as the hardware rather than a
# software renderer that is never shipped.
#
# It only exists in a QEMU built against virglrenderer. Falling back rather
# than failing, because a QEMU without it is otherwise perfectly usable --
# sway will not start, but everything below the compositor will.
vga=${VGA:-virtio-vga-gl}

if ! qemu-system-x86_64 -device help 2>/dev/null | grep -q "\"${vga}\""; then
  if [ "${vga}" = "virtio-vga-gl" ]; then
    echo "this qemu has no virtio-vga-gl; falling back to virtio-vga" >&2
    echo "  rebuild it with --enable-virglrenderer for accelerated graphics" >&2
    vga=virtio-vga
  else
    echo "this qemu has no ${vga}" >&2
    exit 1
  fi
fi
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
  -drive file="./${image}",format=raw,if=none,id=nvme0 \
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
  # egl-headless rather than none. -display none drops OpenGL with it, and a
  # guest on virtio-vga-gl then has no GL at all -- which is the whole point
  # of the device. egl-headless renders offscreen through the host's EGL, so
  # the guest keeps its accelerated GL with no window on screen.
  #
  # The adapter stays either way, so OVMF still publishes a GOP and pboot's
  # graphics keep working; its text goes to serial with the rest of the
  # firmware output. Do not add -vga none: that would remove the GOP pboot
  # draws on.
  if [ "${vga}" = "virtio-vga-gl" ]; then
    set -- "$@" -device "${vga}" -display egl-headless -serial stdio
  else
    set -- "$@" -device "${vga}" -display none -serial stdio
  fi
else
  # gl=on hands rendering to the host GPU. show-tabs and show-menubar off keep
  # the window to just the guest display.
  set -- "$@" \
    -device "${vga}" \
    -display gtk,gl=on,show-tabs=off,show-menubar=off \
    -boot menu=on,splash-time=10000
fi

exec qemu-system-x86_64 "$@"
