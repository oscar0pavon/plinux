# plinux

A complete Linux distribution built from source, with its own bootloader, init,
getty and login written in C. No GRUB, no systemd, no busybox.

## What it is

plinux is a single-user workstation system, built the way Linux From Scratch
builds one — every package compiled from its own tarball, nothing installed by
a package manager — but with the parts that usually come from a distribution
replaced by programs written for it. UEFI hands control to `pboot`, `pboot`
loads the kernel, the kernel runs `pinit` as PID 1, `pinit` starts `pgetty` on
each console, and `pgetty` runs `plogin`, which execs the shell. None of that
chain is GRUB, systemd, agetty or shadow's `login`. Four C programs, about two
thousand lines between them, and each one is small enough to read in an
afternoon.

The system it produces is deliberately small: one user, who is root; two C
libraries, because `udev` will not build against musl and everything else
prefers it; and thirty-seven packages. Thirty-three of them make a console
system that can partition a disk, repair its own filesystems, join a wireless
network and edit its own configuration; the other four are the first tier of
the Wayland stack. There is no service manager, no package manager,
and no toolchain in the image — packages are compiled on the host and staged
into `obj/`, which becomes the root filesystem.

It is also self-hosting in the sense that matters day to day: the machine this
is developed on runs plinux, and `sys/` is not a template for the image but the
running system's actual configuration, reached by symlink. Changing a file
there changes the workstation and the next image at the same time.

The three ways to run it: `./run` boots the image under QEMU, `build.sh usb`
writes it to a USB stick as a bootable rescue system that carries its own
identifiers, and `build.sh` plus the `pboot` install steps put it on real
hardware. The Wayland stack — wlroots and sway — is the work in progress; the
system is a console system until it lands.

## Getting it

```sh
git clone https://github.com/oscar0pavon/plinux
cd plinux
./configure              # clone src/linux and src/pboot, install the kernel config
./download.sh all        # fetch every source into sources/
./build.sh packages      # the 37 packages in packages/order, into obj/
./build.sh               # pboot, kernel, pinit, pgetty, plogin
./build.sh check         # find binaries whose libraries the image lacks
sudo ./build.sh virt     # write virtual_machine/disk.raw
./run                    # boot it
```

That is the whole build. It takes about 45 minutes on 32 threads, most of it
in the packages, and needs roughly 4G for `src/` and `sources/` on top of the
450M image. The steps are explained under [Building from
scratch](#building-from-scratch) below.

`./configure` clones two repositories that are developed outside this tree —
the kernel from mainline and `pboot` from its own repository — because a
shallow clone of the kernel is several hundred megabytes and does not belong
in this history. Everything else with a `p` prefix lives here.

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
| musl | 1.2.5 | libc for every `p*` component and bash |
| glibc | 2.42 | staged into the image for dynamically linked binaries |

The packages built by `./build.sh packages` are unpacked into `src/` too, as
versioned directories. They are not tracked; `download.sh` fetches the tarballs
and the package scripts unpack them.

## Layout

```
build.sh              build everything into obj/, or write obj/ to a disk
configure             clone the kernel and pboot, install sys/kernel_config
download.sh           fetch source tarballs into sources/
wget-list-core        the sources the console system is built from
wget-list-gui         the Wayland stack, fetched separately
wget-list-sysv        the LFS book's own list, kept for reference
run                   symlink to virtual_machine/start.sh
obj/                  staged root filesystem; becomes / in the image
packages/             one build script per package, plus the build order
src/                  component sources and third-party trees
sources/              downloaded tarballs and patches
sys/                  scripts, dotfiles and /etc content for a running system
sys/kernel_config     the kernel .config, kept outside the cloned kernel tree
docs/                 the LFS book, as PDF and as grepable text
logs/                 per-step build output
virtual_machine/      QEMU image, OVMF firmware, pboot.conf, launcher
```

## Building from scratch

The seven commands are under [Getting it](#getting-it). What each one is for,
and why they run in that order:

**`./configure`** clones `src/linux` and `src/pboot` and copies
`sys/kernel_config` to `src/linux/.config`. It has to come first — not because
`download.sh` needs it, but because every `build.sh` invocation installs the
kernel's userspace API headers out of `src/linux` into `obj/usr/include`, and
no package will compile without them.

**`./download.sh all`** fetches both lists: the thirty-five tarballs and
patches of `wget-list-core`, and the four of `wget-list-gui`. Plain
`./download.sh` takes only the core, which is enough for a console system but
not for `packages/order` as it now stands — that ends with the Wayland tier.
See [Downloading sources](#downloading-sources).

**`./build.sh packages`** walks `packages/order` from the top, running one
script per package, each installing with `DESTDIR=obj`. A package that
completes leaves a stamp in `obj/.packages`, so an interrupted run resumes
rather than starting over. This is the long step, about 40 minutes on 32
threads.

**`./build.sh`** builds this project's own components — pboot, the kernel,
pinit, pgetty and plogin — and stages `sys/` on top. It is a separate
step from `packages` on purpose: the components change often and rebuild in
minutes, the packages almost never change.

**`./build.sh check`** reads the `NEEDED` entries of every binary in `obj/`
and reports any whose libraries are not in the image. Run it after both build
steps; it has nothing useful to say until then. One binary is expected to fail
it, see [Packages](#packages).

**`sudo ./build.sh virt`** copies `obj/` and the bootloader into
`virtual_machine/disk.raw` over a loop device, which is what needs root. It
builds nothing, so run a plain `./build.sh` first if any source changed.

**`./run`** starts QEMU against that image.

Afterwards, the loop while working on it is usually just:

```sh
./build.sh && sudo ./build.sh virt && ./run
```

### What the host needs

Packages are compiled by the host toolchain; nothing is cross-compiled and
there is no chroot. Required:

| Tool | For |
| --- | --- |
| `gcc`, `g++` | everything |
| `musl-gcc` | the `p*` components, bash, and the standalone musl packages |
| `make`, `perl`, `python3` | package build systems |
| `meson`, `ninja` | dbus and, later, the whole Wayland stack |
| `pkgconf` | finding staged libraries |
| `git`, `wget` | `./configure` and `./download.sh` |
| `upx` | compressing pboot |
| `qemu-system-x86_64` | `./run` |
| `sfdisk`, `mkfs.ext4`, `mkfs.fat` | `build.sh virt` and `build.sh usb` |

Anything built with `musl-gcc` runs its configure tests on the host, so the
host needs musl's loader present at the path those binaries name:

```sh
ln -s /musl/lib/libc.so /usr/lib/ld-musl-x86_64.so.1
```

Without it configure stops at `cannot run C compiled programs`, which reads
like a broken compiler but is only a missing interpreter.

### build.sh

```sh
./build.sh help          # all commands
./build.sh               # this project's own components
./build.sh packages      # the packages in packages/order
./build.sh virt          # copy obj/ into virtual_machine/disk.raw
./build.sh usb /dev/sdX  # write obj/ to a USB disk as a bootable rescue system
./build.sh check         # find binaries whose libraries are missing
./build.sh clean all     # clean sources and delete obj/
```

Build output is streamed as well as written to `logs/`. Add `quiet` to any
command, or set `VERBOSE=0`, to only log it and print one line per step.

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

## Downloading sources

Three lists, split by what actually gets built:

| List | Contents |
| --- | --- |
| `wget-list-core` | the console system, one line per entry in `packages/order` |
| `wget-list-gui` | the Wayland stack, on top of the core |
| `wget-list-sysv` | the LFS 12.4 book's own list, not downloaded by default |

```sh
./download.sh                          # wget-list-core
./download.sh gui                      # wget-list-gui
./download.sh all                      # both
./download.sh --list wget-list-sysv    # the book's list
./download.sh retry                    # only the entries that failed last time
./download.sh verify                   # md5sum -c, if md5sums is present
./download.sh help
```

`wget-list-sysv` is not what gets fetched, and that is deliberate. Ninety-one
of its entries are the book's, and about sixty of those are the chapter 5 and 6
temporary toolchain — gcc, binutils, gmp, mpfr, mpc, m4, make, perl, python,
tcl, expect, autoconf, libtool, texinfo — which LFS builds so that chapter 8
can be built inside a chroot. plinux does none of that. It compiles against the
host toolchain and stages into `obj/`, so those tarballs are several hundred
megabytes that nothing ever unpacks. The file stays in the tree as the starting
point if the self-hosting toolchain is ever built.

Each file is fetched separately so a bad mirror is named rather than lost in
the noise. Complete files are skipped, partial ones resumed, and failures are
recorded in `sources/.failed` for `retry`. The exit status is 0 only when every
file was obtained, so it can gate a build script.

A list line is a URL, optionally followed by a name to save it as. Forge
archive URLs end in the tag rather than the project, so seatd would otherwise
arrive in `sources/` as `0.9.1.tar.gz`.

`md5sums` is not in this repository. Fetch it from the same release of the book
as `wget-list-sysv` and put it beside the script to enable `verify`. It lists
only the book's tarballs, so `wget-list-gui` goes unverified; several of those
are generated archive URLs with no stable checksum to record anyway.

One thing has no recorded origin: `src/musl` was unpacked by hand and is in no
list, unlike `src/linux` and `src/pboot`, which `./configure` clones.

## Packages

The userland beyond the `p*` components is built from source, one script per
package in `packages/`. `packages/order` lists them in dependency order and
`./build.sh packages` walks it from the top.

```sh
./build.sh packages          # build whatever is not installed yet
./build.sh packages <name>   # rebuild just that one, installed or not
./build.sh packages force    # rebuild them all
./build.sh packages quiet    # log the output instead of streaming it
./build.sh check             # find binaries whose libraries are missing
```

Run `check` after building. A package compiled against a host library that
was never staged installs perfectly and then fails the moment the program is
run, which is invisible until someone tries it: that is how `kmod` shipped
unable to start, taking `modprobe` and `depmod` with it, and how `dmesg` and
`lsblk` were broken for thirteen packages. `check` reads the `NEEDED` entries
of every binary in `obj/` and reports the ones the image cannot satisfy.

`memusagestat` is expected to fail it. That is a glibc profiling helper
wanting libgd and libpng, and neither is worth a package here.

Each script sources `packages/common.sh`, which unpacks the tarball from
`sources/` into `src/` if it is not already there and sets `CC` and the staging
paths. Everything installs with `DESTDIR=obj`, never into the host. A package
that completes leaves a stamp in `obj/.packages`, so the stamps disappear with
`clean all` and cannot claim a package is present in an empty tree.

Built so far, 37 packages:

| Package | Why it is here |
| --- | --- |
| glibc | udev is part of systemd, which does not build against musl |
| musl | libc for the `p*` components and bash |
| bash | the shell, static against musl so the login path does not depend on the loader |
| coreutils | ls, cp, mkdir and the rest |
| sed, grep, gawk, findutils, diffutils | the text tools every shell script reaches for |
| gzip, tar | without these the image cannot unpack anything, including its own sources |
| zlib, xz, zstd | kmod names all three, so without them modprobe cannot start |
| util-linux | mount, blkid, cfdisk, and libblkid/libmount for udev |
| attr, acl | libacl, which udev uses to set permissions on device nodes |
| libcap | libcap, likewise |
| openssl | libcrypto, likewise |
| kmod | module loading, and libkmod for udev |
| udev | device nodes, `/dev/disk/by-uuid`, interface renaming |
| ncurses, readline, libxcrypt | named by util-linux; without them dmesg, lsblk, fdisk and sulogin cannot start |
| vim, less | the editor and the pager |
| tzdata | the timezone database; `/etc/localtime` is America/Asuncion |
| e2fsprogs | the root filesystem is ext4 and nothing could repair it: util-linux supplies `fsck`, but that is only a dispatcher |
| dosfstools | the same for the EFI system partition, and `build.sh usb` needs `mkfs.fat` |
| procps-ng | ps, top, free, pgrep |
| expat | XML parsing, which dbus reads its configuration with |
| dbus | the message bus; iwd will not start without one |
| iwd | wireless; `init_os` starts it through `set_ip` |
| libffi | wayland dispatches protocol calls through it |
| wayland | the protocol libraries, and wayland-scanner, which is a build tool |
| wayland-protocols | XML only; xdg-shell is how a client gets a window |
| seatd | hands out the DRM and input devices, so sway need not be root |

dbus is the first package here that is not in the LFS book. The book builds no
D-Bus at all — its only mention is the `messagebus` user — so `packages/dbus.sh`
follows upstream rather than `docs/`. Note that dbus 1.16 dropped autotools:
there is no `configure` in the tarball, only meson.

The two C libraries coexist: separate loaders, separate names, and each binary
names the one it was linked against. musl installs its libraries in
`/usr/lib/musl`, because musl's `libc.so` *is* its loader while glibc installs
a linker script under that name — sharing a directory means one destroys the
other.

Still to come is the rest of the Wayland stack: libdrm, pixman, libxkbcommon with
xkeyboard-config, libevdev, hwdata and libdisplay-info; then libinput; then
llvm and mesa; then the text stack, freetype through pango; then json-c,
wlroots and sway. Everything in it is built against glibc, not musl: mesa and
LLVM are not realistically musl-buildable here, and a stack cannot be split
between two C libraries.

Also worth having, none of them on the critical path: psmisc, iproute2,
iana-etc, kbd, and man-db with groff — nothing in the image can read a man page.

### Building against the image, not the build machine

This is the one thing about the build that is easy to get wrong, because
getting it wrong looks like success.

These builds run on a workstation that is itself running plinux. A package
that finds a library or a header in the host's `/usr` therefore links against
very nearly the right thing, and the build succeeds. The result only fails
somewhere else — in the VM, or off the rescue USB — and nothing in between
catches it. `packages/common.sh` closes that off:

```sh
PKG_CONFIG_LIBDIR=obj/usr/lib/pkgconfig     # replaces the default search path
PKG_CONFIG_SYSROOT_DIR=obj                  # rewrites the -I and -L it prints
CFLAGS/CXXFLAGS/LDFLAGS  --sysroot=obj      # everything not using pkg-config
```

`PKG_CONFIG_LIBDIR` rather than `PKG_CONFIG_PATH`, because `PATH` is searched
*before* the default directories while `LIBDIR` replaces them: a dependency
that was never staged is now a configure-time error instead of a silent host
link. The sysroot covers what pkg-config never sees — `AC_CHECK_HEADER`,
`AC_CHECK_LIB`, meson's `cc.find_library`, cmake's `find_package`. That is the
check vim needed and did not have: its configure found the host's GTK3,
believed it was building a GUI, and produced a binary naming 226 libraries the
image did not have. Under a sysroot that test fails on its own.

`PLINUX_SYSROOT=none` turns the sysroot off, for bisecting a package that will
not build. There is no equivalent escape for pkg-config; edit `common.sh`.

This depends on `obj/bin`, `obj/lib`, `obj/lib64` and `obj/sbin` being
*relative* symlinks — `usr/lib`, not `../../../usr/lib`. Both spell `/usr/lib`
once the tree is the root filesystem, but only the relative form also resolves
correctly when the tree is read from the build machine. The `../../..` form
escapes `obj/` entirely and lands on the host's own `/usr`, which is why `ls
obj/bin` once reported `tar` and `ps` as installed when neither was.

The kernel's userspace API headers are part of the sysroot and are installed
into `obj/usr/include` by `build.sh`, refreshed whenever the kernel is
rebuilt. Before that they were never staged at all, and every package compiled
against the host's copy.

## Running

```sh
./run              # GTK window, console on the emulated display
./run headless     # no window, console on serial
./run help
```

The machine is deliberately close to the workstation: q35, `-cpu host`, 8 cpus,
8G, the disk on an NVMe controller, xHCI, and virtio for the display, keyboard
and network. So the guest sees `/dev/nvme0n1`, which is why `pboot.conf` and the
image's `/etc/fstab` name it that way rather than `sda`.

`MEMORY`, `CPUS` and `VGA` override the defaults. `USB_DISK=/dev/sdb ./run`
passes a host disk through to the guest; it is opt-in because the guest can
write to it and `/dev/sdb` is whatever was plugged in last.

To shut down, `kill -12 1` from the guest shell, or close the window.

The emulated display adapter is kept even in headless mode: pboot draws through
the GOP that UEFI publishes for it, and `-vga none` would remove it.

Two guest drivers this depends on, both easy to lose when the kernel config is
refreshed from the workstation: `CONFIG_DRM_VIRTIO_GPU` for the display, and
`CONFIG_VIRTIO_NET` for the network — the workstation has no e1000 card, so
`CONFIG_E1000` is not set and an emulated e1000 would go unclaimed.

## Rescue USB

```sh
sudo ./build.sh usb /dev/sdX
```

Writes `obj/` to a USB disk as a self-contained bootable system. The device has
to be named in full; there is no default, and the command refuses anything that
is not a whole disk, is the disk the host booted from, or has a filesystem
mounted. It then asks for `ERASE` to be typed, which `USB_YES=1` skips.

The layout is the same as the VM image: GPT, a 256M FAT32 EFI system partition
and the rest ext4.

The part worth knowing is what happens after the filesystems are made. A stick
cannot use the `pboot.conf` and `/etc/fstab` that the VM image uses, because
those name `/dev/nvme0n1p2` and the VM's UUIDs; booted on another machine they
would send the kernel looking for that machine's disk. So `usb` reads the
identifiers back off the device it just partitioned and generates both files
against them: `root=PARTUUID=` for the kernel, which resolves it natively from
the GPT with no initramfs, and `UUID=` in `/etc/fstab`, which `mount` resolves
through libblkid. The stick boots itself, wherever it is plugged in.

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

`src/pinit/reboot` and `src/pinit/poweroff` are one-line wrappers around those.
`make install` in `src/pinit` puts them in `/usr/sbin` on the workstation;
`build.sh` does not yet stage them into `obj/`, so the image still needs the
`kill` form.

On shutdown pinit sends every remaining process `SIGTERM`, waits five seconds,
sends `SIGKILL`, then `swapoff -a`, `umount -a` and a read-only remount of `/`
before asking the kernel to reboot or power off. Without that last part the
root filesystem replayed its journal on every boot.

## pboot.conf

Lives on the EFI system partition next to the kernel. One `n`/`k`/`p` triple per
boot entry:

```
m 0                     show menu: 1 yes, 0 no
e 0                     default entry, by index
n "plinux"              entry name
k "vmlinuz"             kernel filename on the ESP
p "root=/dev/nvme0n1p2 rw init=/pinit rootwait console=tty0 console=ttyS0,115200"
```

Sizes are fixed in `src/pboot/types.h` and are not bounds-checked while parsing:
names and kernel filenames hold 20 characters, parameters hold 100. A longer
parameter line overflows into the next entry.

On real hardware prefer `root=PARTUUID=...` over `/dev/nvme0n1p3`, which is what
`build.sh usb` generates. NVMe controllers are numbered in the order their
probes finish, so with more than one drive the name is not stable across boots.
The kernel resolves `PARTUUID=` by itself; `UUID=` needs an initramfs to
resolve it, and there is none here. Add `rootwait` so the kernel waits for the
device instead of panicking when the probe is still in flight.

## Disk layout

The VM image is GPT:

| Partition | Size | Type | Contents |
| --- | --- | --- | --- |
| 1 | 100M | EFI System (FAT) | `EFI/BOOT/BOOTX64.EFI`, `vmlinuz`, `pboot.conf` |
| 2 | 922M | ext4 | root filesystem, staged from `obj/` |

The guest reaches them as `/dev/nvme0n1p1` and `/dev/nvme0n1p2`, since `run`
attaches the image through an NVMe controller. The build side is unaffected:
`build.sh virt` writes the image over a loop device either way.

`/bin`, `/lib`, `/lib64`, `/sbin` and `/var/run` are relative symlinks, and
they resolve both inside `obj/` and once the tree is `/`. That is the point of
them being relative; see the sysroot section above.

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
book sections do not apply and their packages are in no list here:

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

Shadow is not built. The account database is the single root entry in
`sys/etc/passwd`, which is all a one-user system needs.

The larger departure is that LFS builds inside a chroot, on a toolchain it
builds first, and installs straight into `/usr`. plinux builds on the host
toolchain and stages into `obj/`, so book recipes need `DESTDIR` or an
equivalent prefix before being run here — and so the isolation a chroot gives
for free has to be arranged explicitly, which is what the sysroot section
above is about.

## System configuration

`sys/` holds what a running plinux needs outside of any package. `build.sh`
installs it as part of a normal build:

| Source | Installed to | Contents |
| --- | --- | --- |
| `sys/root/` | `/root/` | `.bash_profile`, `.bashrc`, `shell_config.sh` |
| `sys/scripts/` | `/usr/bin/` | `init_os`, `set_ip`, `pdevices` |
| `sys/etc/` | `/etc/` | staged whole: `passwd`, `group`, `fstab`, `iwd/main.conf` |
| `sys/kernel_config` | `src/linux/.config` | installed by `./configure` |

`sys/etc/` is copied wholesale rather than file by file, so a package that
needs a configuration file only has to have it added there — before that, each
new file also needed a line in `build.sh`, and one of them was missed for as
long as iwd had been in the image.

Only root exists on this system, so `/etc/passwd` is a single line and nothing
is chmodded during staging.

These files are also the ones a plinux workstation runs from directly, by
symlink rather than by copy. Editing them changes the running machine as well
as the next image, so a mistake here is felt immediately. They are written to
tolerate that: no bare `mkdir` without checking the binary exists, `HOME`
defaulted, and `init_os` only run on `tty1` with no display already up.
`pdevices` and `init_os` also skip anything already running, since `init_os`
runs again every time the login shell on tty1 comes back.

Nothing on this system calls `syslog(3)` and there is no syslog daemon, so the
two daemons that can fail quietly write to files instead:
`/var/log/udevd.log` and `/var/log/iwd.log`, one generation each.

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

## Licensing

pgetty derives from mingetty and is GPLv2; see `src/pgetty/COPYING`.
`packages/bash.sh` is adapted from robxu9/bash-static (MIT).
Third-party trees under `src/` keep their own licenses.
