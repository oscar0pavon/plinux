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
| linux | mainline | cloned by `./configure`, configured from `sys/kernel_config` |
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
sys/kernel_config     the kernel .config, kept outside the cloned kernel tree
virtual_machine/      QEMU image, OVMF firmware, pboot.conf, launcher
```

## Building

```sh
./configure           # clone the component repos kept outside this tree
./build.sh help       # all commands
./build.sh            # full build into obj/
./build.sh virt       # copy obj/ into virtual_machine/disk.raw
./build.sh clean all  # clean sources and delete obj/
```

`./configure` is safe to re-run: repositories already cloned are reported and
skipped, and a directory that exists but is not a clone is left alone rather
than overwritten. `./configure update` pulls into the existing clones. Both
clone and pull are shallow, since the kernel's full history is several
gigabytes and none of it is needed to build.

It then copies `sys/kernel_config` to `src/linux/.config`, leaving an existing
`.config` alone so work done with `menuconfig` is not thrown away. The kernel
is an external clone, so its configuration cannot live inside it — a re-clone
or a shallow pull would take it along. `build.sh` runs `make olddefconfig`
before building, which takes the default for any symbol the current kernel has
added since the config was saved instead of prompting.

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

## Where this project departs from LFS

plinux supplies its own bootloader, init, getty and login, so the corresponding
book sections do not apply and their packages are not in `wget-list-sysv`:

| Book section | LFS package | Replaced by |
| --- | --- | --- |
| 8.64. GRUB-2.12 | grub | [pboot](src/pboot) |
| 10.4. Using GRUB to Set Up the Boot Process | grub | pboot, configured by `pboot.conf` |
| 8.82. SysVinit-3.14 | sysvinit | [pinit](src/pinit) |
| 9.2. LFS-Bootscripts-20250827 | lfs-bootscripts | pinit, which mounts and configures directly |

Two packages stay because only one program in each is superseded:

| Book section | Kept for | Superseded program |
| --- | --- | --- |
| 8.79. Util-linux-2.41.1 | blkid, mount, cfdisk, blockdev and the rest | `agetty`, replaced by [pgetty](src/pgetty) |
| 8.28. Shadow-4.18.0 | passwd, su, the account database | `login`, replaced by [plogin](src/plogin) |

Also note LFS builds inside a chroot and installs straight into `/usr`. This
project stages into `obj/`, so book recipes need `DESTDIR` or an equivalent
prefix before being run here.

## Downloading LFS sources

`wget-list-sysv` holds the package and patch URLs for LFS 12.4, less the four
entries listed above, so 91 of the book's 95.

```sh
./download.sh            # fetch everything missing into sources/
./download.sh retry      # only the entries that failed last time
./download.sh verify     # md5sum -c, if md5sums is present
./download.sh help
```

Each file is fetched separately so a bad mirror is named rather than lost in
the noise. Complete files are skipped, partial ones resumed, and failures are
recorded in `sources/.failed` for `retry`. The exit status is 0 only when every
file was obtained, so it can gate a build script.

`md5sums` is not in this repository. Fetch it from the same release of the book
as `wget-list-sysv` and put it beside the script to enable `verify`.

The list includes `systemd-257.8.tar.gz`, `systemd-man-pages-257.8.tar.xz` and
`udev-lfs-20230818.tar.xz`, which are what the book's udev section needs.

## Reference

The Linux From Scratch book is kept here for build procedures, as the original
PDF and as text extracted with `pdftotext -layout` so it can be grepped:

```
LFS-BOOK-12.4.pdf         the book
LFS-BOOK-12.4.txt         extracted text, 17371 lines
LFS-BOOK-12.4-index.txt   section -> line number, 161 entries
```

Look a package up in the index, then read from that line:

```sh
grep -i udev LFS-BOOK-12.4-index.txt     # 9394  8.76. Udev from Systemd-257.8
sed -n '9394,9530p' LFS-BOOK-12.4.txt
```

The `-layout` extraction keeps indentation and trailing backslashes, so the
commands can be copied out directly. Regenerate both files with:

```sh
pdftotext -layout LFS-BOOK-12.4.pdf LFS-BOOK-12.4.txt
```

LFS installs straight into `/usr` because it builds inside a chroot. This
project stages into `obj/` instead, so its recipes need a `DESTDIR` or an
equivalent prefix before they are run here.

## Licensing

pgetty derives from mingetty and is GPLv2; see `src/pgetty/COPYING`.
`src/bash/build_static.sh` is adapted from robxu9/bash-static (MIT).
Third-party trees under `src/` keep their own licenses.
