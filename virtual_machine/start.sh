#!/bin/sh

cd "$(dirname "$(readlink -f "$0")")" || exit 1

# -display none only drops the window. The emulated VGA device stays, so OVMF
# still publishes a GOP and pboot's graphics keep working; its text goes to
# serial along with the rest of the firmware output.
# Do not add -vga none: that would remove the GOP pboot draws on.
qemu-system-x86_64 -enable-kvm -bios ./uefi.bios\
  -drive file=./disk.raw,format=raw,media=disk\
  -m 1G\
  -display none\
  -serial stdio
