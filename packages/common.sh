# Sourced by the package scripts in this directory. Gives them the paths they
# build into and a couple of helpers. Not meant to be run directly.

packages_directory=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
plinux_directory=$(dirname "${packages_directory}")

src_directory=${plinux_directory}/src
build_directory=${plinux_directory}/obj
sources_directory=${plinux_directory}/sources

# Inside the chroot, every path below collapses to the real one.
#
# PLINUX_IN_CHROOT is set by "./build.sh chroot packages", which runs these
# same scripts with lfs/ as /. There is no staging directory there because
# there is nothing to stage away from: /usr *is* the target, so DESTDIR is
# empty and "make install" installs.
#
# Emptying build_directory is the whole change, and that is not a trick -- it
# is what the variable meant all along. Everything derived from it is already
# written as "${build_directory}/usr/...", so with it empty they read
# /usr/lib/musl, /usr/lib/pkgconfig, /usr/share/pkgconfig: correct inside the
# chroot, and the same strings the sysroot machinery was constructing
# approximations of outside it.
#
# The sysroot itself has to be switched off rather than emptied. An empty
# --sysroot= is not "no sysroot", it is a sysroot of "", and gcc treats that
# differently. PLINUX_SYSROOT=none is the existing way to say it and it
# already means exactly this.
#
# Which leaves the point of the exercise: in the chroot none of that machinery
# is doing anything, because there is no second tree for a search to escape
# into. The --sysroot, the -L, the -rpath-link and the PKG_CONFIG_SYSROOT_DIR
# below exist to make a native compiler on a host running this distribution
# behave as though the host were not there. Inside the chroot it genuinely is
# not there.
if [ -n "${PLINUX_IN_CHROOT:-}" ]; then
  src_directory=/sources-build
  build_directory=
  sources_directory=/sources
  PLINUX_SYSROOT=none
fi

export MAKEFLAGS=${MAKEFLAGS:--j32}

# Packages target musl, not the host glibc. musl itself overrides this, since
# building a C library with itself is circular.
#
# The -L is part of the compiler and not of LDFLAGS below, which is the whole
# point of writing it here. LDFLAGS puts obj/usr/lib first, and obj/usr/lib is
# where *glibc* installs libc.so. musl-gcc's specs do add -L/musl/lib, but gcc
# places LDFLAGS ahead of the paths the specs contribute, so "-lc" in a musl
# build resolved to glibc: the link pulled in obj/usr/lib/libc.so, which is
# glibc's linker script, and through it the build machine's own libc.so.6.
#
# Both halves of that are wrong and neither is loud. The binary comes out
# asking for the musl loader while naming libc.so.6, which cannot run --
# and "./build.sh check" passes it, because libc.so.6 *is* in the image.
# Worse, every configure test links the same way, so the package is told it
# has whatever glibc has. That is what stopped the build in coreutils:
# AC_CHECK_FUNC(error) succeeded against glibc, musl has no error() and no
# error.h, and gnulib duly left error() undeclared in the one file that
# calls it.
#
# Carried on CC because common.sh is sourced before a package says
# "export CC=gcc". Anything exported here by name -- LDFLAGS, LIBRARY_PATH --
# would reach the glibc packages too and point their -lc at musl, which is
# the same bug with the libraries swapped. Attached to the compiler it goes
# away the moment the compiler does.
#
# The image's /musl rather than the build host's, which are now the same path
# and not the same tree -- packages/musl.sh installs everything but the loader
# under /musl, matching how this workstation keeps it. Inside the chroot
# build_directory is empty and this reads -L/musl/lib, which is the image's.
# If musl is not staged yet the directory does not exist and the specs' own
# -L/musl/lib is what answers.
export CC=${CC:-musl-gcc -L${build_directory}/musl/lib}

# Built for the machine that builds them. This is a personal system, so the
# image only ever runs on this i9-14900K or in the VM, and the VM is started
# with -cpu host so its ISA is the same one.
#
# PLINUX_MARCH overrides it; PLINUX_MARCH=none builds generic x86-64 instead,
# which is what to use if the image has to run anywhere else. Note that
# changing this does not rebuild anything by itself: the already-built
# packages keep their stamps, so follow it with "./build.sh packages force".
#
# glibc opts out of this in its own script. The book warns that -march values
# it has not tested can break the toolchain packages and names Glibc as one,
# and glibc already picks AVX2 string routines at runtime through ifunc, so
# there is nothing to win and a working C library to lose.
plinux_march=${PLINUX_MARCH:-native}

if [ "${plinux_march}" != "none" ]; then
  export CFLAGS="${CFLAGS:--O2 -pipe} -march=${plinux_march}"
  export CXXFLAGS="${CXXFLAGS:--O2 -pipe} -march=${plinux_march}"
fi

# Look in the image, not on the build machine.
#
# These builds run on a workstation that is itself running plinux, so a
# package that finds a library in the host's /usr links against very nearly
# the right thing and the build succeeds. The result only fails somewhere
# else: in the VM, or off the rescue USB, where that library was never
# installed. Nothing catches it in between.
#
# LIBDIR, not PATH: PKG_CONFIG_PATH is searched *before* the default
# directories and PKG_CONFIG_LIBDIR *replaces* them. With LIBDIR the host's
# /usr/lib/pkgconfig stops existing as far as pkg-config is concerned, so a
# dependency that was never staged is a hard error at configure time instead
# of a silent host link discovered months later.
#
# SYSROOT_DIR then rewrites the -I and -L in what the .pc files print: they
# were installed saying prefix=/usr, which is true of the image and not of
# this tree.
#
# Both directories, because pkg-config's own default is both. Anything
# architecture-independent installs to share/pkgconfig rather than
# lib/pkgconfig -- wayland-protocols is data only and does exactly that, and
# so do kmod.pc and udev.pc. With only lib/pkgconfig here they are invisible,
# and "dependency('wayland-protocols')" fails in a stack where every package
# after wayland asks for it.
export PKG_CONFIG_LIBDIR=${build_directory}/usr/lib/pkgconfig:${build_directory}/usr/share/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=${build_directory}

# The same rule for everything that does not go through pkg-config, which is
# most of what a configure script checks: AC_CHECK_HEADER, AC_CHECK_LIB,
# meson's cc.find_library, cmake's find_package. --sysroot moves gcc's default
# /usr/include and /usr/lib into the image.
#
# This is the check vim needed and did not have. Its configure found the
# host's GTK3, believed it was building a GUI, and produced a binary naming
# 226 libraries the image did not have -- and it built and installed cleanly.
# Under a sysroot that configure test simply fails and vim builds console-only
# on its own.
#
# Safe as a native flag because obj/usr/lib already holds crt1.o, crti.o,
# crtn.o and both loaders, and because obj/lib is a relative symlink now: with
# the old ../../../usr/lib it would have pointed the search straight back at
# the host and quietly undone all of this.
#
# PLINUX_SYSROOT=none opts out, for bisecting a package that will not build.
plinux_sysroot=${PLINUX_SYSROOT:-${build_directory}}

if [ "${plinux_sysroot}" != "none" ]; then
  export CFLAGS="${CFLAGS} --sysroot=${plinux_sysroot}"
  export CXXFLAGS="${CXXFLAGS} --sysroot=${plinux_sysroot}"

  # -L as well as --sysroot, because --sysroot does not cover -l.
  #
  # gcc's own library search path includes
  # .../x86_64-pc-linux-gnu/lib/../lib, which resolves to the build machine's
  # /usr/lib and is not sysroot-relative, so "-lfoo" finds the host's copy
  # whatever --sysroot says. That is harmless while the two agree and wrong
  # the moment they do not: this host carries util-linux 2.39.1 from 2024
  # while the image stages 2.41.1, and glib 2.86 calls
  # mnt_monitor_veil_kernel, which exists only in the newer one. glib's
  # configure test passed, because pkg-config handed it -L obj, and the link
  # of libgio then failed against the host's older libmount.
  #
  # Putting obj first fixes the ordering rather than the search path -- the
  # host's directories are still there, behind it. That is as far as a native
  # build can go without a chroot.
  #
  # This is what the README used to warn against, on the grounds that it puts
  # the image's glibc ahead of the host's and configure's test programs then
  # cannot run. That has been moot since --sysroot went in: crt1.o and libc
  # already come from obj, and fifty packages have built and run their tests
  # that way.
  # -rpath-link as well as -L, because -L does not cover indirect
  # dependencies either.
  #
  # When a program links against libgio, ld has to resolve the symbols libgio
  # itself imports, so it follows libgio's DT_NEEDED and loads libmount.so.1
  # to check. For that search it uses -rpath-link, -rpath, LD_LIBRARY_PATH and
  # the default directories -- and not -L, which applies only to what "-lfoo"
  # names directly. So obj's libmount was first for glib's own link and the
  # host's 2.39.1 was still first for everything linking against glib
  # afterwards, and the symbol glib had just used came back undefined.
  #
  # This writes nothing into the output: -rpath-link is link-time only, unlike
  # -rpath, which would bake a build-machine path into the binary.
  export LDFLAGS="${LDFLAGS:-} --sysroot=${plinux_sysroot} -L${plinux_sysroot}/usr/lib -Wl,-rpath-link,${plinux_sysroot}/usr/lib"
fi

# Configure a meson package into a build directory inside its source tree.
#
# The reason this is a helper and not four copies of a command line is
# --libdir. Meson does not default it to "lib": on x86_64 it looks at the
# *build machine* and picks "lib64" if /usr/lib64 exists there as a real
# directory. This host grew one, so meson started installing into
# obj/usr/lib64 -- a directory the image does not have and nothing searches,
# with the .pc files going to obj/usr/lib64/pkgconfig where PKG_CONFIG_LIBDIR
# does not look either. The package installs, and the next one cannot find it.
#
# dbus only escaped because it was built before that directory appeared on the
# host. That is the worst kind of bug: correct on one machine, wrong on the
# same machine a week later, and silent both times. Naming libdir explicitly
# makes it depend on nothing.
#
# --wrap-mode=nodownload because a missing dependency should be a build
# failure, not meson quietly fetching a copy from the network and building a
# private one into the image.
#
# The build directory is removed first: meson refuses to reconfigure one whose
# options have changed, and these scripts are re-run after every failure.
meson_setup(){
  local build_dir=$1
  shift

  rm -rf "${build_dir}"

  meson setup "${build_dir}"       \
        --prefix=/usr              \
        --libdir=lib               \
        --buildtype=release        \
        --wrap-mode=nodownload     \
        "$@"
}

# Unpack an archive from sources/ into src/ unless it is already there, and
# print where it landed. Progress goes to stderr so the path stays usable.
unpack(){
  local pattern=$1
  local directory=$2
  local archive

  if [ -d "${src_directory}/${directory}" ]; then
    echo "already unpacked: ${directory}" >&2
    echo "${src_directory}/${directory}"
    return 0
  fi

  archive=$(ls ${sources_directory}/${pattern} 2>/dev/null | head -1)

  if [ -z "${archive}" ]; then
    echo "no ${pattern} in ${sources_directory}; run ./download.sh" >&2
    return 1
  fi

  echo "unpacking ${archive##*/}" >&2

  if ! tar -xf "${archive}" -C "${src_directory}"; then
    echo "cannot unpack ${archive}" >&2
    return 1
  fi

  if [ ! -d "${src_directory}/${directory}" ]; then
    echo "${archive##*/} did not unpack to ${directory}" >&2
    return 1
  fi

  echo "${src_directory}/${directory}"
}

# Apply a patch from sources/ if it was downloaded; quietly do nothing if not
apply_patch(){
  local pattern=$1
  local patch_file

  patch_file=$(ls ${sources_directory}/${pattern} 2>/dev/null | head -1)

  if [ -z "${patch_file}" ]; then
    return 0
  fi

  # A failed build leaves its tree patched, and these scripts are re-run after
  # every failure. If the patch reverses cleanly it is already in, and
  # applying it again would fail on every hunk.
  if patch -Np1 -R --dry-run -i "${patch_file}" > /dev/null 2>&1; then
    echo "already applied: ${patch_file##*/}" >&2
    return 0
  fi

  echo "applying ${patch_file##*/}" >&2
  patch -Np1 -i "${patch_file}"
}
