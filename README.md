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
| glibc | 2.42 | staged into the image for dynamically linked binaries |

The LFS packages built by `./build.sh packages` are unpacked into `src/` too,
as versioned directories. They are not tracked; `download.sh` fetches the
tarballs and the package scripts unpack them.

## Layout

```
build.sh              build everything into obj/, or stage obj/ into the VM image
configure             clone the kernel and pboot, install sys/kernel_config
download.sh           fetch the LFS tarballs listed in wget-list-sysv
run                   symlink to virtual_machine/start.sh
obj/                  staged root filesystem; becomes / in the image
packages/             one build script per LFS package, plus the build order
src/                  component sources and third-party trees
sources/              downloaded tarballs and patches
sys/                  scripts, dotfiles and /etc content for a running system
sys/kernel_config     the kernel .config, kept outside the cloned kernel tree
docs/                 the LFS book, as PDF and as grepable text
logs/                 per-step build output
virtual_machine/      QEMU image, OVMF firmware, pboot.conf, launcher
```

## Building

```sh
./configure           # clone the component repos kept outside this tree
./download.sh         # fetch the LFS tarballs into sources/
./build.sh help       # all commands
./build.sh            # full build into obj/
./build.sh packages   # build the LFS packages into obj/
./build.sh virt       # copy obj/ into virtual_machine/disk.raw
./build.sh clean all  # clean sources and delete obj/
```

Add `verbose` to any command, or set `VERBOSE=1`, to stream build output as
well as logging it. Without it each step prints one line and the detail goes to
`logs/`.

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
included as `virtual_machine/uefi.bios`. The packages additionally need
`meson`, `ninja`, `perl` and `python3`.

Anything built with `musl-gcc` runs its configure tests on the host, so the
host needs musl's loader present at the path those binaries name:

```sh
ln -s /musl/lib/libc.so /usr/lib/ld-musl-x86_64.so.1
```

Without it configure stops at `cannot run C compiled programs`, which reads
like a broken compiler but is only a missing interpreter.

## Packages

The userland beyond the `p*` components is built from the LFS packages, one
script per package in `packages/`. `packages/order` lists them in dependency
order and `./build.sh packages` walks it from the top.

```sh
./build.sh packages          # build whatever is not installed yet
./build.sh packages force    # rebuild them all
./build.sh packages verbose  # stream the output
```

Each script sources `packages/common.sh`, which unpacks the tarball from
`sources/` into `src/` if it is not already there and sets `CC` and the staging
paths. Everything installs with `DESTDIR=obj`, never into the host. A package
that completes leaves a stamp in `obj/.packages`, so the stamps disappear with
`clean all` and cannot claim a package is present in an empty tree.

Built so far:

| Package | Why it is here |
| --- | --- |
| glibc | udev is part of systemd, which does not build against musl |
| musl | libc for the `p*` components and bash |
| coreutils | ls, cp, mkdir and the rest |
| util-linux | mount, blkid, cfdisk, and libblkid/libmount for udev |
| attr, acl | libacl, which udev uses to set permissions on device nodes |
| libcap | libcap, likewise |
| openssl | libcrypto, likewise |
| kmod | module loading, and libkmod for udev |
| udev | device nodes, `/dev/disk/by-uuid`, interface renaming |
| expat | XML parsing, which dbus reads its configuration with |
| dbus | the message bus; iwd will not start without one |

dbus is the first package here that is not in the LFS book. The book builds no
D-Bus at all — its only mention is the `messagebus` user — so `packages/dbus.sh`
follows upstream rather than `docs/`. Note that dbus 1.16 dropped autotools:
there is no `configure` in the tarball, only meson.

The two C libraries coexist: separate loaders, separate names, and each binary
names the one it was linked against. musl installs its libraries in
`/usr/lib/musl`, because musl's `libc.so` *is* its loader while glibc installs
a linker script under that name — sharing a directory means one destroys the
other.

Still to come, roughly in order: grep, sed, gawk, findutils and diffutils,
which every later `./configure` calls; tar, gzip and xz; zlib and ncurses;
e2fsprogs for the ext4 root; procps-ng and psmisc.

iproute2 is no longer among them. Nothing in the boot path runs `ip`: pinit
configures loopback with `SIOCSIFADDR` directly, and iwd sets the wireless
address over rtnetlink itself. It is still worth having for interactive use,
but the system now comes up without it.

Packages are compiled by the host toolchain and install into `obj/`. Do not
point `LDFLAGS` at `obj/usr/lib` to pick up a library staged by an earlier
package: that puts the image's glibc ahead of the host's, and configure's test
programs then link against a libc that cannot run on the build machine.

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
     mounts proc, sys, devtmpfs, devpts and tmpfs itself, runs mount -a -F
     for the block devices in /etc/fstab, configures loopback, then starts
     a getty per console
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

Shadow is not built yet. The account database is the single root entry in
`sys/etc/passwd`, which is all a one-user system needs.

Also note LFS builds inside a chroot and installs straight into `/usr`. This
project stages into `obj/`, so book recipes need `DESTDIR` or an equivalent
prefix before being run here.

## System configuration

`sys/` holds what a running plinux needs outside of any package. `build.sh`
installs it as part of a normal build:

| Source | Installed to | Contents |
| --- | --- | --- |
| `sys/root/` | `/root/` | `.bash_profile`, `.bashrc`, `shell_config.sh` |
| `sys/scripts/` | `/usr/bin/` | `init_os`, `set_ip`, `pdevices` |
| `sys/etc/` | `/etc/` | `passwd`, `group` |
| `sys/kernel_config` | `src/linux/.config` | installed by `./configure` |

Only root exists on this system, so `/etc/passwd` is a single line and nothing
is chmodded during staging.

These files are also the ones a plinux workstation runs from directly, by
symlink rather than by copy. Editing them changes the running machine as well
as the next image, so a mistake here is felt immediately. They are written to
tolerate that: no bare `mkdir` without checking the binary exists, `HOME`
defaulted, and `init_os` only run on `tty1` with no display already up.

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
docs/LFS-BOOK-12.4.pdf         the book
docs/LFS-BOOK-12.4.txt         extracted text, 17371 lines
docs/LFS-BOOK-12.4-index.txt   section -> line number, 161 entries
```

Look a package up in the index, then read from that line:

```sh
grep -i udev docs/LFS-BOOK-12.4-index.txt   # 9394  8.76. Udev from Systemd-257.8
sed -n '9394,9530p' docs/LFS-BOOK-12.4.txt
```

The `-layout` extraction keeps indentation and trailing backslashes, so the
commands can be copied out directly. Regenerate both files with:

```sh
pdftotext -layout docs/LFS-BOOK-12.4.pdf docs/LFS-BOOK-12.4.txt
```

LFS installs straight into `/usr` because it builds inside a chroot. This
project stages into `obj/` instead, so its recipes need a `DESTDIR` or an
equivalent prefix before they are run here.

## Licensing

pgetty derives from mingetty and is GPLv2; see `src/pgetty/COPYING`.
`src/bash/build_static.sh` is adapted from robxu9/bash-static (MIT).
Third-party trees under `src/` keep their own licenses.
