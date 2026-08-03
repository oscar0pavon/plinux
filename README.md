# plinux

A complete Linux distribution built from source, with its own bootloader, init,
getty and login written in C. No GRUB, no systemd, no busybox.

## Components

Everything with a `p` prefix is written for this project:

| Component | What it is |
| --- | --- |
| [pboot](src/pboot) | UEFI bootloader. Reads `pboot.conf`, loads a kernel with parameters, optional menu |
| [pinit](src/pinit) | PID 1. Mounts the filesystems, brings up the network, starts the gettys |
| [pgetty](src/pgetty) | Console getty, derived from mingetty |
| [plogin](src/plogin) | Sets up the root environment and execs the shell |

Third-party sources live in `src/` alongside them:

| Source | Version | Notes |
| --- | --- | --- |
| linux | 6.14.6 | built with `pavon_defconfig` |
| bash | 5.3 | static against musl, with bash's bundled termcap |
| musl | 1.2.5 | libc for every `p*` component and bash |
| glibc | 2.41 | staged into the image for dynamically linked binaries |

## Layout

```
build.sh              build everything into obj/, or stage obj/ into the VM image
run                   symlink to virtual_machine/start.sh
obj/                  staged root filesystem; becomes / in the image
src/                  component sources and third-party trees
sys/                  scripts and dotfiles for a running system
virtual_machine/      QEMU image, OVMF firmware, pboot.conf, launcher
```

## Building

```sh
./build.sh help       # all commands
./build.sh            # full build into obj/
./build.sh virt       # copy obj/ into virtual_machine/disk.raw
./build.sh clean all  # clean sources and delete obj/
```

`virt` builds nothing, so run a plain `./build.sh` first if any source changed.
It needs root for `losetup` and `mount`.

Requires `musl-gcc`, `upx`, `gcc`, and `qemu-system-x86_64`. OVMF firmware is
included as `virtual_machine/uefi.bios`.

## Running

```sh
./run
```

Boots the image headless, with the console on serial. There is no window, so to
shut down use `kill -12 1` from the guest shell, or `pkill qemu-system-x86_64`
from another terminal.

The emulated VGA device is kept even though nothing displays it: pboot draws
through the GOP that UEFI publishes for it, and `-vga none` would remove it.

## Boot sequence

```
UEFI firmware
  -> pboot            EFI/BOOT/BOOTX64.EFI on the EFI system partition
     reads pboot.conf, loads vmlinuz with the configured parameters
  -> kernel
  -> /pinit           PID 1
     mounts proc, sys, devtmpfs, devpts, tmpfs and the block devices,
     brings up the network, then starts a getty per console
  -> pgetty           tty1, tty2, ttyS0
  -> plogin
  -> bash
```

pinit answers two signals:

```sh
kill -2  1    # SIGINT,  reboot
kill -12 1    # SIGUSR2, poweroff
```

## pboot.conf

Lives on the EFI system partition next to the kernel. One `n`/`k`/`p` triple per
boot entry:

```
m 0                     show menu: 1 yes, 0 no
e 0                     default entry, by index
n "plinux"              entry name
k "vmlinuz"             kernel filename on the ESP
p "root=/dev/sda2 rw init=/pinit console=tty0 console=ttyS0,115200"
```

Sizes are fixed in `src/pboot/types.h` and are not bounds-checked while parsing:
names and kernel filenames hold 20 characters, parameters hold 100. A longer
parameter line overflows into the next entry.

On real hardware prefer `root=PARTUUID=...` over `/dev/nvme0n1p3`. NVMe
controllers are numbered in the order their probes finish, so with more than one
drive the name is not stable across boots. The kernel resolves `PARTUUID=` by
itself; `UUID=` needs an initramfs to resolve it, and there is none here. Add
`rootwait` so the kernel waits for the device instead of panicking when the
probe is still in flight.

## Disk layout

The VM image is GPT:

| Partition | Size | Type | Contents |
| --- | --- | --- | --- |
| 1 | 100M | EFI System (FAT) | `EFI/BOOT/BOOTX64.EFI`, `vmlinuz`, `pboot.conf` |
| 2 | 922M | ext4 | root filesystem, staged from `obj/` |

`/bin`, `/lib` and `/lib64` are relative symlinks into `/usr`. They dangle when
viewed inside `obj/` and resolve correctly once the tree is `/`, because `..`
at `/` is `/`.

## Installing pboot on real hardware

```sh
mount -t efivarfs none /sys/firmware/efi/efivars
mkdir -p /boot/EFI/pboot
cp src/pboot/pboot /boot/EFI/pboot/pboot.efi
efibootmgr --create --disk /dev/nvme0n1 --part 1 -L "pboot" \
  --loader '\EFI\pboot\pboot.efi'
```

## Licensing

pgetty derives from mingetty and is GPLv2; see `src/pgetty/COPYING`.
`src/bash/build_static.sh` is adapted from robxu9/bash-static (MIT).
Third-party trees under `src/` keep their own licenses.
