
qemu-system-x86_64 -enable-kvm -bios ./uefi.bios\
  -drive file=disk.raw,format=raw,media=disk\
  -m 1G
