if [ ! -e disk.raw ];then
dd if=/dev/zero of=disk.raw bs=1M count=1024
fi

losetup -P /dev/loop0 disk.raw
#TODO format disks

losetup -d /dev/loop0

#rescan partions
losetup -P /dev/loop0 disk.raw

mkdir -p disk/root
mkdir -p disk/boot


mkfs.fat /dev/loop0p1
mkfs.ext4 /dev/loop0p2

mount /dev/loop0p1 disk/boot
mount /dev/loop0p2 disk/root
