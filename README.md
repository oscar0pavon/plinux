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
prefers it; and a hundred and one packages. A third make a console system
that can partition a disk, repair its own filesystems, join a wireless network
and edit its own configuration; another third are the Wayland stack, which
reaches sway, with foot and wmenu to run inside it; the rest are the toolchain
and the build tools, which are there because the system builds itself.

There is no service manager and no package manager. There is a compiler:
the image carries gcc, binutils, cmake, meson and ninja, so it can rebuild
itself rather than being something only this workstation can produce. That is
most of the reason the finished tree is 1.5G.

It is also self-hosting in the sense that matters day to day: the machine this
is developed on runs plinux, and `sys/` is not a template for the image but the
running system's actual configuration, reached by symlink. Changing a file
there changes the workstation and the next image at the same time.

The three ways to run it: `./run` boots the image under QEMU, `build.sh usb`
writes it to a USB stick as a bootable rescue system that carries its own
identifiers, and `build.sh` plus the `pboot` install steps put it on real
hardware.

The chroot-built image boots: pboot loads the kernel, `pinit` comes up as PID
1, `plogin` reaches a shell, and pdaemon starts udevd, seatd, dbus and iwd,
with sway opening as a client on seat0. That has been verified on the serial
console; sway has not yet been looked at on a display.

## Getting it

```sh
git clone https://github.com/oscar0pavon/plinux
cd plinux
./configure                              # clone src/linux and src/pboot
./download.sh all                        # every source into sources/
./download.sh --list wget-list-toolchain # the chapter 5-7 toolchain as well

./build.sh toolchain                     # LFS 5 and 6: cross compiler, temp tools
./build.sh chroot build                  # LFS 7: enter the chroot, build its tools
./build.sh chroot packages               # LFS 8: the 101 packages, inside it
./build.sh chroot cleanup                # LFS 7.13 and 8.85: /tools and the rest
./build.sh chroot strip                  # LFS 8.84

./build.sh                               # pboot, kernel, p* components, sys/
sudo ./build.sh virt                     # write virtual_machine/disk.raw
./run                                    # boot it
```

That is the whole build. About 35 minutes on 32 threads, and 14G of disk while
it runs — most of which `chroot cleanup` gives back, leaving a 1.5G tree. The
image is 4G because the result carries its own compiler.

It follows the LFS book: a cross toolchain built on the host, a temporary
system cross-compiled with it, a chroot, and then everything else built inside
that chroot where the build machine cannot be reached at all. The steps are
explained under [Building from scratch](#building-from-scratch).

plinux built into `obj/` once, with packages compiled by the host toolchain
and staged, and `--sysroot`, `-L` and `-rpath-link` arranging by hand the
isolation a chroot gives for free. That is gone. It half worked, and the way
it failed was silent — a package that found a host library built cleanly and
only failed in the VM.

`./configure` clones two repositories that are developed outside this tree —
the kernel from mainline and `pboot` from its own repository — because a
shallow clone of the kernel is several hundred megabytes and does not belong
in this history. Everything else with a `p` prefix lives here.

## Components

Everything with a `p` prefix is written for this project:

| Component | What it is |
| --- | --- |
| [pboot](src/pboot) | UEFI bootloader. Reads `pboot.conf`, loads a kernel with parameters, optional menu |
| [pinit](src/pinit) | PID 1. Mounts the filesystems, brings up the network, starts pdaemon and the gettys |
| [pdaemon](src/pdaemon) | Supervises udevd, seatd, dbus-daemon and iwd: starts them, logs them, restarts them |
| [pgetty](src/pgetty) | Console getty, derived from mingetty |
| [plogin](src/plogin) | Sets up the root environment and execs the shell |


## Layout

```
build.sh              build into lfs/, or write lfs/ to a disk
configure             clone the kernel and pboot, install sys/kernel_config
download.sh           fetch source tarballs into sources/
wget-list-core        the sources the console system is built from
wget-list-gui         the Wayland stack, fetched separately
wget-list-toolchain   the chapter 5-7 toolchain, which the image never keeps
wget-list-sysv        the LFS book's own list, kept for reference
run                   symlink to virtual_machine/start.sh
lfs/                  staged root filesystem; $LFS in the book's terms, and / in the image
toolchain/            LFS chapters 5-7: the cross toolchain and the chroot steps
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

The sequence is under [Getting it](#getting-it). What each command is for, and
why they run in that order. This is LFS 12.4 as the book writes it, with
plinux's package set in place of the book's chapter 8.

**`./configure`** clones `src/linux` and `src/pboot` and copies
`sys/kernel_config` to `src/linux/.config`. It comes first because the kernel
tree has to exist before anything is built from it.

**`./download.sh all`** fetches `wget-list-core` and `wget-list-gui`;
`./download.sh --list wget-list-toolchain` adds what chapters 5 to 7 need and
the image never keeps. See [Downloading sources](#downloading-sources).

**`./build.sh toolchain`** walks `toolchain/order`: chapters 5 and 6. Binutils
and GCC pass 1, the kernel API headers, glibc, libstdc++, then seventeen tools
cross-compiled by that toolchain into `lfs/usr`. Every step runs under
`env -i`, so nothing this workstation exports reaches it, and stamps in
`lfs/.toolchain` make it resumable. About eleven minutes; GCC is most of it.

The glibc step ends with the book's sanity checks run as tests rather than
printed to compare by eye — the interpreter path, the three start files, the
include path, the linker's search directories, which `libc.so.6` was opened
and which loader was found. If any of the seven fail the walk stops before
chapter 6, because a toolchain aimed at the wrong tree produces a system that
fails much later and for no visible reason.

**`./build.sh chroot build`** mounts the virtual kernel filesystems into
`lfs/`, chroots, and walks `toolchain/chroot/order`: the full directory tree
and `/etc/passwd`, then gettext, bison, perl, python, texinfo and util-linux.

**`./build.sh chroot packages`** runs `packages/order` inside that chroot.
The same scripts, against a `/` that is `lfs/` — `packages/common.sh`
sees `PLINUX_IN_CHROOT` and empties `build_directory`, so `DESTDIR` goes empty
and the sysroot machinery switches off, because there is no second tree left
for a search to escape into. Stamps go in `lfs/.packages`.

**`./build.sh chroot cleanup`** is LFS 7.13.1 and 8.85: `/tools`, the chapter
6 toolchain still installed under its target triplet, the libtool `.la` files,
the `tester` account, and the unpacked source trees. 14G to 1.5G.

**`./build.sh chroot strip`** is 8.84. Every binary goes through a copy and
comes back by rename, so no mapped file is ever written — the book's warning
about stripping a library out from under a running process is real.

**`./build.sh`** with no arguments builds the half a chroot cannot: pboot, the
kernel, pinit, pdaemon, pgetty, plogin, the firmware and `sys/`. These are
host-built, which
is defensible where packages would not be — the `p*` binaries link musl
statically and the kernel and pboot link no libc at all, so nothing there
loads a library at runtime.

**`sudo ./build.sh virt`** writes `lfs/` and the bootloader into
`virtual_machine/disk.raw` over a loop device, which is what needs root.
`IMAGE` selects a different one in both `build.sh virt` and `./run`, which is
useful for keeping a known-good image while a new one is unproven.

Useful on their own:

```sh
./build.sh chroot                    # interactive shell inside lfs/
./build.sh chroot packages <name>    # rebuild one package in there
./build.sh chroot umount             # take the mounts down by hand
./build.sh toolchain force           # rebuild chapters 5 and 6
```

The mounts come down on every exit path, including a failed build or a Ctrl-C
out of the interactive shell, and `clean` refuses to run while any of them is
up.

### What the host needs

The host builds the chapter 5 cross compiler, the kernel and the `p*`
components. Everything else is built inside the chroot by tools the chroot
contains, so this list is shorter than it was — `meson`, `ninja` and `pkgconf`
used to be on it, and are now packages in the image rather than requirements
of the machine.

| Tool | For |
| --- | --- |
| `gcc`, `g++` | the chapter 5 toolchain, and the kernel |
| `musl-gcc` | the `p*` components and their static musl link |
| `make`, `perl`, `python3` | the chapter 5 and 6 build systems |
| `m4`, `bison`, `flex`, `texinfo` | likewise; LFS lists them as host requirements |
| `git`, `wget` | `./configure` and `./download.sh` |
| `upx` | compressing pboot |
| `qemu-system-x86_64` | `./run` |
| `sfdisk`, `mkfs.ext4`, `mkfs.fat` | `build.sh virt` and `build.sh usb` |

`docs/` carries the book's own `version-check.sh` in section 2.2; running it
is the quickest way to find a missing one.

Anything built with `musl-gcc` runs its configure tests on the host, so the
host needs musl's loader present at the path those binaries name:

```sh
ln -s /musl/lib/libc.so /usr/lib/ld-musl-x86_64.so.1
```

Without it configure stops at `cannot run C compiled programs`, which reads
like a broken compiler but is only a missing interpreter.

### build.sh

```sh
./build.sh help            # all commands
./build.sh                 # pboot, kernel, p* components and sys/, into lfs/
./build.sh toolchain       # LFS chapters 5 and 6
./build.sh chroot          # interactive shell in lfs/
./build.sh chroot build    # LFS chapter 7
./build.sh chroot packages # LFS chapter 8: packages/order, inside the chroot
./build.sh chroot cleanup  # LFS 7.13 and 8.85
./build.sh chroot strip    # LFS 8.84
./build.sh chroot umount   # take the chroot mounts down
./build.sh check           # find binaries whose libraries are missing
./build.sh virt            # copy lfs/ into a raw disk image
./build.sh usb /dev/sdX    # write it to a USB disk as a bootable rescue system
./build.sh clean all       # clean sources and delete lfs/, after asking
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

Four lists, split by what actually gets built:

| List | Contents |
| --- | --- |
| `wget-list-core` | the console system and the toolchain, one line per entry in `packages/order` |
| `wget-list-gui` | the Wayland stack, on top of the core |
| `wget-list-toolchain` | what LFS chapters 5 to 7 build and the image never keeps |
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
can be built inside a chroot.

That is no longer something plinux skips. `wget-list-toolchain` fetches what
chapters 5 to 7 need — binutils, gcc, gmp, mpfr, mpc, m4, make, patch, file,
ncurses, gettext, bison, perl, python, texinfo — and `./build.sh toolchain`
builds them. `wget-list-sysv` remains unfetched because it is the book's whole
list, including packages plinux replaces outright, and because several of its
entries exist only to run test suites that are not run here.

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

Two things are not tarballs and so are in no list: `src/linux` and `src/pboot`,
which `./configure` clones. musl used to be a third — a tree unpacked by hand
with nothing recording where it came from — and is an ordinary entry in
`wget-list-core` now.

## Packages

The userland beyond the `p*` components is built from source, one script per
package in `packages/`. `packages/order` lists them in dependency order and
`./build.sh chroot packages` walks it from the top, inside the chroot.

```sh
./build.sh chroot packages          # build whatever is not installed yet
./build.sh chroot packages <name>   # rebuild just that one, installed or not
./build.sh chroot packages force    # rebuild them all
./build.sh chroot packages quiet    # log the output instead of streaming it
./build.sh check                    # find binaries whose libraries are missing
```

The scripts are not chroot-specific. `packages/common.sh` sees
`PLINUX_IN_CHROOT` and empties `build_directory`, so every path derived from
it — `${build_directory}/usr/lib/pkgconfig`, the `-L` on `CC`, the `DESTDIR`
each script installs with — collapses to the real one. `DESTDIR=` installs to
`/`, which inside the chroot is `lfs/`.

Run `check` after building. A package compiled against a host library that
was never staged installs perfectly and then fails the moment the program is
run, which is invisible until someone tries it: that is how `kmod` shipped
unable to start, taking `modprobe` and `depmod` with it, and how `dmesg` and
`lsblk` were broken for thirteen packages. `check` reads the `NEEDED` entries
of every binary in `lfs/` and reports the ones the image cannot satisfy.

It matters less than it did. That failure mode was a property of compiling
against the build machine, and inside the chroot there is no build machine to
compile against — `check` is now a check on the result rather than a defence
against the method.

`memusagestat` is expected to fail it. That is a glibc profiling helper
wanting libgd, which is not worth a package here. It wanted libpng too until
cairo needed one.

Each script sources `packages/common.sh`, which unpacks the tarball from
`sources/` and sets `CC` and the install paths. Inside the chroot `DESTDIR` is
empty and `make install` installs into `/`, which is `lfs/`. A package
that completes leaves a stamp in `lfs/.packages`, so the stamps disappear with
`clean all` and cannot claim a package is present in an empty tree.

Staging adds and overwrites but never deletes, so a package that changes what
it installs leaves the old files behind. Rebuilding mesa against libglvnd left
its previous `libEGL.so.1.0.0` and `libGLESv2.so.2.0.0` in `lfs/usr/lib` with
nothing pointing at them. Harmless, but they accumulate; `clean all` is the
only thing that removes them.

The console system, 33 packages:

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

The Wayland stack, 34 more:

| Package | Why it is here |
| --- | --- |
| libffi | wayland dispatches protocol calls through it |
| wayland | the protocol libraries, and wayland-scanner, which is a build tool |
| wayland-protocols | XML only; xdg-shell is how a client gets a window |
| seatd | hands out the DRM and input devices, so sway need not be root |
| libdrm | the userspace side of the kernel's DRM; amdgpu only |
| pixman | software rasteriser, which is how wlroots renders without a GPU |
| hwdata | pnp.ids, so a monitor reports a manufacturer and not a three-letter code |
| libdisplay-info | parses EDID into modes, size and colorimetry |
| xkeyboard-config | the layout data; `us` and `latam` are files in it |
| libxkbcommon | turns key codes into symbols, reading the above |
| libevdev | wraps the kernel input event protocol for libinput |
| mtdev | translates the kernel's older multitouch protocol into the current one |
| libinput | pointer acceleration, gestures, tap-to-click, and the device quirks database |
| elfutils | libelf only, which mesa's radeonsi hard-requires |
| libglvnd | vendor-neutral dispatch: libOpenGL, libEGL and the GLES libraries |
| mesa | GBM, Vulkan and the GL drivers behind libglvnd; radeonsi and RADV, no LLVM |
| libpng | PNG surfaces for cairo |
| freetype | the font engine; built twice, around harfbuzz |
| fontconfig | turns "monospace 11" into a file on disk |
| fribidi | the Unicode bidirectional algorithm, which pango requires |
| pcre2 | glib's regular expressions, and sway's window criteria |
| glib | GObject, which is pango's type system |
| harfbuzz | text shaping: ligatures, contextual forms, mark positioning |
| cairo | 2D drawing; sway's title bars and swaybar are cairo surfaces |
| pango | text layout, tying all of the above together |
| json-c | sway's IPC format, which swaymsg speaks |
| wlroots | the compositor library: DRM output, libinput devices, GLES2 rendering |
| sway | the compositor itself |
| dejavu-fonts | a font, without which every label renders as a box |
| tllist | a single-header list that fcft and foot both include |
| fcft | the font library foot renders with |
| foot | the terminal; sway's default config opens it on $mod+Return |
| wmenu | the launcher on $mod+d; wmenu-run feeds it $PATH and execs the pick |

And the toolchain and build tools, 34 more, which the image has because it
builds itself. None of these existed here while packages were compiled on the
build machine and staged; every one was something the host supplied without
anyone noticing until the build moved into a chroot.

| Package | Why it is here |
| --- | --- |
| binutils, gcc | the compiler and linker, so the image can rebuild itself |
| gmp, mpfr, mpc | gcc's arbitrary-precision arithmetic |
| m4, make, patch, file | chapter 6 built these; chapter 8 replaces them |
| bison, flex | parser and lexer generators |
| bc | the kernel's build system computes constants with it |
| bzip2 | not to link against — tar cannot read a `.tar.bz2` without it |
| gperf | udev's rule lookup tables |
| pkgconf | nothing from libffi onward configures without a pkg-config |
| autoconf, automake, libtool | anything regenerating a build system after a patch |
| perl | half of the chapter 8 packages run a perl script somewhere |
| gettext, texinfo | message catalogues, and makeinfo |
| python | meson is written in it |
| flit-core, packaging, wheel, setuptools | pip's build backends |
| ninja, meson | the build system most of the Wayland stack uses |
| markupsafe, jinja2 | udev generates sources from templates |
| mako, pyyaml | so does mesa, from a different pair |
| cmake | glslang builds with nothing else |
| glslang | mesa compiles RADV's shaders with `glslangValidator` |

dbus is the first package here that is not in the LFS book. The book builds no
D-Bus at all — its only mention is the `messagebus` user — so `packages/dbus.sh`
follows upstream rather than `docs/`. Note that dbus 1.16 dropped autotools:
there is no `configure` in the tarball, only meson.

The two C libraries coexist: separate loaders, separate names, and each binary
names the one it was linked against. musl lives entirely in `/musl` — headers,
libraries, crt files, specs and `musl-gcc` — which is how this workstation has
always kept it. The single exception is the loader, at
`/usr/lib/ld-musl-x86_64.so.1`, because that path is written into the
`PT_INTERP` of every musl binary and the kernel resolves it before anything
else exists.

That arrangement replaced two narrower ones. musl's `libc.so` *is* its loader
while glibc installs a linker script under the same name, so one `/usr/lib`
meant whichever built second destroyed the other's; and two C libraries were
also describing themselves in one `/usr/include`, where four musl headers
outlived glibc and `stropts.h` got included beside glibc's declarations. Both
were the same problem answered one directory at a time.

The whole Wayland stack is built against glibc, not musl: mesa is not
realistically musl-buildable here, and a stack cannot be split between two C
libraries.

Still missing from the book, none on the critical path: man-db with groff,
man-pages and libpipeline — nothing in the image can read a man page, though
`less` is built and 24M of them are installed. Then kbd, without which the
console has no way to load a keymap; iana-etc, so `/etc/services` exists;
psmisc for `killall` and `fuser`; iproute2 for `ip`; and inetutils for `ping`.
Tcl, Expect and DejaGNU are in no list because they exist only to run test
suites, and nothing here runs them.

### Building against the image, not the build machine

None of this runs any more. It is kept because it is the argument for what
replaced it: `packages/common.sh` sees `PLINUX_IN_CHROOT`, empties
`build_directory` and switches the sysroot off, because inside `lfs/` there is
no second tree for a search to escape into. What follows is what had to be
arranged by hand when there was, and is written in the past tense for that
reason.

This was the one thing about the build that was easy to get wrong, because
getting it wrong looked like success.

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
link. Both `lib/pkgconfig` and `share/pkgconfig`, because anything
architecture-independent installs to the second — `wayland-protocols` does,
and so do `kmod.pc` and `udev.pc`.

The sysroot covers what pkg-config never sees, and it is worth being precise
about how far it reaches, because it is not as far as it looks.

**Headers are covered.** `#include` resolves inside `obj`, which is what makes
`AC_CHECK_HEADER` and meson's `cc.has_header` honest. That is the check vim
needed and did not have: its configure found the host's GTK3, believed it was
building a GUI, and produced a binary naming 226 libraries the image did not
have. Under a sysroot that test fails on its own.

**Libraries are not.** GCC's own search path includes
`/usr/lib/gcc/x86_64-pc-linux-gnu/15.2.0/../../../../x86_64-pc-linux-gnu/lib/../lib`,
which resolves to the host's `/usr/lib` and is *not* sysroot-relative, so
`-lelf` and `-lsensors` link against the host's copies whatever `--sysroot`
says. `AC_CHECK_LIB` and `cc.find_library` therefore still see the build
machine. `LDFLAGS` carries `-L obj/usr/lib` to put the image first in that
order, which is as far as a native build reaches.

**And `-L` does not cover indirect dependencies.** When a program links
against `libgio`, ld follows `libgio`'s own `DT_NEEDED` to `libmount.so.1` to
check the symbols it imports — and for *that* search it uses `-rpath-link`,
`-rpath` and the default directories, never `-L`. So `LDFLAGS` carries
`-Wl,-rpath-link,obj/usr/lib` as well. Without it, glib built against the
image's util-linux 2.41.1 and everything linking against glib afterwards
resolved through the host's 2.39.1, where the function glib had just called
does not exist.

**Neither were GCC's own headers.** `#include <string>` resolved to the host's
`/usr/include/c++/15.2.0/string` even under the sysroot, while `#include
<stdio.h>` came from `obj`. The C++ standard library was the host's by
construction, so `packages/gcc-runtime.sh` copied the matching `libstdc++`,
`libgcc_s` and `libgomp` out of the same GCC rather than building them —
"because building them means building GCC", as its own comment put it. The
chroot build does build GCC, so that script is gone.

In practice the two halves catch each other. mesa's lm-sensors probe linked
against the host's `libsensors` and defined `HAVE_LIBSENSORS`, and then the
build failed on `sensors/sensors.h` — the library slipped through, the header
did not. What the sysroot misses, `./build.sh check` is there to find.

`PLINUX_SYSROOT=none` turns the sysroot off, for bisecting a package that will
not build. There is no equivalent escape for pkg-config; edit `common.sh`.

It depended on `bin`, `lib`, `lib64` and `sbin` being *relative* symlinks —
`usr/lib`, not `../../../usr/lib`. Both spell `/usr/lib` once the tree is the
root filesystem, but only the relative form also resolves correctly when the
tree is read from the build machine; the `../../..` form escaped the staged
tree entirely and landed on the host's own `/usr`, which is why `ls obj/bin`
once reported `tar` and `ps` as installed when neither was. `lfs/` gets the
same three symlinks from `toolchain/common.sh`, for the same reason, and
`lib64` is a real directory there because that is what the book's chapter 5
requires.

The kernel's userspace API headers were part of that sysroot too. In `lfs/`
they are chapter 5's and come from `linux-6.16.1` rather than the running
kernel — see `toolchain/linux-headers.sh`, which explains what installing the
newer set over them breaks.

## Running

```sh
./run                       # GTK window, console on the emulated display
./run headless              # no window, console on serial
./run help
```

`IMAGE` selects a different image in both `./run` and `build.sh virt`, which
is worth having while a new build is unproven — the old one stays bootable:

```sh
cd virtual_machine && IMAGE=spare.raw ./configure.sh
sudo IMAGE=spare.raw ./build.sh virt
IMAGE=spare.raw ./run
```

`configure.sh` makes a 4096M image by default. That was 1024M until the image
gained a compiler.

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

Writes `lfs/` to a USB disk as a self-contained bootable system. The device has
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
  -> pdaemon          udevd, seatd, dbus-daemon, iwd -- each in the
                      foreground, each logged, each restarted if it dies
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
`build.sh` does not yet stage them into `lfs/`, so the image still needs the
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
| 2 | ~3.9G | ext4 | root filesystem, staged from `lfs/` |

The guest reaches them as `/dev/nvme0n1p1` and `/dev/nvme0n1p2`, since `run`
attaches the image through an NVMe controller. The build side is unaffected:
`build.sh virt` writes the image over a loop device either way.

`/bin`, `/lib`, `/sbin` and `/var/run` are relative symlinks, and they resolve
both inside `lfs/` and once the tree is `/`. That is the point of them being
relative; see the sysroot section above. `/lib64` is a real directory holding
two symlinks to the loader, which is the book's arrangement and what the
chapter 5 toolchain was built against.

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

LFS builds inside a chroot, on a toolchain it builds first, and installs
straight into `/usr`. plinux used to do neither, staging into `obj/` from the
host toolchain instead — which meant book recipes needed `DESTDIR`, and the
isolation a chroot gives for free had to be arranged with `--sysroot` and
`-rpath-link` instead.

It now does both, and `./build.sh toolchain` through `./build.sh chroot
packages` is the book's chapters 5 to 8. The native build is gone. The
difference it makes is not theoretical: moving the
build into the chroot turned up nine things the host had been supplying
invisibly, among them a specific `automake-1.16` this workstation happened to
have installed, `pkgconf`, `meson`, `gperf`, and three python modules mesa
generates its own source with. None of them appear in any binary's `NEEDED`,
so `./build.sh check` could not have found any of them.

## System configuration

`sys/` holds what a running plinux needs outside of any package. `build.sh`
installs it as part of a normal build:

| Source | Installed to | Contents |
| --- | --- | --- |
| `sys/root/` | `/root/` | `.bash_profile`, `.bashrc`, `shell_config.sh` |
| `sys/scripts/` | `/usr/bin/` | `init_os`, `set_ip`, `pdevices` |
| `sys/etc/` | `/etc/` | staged whole: `passwd`, `fstab`, `iwd/main.conf` |
| `sys/kernel_config` | `src/linux/.config` | installed by `./configure` |

`sys/etc/` is copied wholesale rather than file by file, so a package that
needs a configuration file only has to have it added there — before that, each
new file also needed a line in `build.sh`, and one of them was missed for as
long as iwd had been in the image.

Only root exists on this system, so `/etc/passwd` is two lines — root and
messagebus — and nothing is chmodded during staging.

`/etc/group` is deliberately *not* in `sys/etc/`. It used to be, and staging it
threw away the eleven groups udev's rules name by hand — audio, cdrom, dialout,
disk, input, kmem, kvm, lp, tape, tty, video — leaving device nodes owned by
root instead. The book's `/etc/group`, written by `toolchain/chroot/layout.sh`,
has all of them, plus `netdev`, which iwd's D-Bus policy names.

These files are also the ones a plinux workstation runs from directly, by
symlink rather than by copy. Editing them changes the running machine as well
as the next image, so a mistake here is felt immediately. They are written to
tolerate that: no bare `mkdir` without checking the binary exists, `HOME`
defaulted, and `init_os` only run on `tty1` with no display already up.
`pdevices` and `init_os` also skip anything already running, since `init_os`
runs again every time the login shell on tty1 comes back.

Nothing on this system calls `syslog(3)` and there is no syslog daemon, so
everything that can fail quietly writes to a file instead. pdaemon gives each
of its four a `/var/log/<name>.log` with one previous generation, and
`init_os` does the same for sway.

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
