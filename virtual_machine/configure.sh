dd if=/dev/zero of=disk.raw bs=1M count=1024

losetup disk.raw
mkdir -p disk/root
mkdir -p disk/boot

#TODO format disks

mount /dev/loop0p1 disk/boot
mount /dev/loop0p2 disk/root
