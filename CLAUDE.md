# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

plinux is a from-source Linux distribution (LFS-style, no package manager) whose
bootloader (`pboot`), init (`pinit`), daemon supervisor (`pdaemon`), getty
(`pgetty`) and login (`plogin`) are small C programs written for this project.
Packages are compiled on the host and staged into `obj/`, which becomes the root
filesystem of a VM image or USB stick. The README is thorough and accurate —
read the relevant section before changing build machinery.

**Critical:** the workstation this repo lives on *runs plinux*, and `sys/` is
the running machine's live configuration reached by symlink — editing
`sys/etc/`, `sys/root/` or `sys/scripts/` changes the current system
immediately, not just the next image. The `p*` components' `make install`
targets also install onto the workstation.

## Commands

```sh
./build.sh                    # everything: components (pboot, kernel, p*), then unbuilt packages, sys/ last
./build.sh packages           # walk packages/order; skips packages stamped in obj/.packages
./build.sh packages <name>    # rebuild one package (ignores its stamp)
./build.sh packages force     # rebuild all
./build.sh check              # report binaries in obj/ whose NEEDED libraries the image lacks
sudo ./build.sh virt          # write obj/ into virtual_machine/disk.raw (builds nothing)
./run                         # boot the image in QEMU (./run headless for serial console)
./build.sh clean all          # clean sources and delete obj/ (also erases the stamps)
```

The usual dev loop: `./build.sh && sudo ./build.sh virt && ./run`.

Build output streams and is also written to `logs/<step>.log` (packages log to
`logs/package-<name>.log`). Add `quiet` or set `VERBOSE=0` to only log.

There are no tests; verification is `./build.sh check` plus booting the image.
Always run `check` after building a package — a package that silently linked a
host library installs fine and only fails at runtime in the VM.

## Architecture

Boot chain: UEFI → `pboot` (reads `pboot.conf` from the ESP) → kernel →
`/pinit` as PID 1 (mounts filesystems, loopback, starts `pdaemon` and gettys) →
`pdaemon` (supervises udevd, seatd, dbus-daemon, iwd; logs each to
`/var/log/<name>.log`) → `pgetty` on tty1/tty2/ttyS0 → `plogin` → bash.
`init_os` (in `sys/scripts/`) runs from the tty1 login shell and starts sway.

- `src/` — the `p*` component sources, plus third-party trees. `src/linux` and
  `src/pboot` are external shallow clones made by `./configure` (re-run safe;
  `./configure update` pulls). Package tarballs unpack here as untracked
  versioned directories.
- `packages/` — one bash script per package plus `order` (dependency order).
  Every script sources `packages/common.sh` and installs with
  `DESTDIR="${build_directory}"` (= `obj/`), never into the host.
- `sys/kernel_config` — the kernel .config, copied to `src/linux/.config` by
  `./configure` (it comes from the workstation's `/usr/src/linux/.config`, it
  is not hand-written). `build.sh` runs `make olddefconfig` before building.
- `docs/` — the LFS 12.4 book as grepable text. Look packages up via
  `grep -i <name> docs/LFS-BOOK-12.4-index.txt`, then `sed -n '<line>,+120p'
  docs/LFS-BOOK-12.4.txt`. Book recipes install to `/usr`; they need `DESTDIR`
  adapted before use here.

### Two C libraries

glibc and musl coexist in the image. The `p*` components and bash build with
`musl-gcc` (bash statically, so the login path survives a broken loader);
everything else — the whole Wayland stack especially — builds against glibc.
musl lives in `/usr/lib/musl` because its `libc.so` is its loader and would
otherwise collide with glibc's linker script of the same name.

### The sysroot discipline (the easiest thing to get wrong)

Because the build host runs plinux, a package that finds a host library builds
successfully and produces a binary that fails only in the VM. `common.sh`
defends against this: `PKG_CONFIG_LIBDIR`/`PKG_CONFIG_SYSROOT_DIR` point
pkg-config exclusively at `obj/`, and `CFLAGS`/`LDFLAGS` carry `--sysroot`,
`-L obj/usr/lib` and `-Wl,-rpath-link,obj/usr/lib`. Headers are fully covered;
library searches are not (GCC's default paths escape the sysroot), which is
what `./build.sh check` exists to catch. `PLINUX_SYSROOT=none` disables it for
bisecting. Don't weaken any of this in a package script; when adding a package,
follow the pattern of an existing one (e.g. `packages/seatd.sh`) — a heavily
commented script explaining *why* each option is set is the house style.

Other package-system facts worth knowing:

- Staging adds/overwrites but never deletes; stale files in `obj/` persist
  until `clean all`.
- `common.sh` sets `-march=native` (override with `PLINUX_MARCH=none` for a
  portable image; existing stamps are not invalidated by changing it).
- `obj/bin`, `obj/lib`, `obj/lib64`, `obj/sbin` are *relative* symlinks so they
  resolve both inside `obj/` and as `/`. Never make them absolute.
- `memusagestat` failing `check` is expected (wants libgd).

## Conventions

- Commit messages follow `component: what changed` in lowercase, e.g.
  `pdaemon: refuse to run twice`, `packages: wayland tier 6 -- json-c, wlroots, sway`.
- Scripts here tolerate re-running (guards for already-running daemons,
  already-cloned repos, existing stamps); keep that property when editing them.
- Nothing calls syslog and there is no syslog daemon: anything that can fail
  quietly must write to its own log file (`/var/log/<name>.log`, one previous
  generation kept).
