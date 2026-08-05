#!/bin/sh

cd "$(dirname "$(readlink -f "$0")")" || exit 1

# -display none only drops the window. The emulated VGA device stays, so OVMF
# still publishes a GOP and pboot's graphics keep working; its text goes to
# serial along with the rest of the firmware output.
# Do not add -vga none: that would remove the GOP pboot draws on.
# -cpu host passes the real CPU through instead of emulating qemu64, whose
# model reports no ssse3, sse4, popcnt, avx, avx2 or bmi at all. Without it a
# guest built with -march=native executes an AVX2 instruction and dies with
# SIGILL, because the image is compiled for the machine that built it.
# Free with KVM: the guest is running on this CPU either way.
qemu-system-x86_64 -enable-kvm -bios ./uefi.bios\
  -cpu host\
  -drive file=./disk.raw,format=raw,media=disk\
  -m 1G\
  -display none\
  -serial stdio
