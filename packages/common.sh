# Sourced by the package scripts in this directory. Gives them the paths they
# build into and a couple of helpers. Not meant to be run directly.

packages_directory=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
plinux_directory=$(dirname "${packages_directory}")

src_directory=${plinux_directory}/src
build_directory=${plinux_directory}/obj
sources_directory=${plinux_directory}/sources

export MAKEFLAGS=${MAKEFLAGS:--j32}

# Packages target musl, not the host glibc. musl itself overrides this, since
# building a C library with itself is circular.
export CC=${CC:-musl-gcc}

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
export PKG_CONFIG_LIBDIR=${build_directory}/usr/lib/pkgconfig
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
  export LDFLAGS="${LDFLAGS:-} --sysroot=${plinux_sysroot}"
fi

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
