# Sourced by the scripts in this directory, which build the LFS chapter 5
# cross toolchain. Not meant to be run directly.
#
# This is deliberately not packages/common.sh, and the difference is the whole
# point of chapter 5.
#
# packages/common.sh spends two hundred lines aiming a *native* compiler at
# obj/ -- --sysroot, PKG_CONFIG_LIBDIR, -L, -rpath-link -- because a native
# build on a machine that already runs this distribution will otherwise find
# the machine. It half works: headers are covered, libraries are not, and
# every package that trips over the difference has earned itself a comment.
#
# Chapter 5 fixes that by not being native. $LFS_TGT-gcc is configured
# --with-sysroot=$LFS, so the host's /usr/lib and /usr/include are on no
# search path at all -- not for -l, not for -rpath-link, not for AC_CHECK_LIB,
# and not for a Makefile doing [ -f /usr/include/foo.h ]. There is nothing
# left to defend against, so nothing here defends.
#
# Which means: do not add CFLAGS here. Setting them is the one reliable way
# to put the host back on a search path. No -march either -- the book warns
# that untested -march values break the toolchain packages and names glibc
# specifically, packages/glibc.sh already opts out for that reason, and a
# cross compiler's own code generation is not where this system's performance
# comes from. Chapter 8 is where -march becomes interesting again.

toolchain_directory=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
plinux_directory=$(dirname "${toolchain_directory}")

src_directory=${plinux_directory}/src
sources_directory=${plinux_directory}/sources

# $LFS. A directory in the repository rather than a mounted partition, which
# the book assumes only because it is written for someone with a spare disk.
# Nothing in chapters 5 to 7 needs a filesystem boundary; obj/ has been a
# plain directory that becomes a root filesystem since this project started,
# and build.sh virt already knows how to pour one into an image.
#
# Beside obj/ rather than replacing it: obj/ still holds a system that boots,
# and it keeps booting until this one can take over.
export LFS=${LFS:-${plinux_directory}/lfs}

# The triplet. Deliberately not what config.guess reports for this machine --
# "x86_64-lfs-linux-gnu" differs from "x86_64-pc-linux-gnu" in the vendor
# field alone, and that difference is what makes the build systems below
# believe they are cross-compiling and reach for $LFS/tools/bin/$LFS_TGT-gcc
# instead of /usr/bin/gcc. It has no effect on the code produced.
export LFS_TGT=$(uname -m)-lfs-linux-gnu

# LFS 4.4. POSIX rather than the host's locale, so configure scripts that
# parse their own tools' output are not reading a translation.
export LC_ALL=POSIX

# $LFS/tools/bin first, so the cross tools are picked up the moment they are
# installed. /usr/bin and /usr/sbin after it and nothing else: this host's
# real PATH carries rust, go, the jdk, rocm, texlive and /musl/bin, none of
# which chapter 5 has any business seeing. The scripts here are run under
# "env -i" by build.sh, so this is the entire PATH, not an addition to one.
#
# The book adds /bin conditionally, "if [ ! -L /bin ]". Here it is always a
# symlink -- this host is a merged-/usr system and so is the image -- so the
# test is left out rather than written to always fail.
export PATH=${LFS}/tools/bin:/usr/bin:/usr/sbin

# LFS 4.4. Without this, a configure script may load site defaults from the
# host's /usr/share/config.site and cache the host's answers. Pointed at a
# path inside $LFS that does not exist, which is the point: nothing is found.
export CONFIG_SITE=${LFS}/usr/share/config.site

export MAKEFLAGS=${MAKEFLAGS:--j$(nproc)}

# LFS 2.6. 022 so the tree being built does not inherit a restrictive default
# from whatever created the directory.
umask 022

# Where a finished step records itself, so the walk can be resumed. Same
# arrangement as obj/.packages: a stamp per step, keyed on the step name.
stamp_directory=${LFS}/.toolchain

# LFS 4.2, the limited directory layout, plus 5.5's loader symlinks.
#
# Run before every step rather than once, because these scripts are re-run
# after every failure and a half-created $LFS is the normal state to find.
# All of it is idempotent.
toolchain_layout(){
  mkdir -p "${LFS}"/{etc,var,tools} "${LFS}"/usr/{bin,lib,sbin}

  local link
  for link in bin lib sbin; do
    # Relative, and for the same reason obj/bin is: "usr/bin" resolves both
    # when the tree is read from here and when it is the root filesystem.
    # An absolute /usr/bin would point at the build machine right now, and
    # a --sysroot search that follows it would leave $LFS without saying so.
    if [ "$(readlink "${LFS}/${link}" 2>/dev/null)" != "usr/${link}" ]; then
      ln -sfn "usr/${link}" "${LFS}/${link}"
    fi
  done

  # lib64 is a real directory here, unlike obj/lib64 which is a symlink to
  # usr/lib. The book's arrangement (4.2 and 5.5): /lib64 holds nothing but
  # two symlinks naming the loader, which glibc's own install and the
  # chapter 5 sanity checks both expect to find by that path. Reconciling
  # this with obj/'s convention is a chapter 8 question, not this one.
  mkdir -p "${LFS}/lib64"

  mkdir -p "${stamp_directory}"
}

# Unpack an archive from sources/ into src/ unless it is already there, and
# print where it landed. Progress to stderr so the path stays usable.
# Same contract as packages/common.sh's unpack, repeated rather than shared
# because that file cannot be sourced here without its CFLAGS coming too.
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
    echo "no ${pattern} in ${sources_directory}; run ./download.sh --list wget-list-toolchain" >&2
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

# A build directory inside a source tree, emptied first.
#
# The book says "mkdir -v build; cd build" and assumes a tarball just landed.
# These scripts are re-run after failures, on a tree that already has one, and
# a configure that ran against different options leaves cached answers that
# are worse than no build directory at all.
#
# The name is a parameter because two of these trees are shared with
# packages/. src/glibc-2.42 is built here cross-compiled into $LFS and again
# by packages/glibc.sh natively into obj/, and both would otherwise call
# their build directory "build" and silently inherit the other's config.cache.
# Chapter 5 uses "build-cross" throughout; packages/ keeps "build".
fresh_build_dir(){
  local tree=$1
  local name=${2:-build-cross}

  rm -rf "${tree}/${name}"
  mkdir -p "${tree}/${name}"
  echo "${tree}/${name}"
}

# Chapter 6 unpacks into src/cross/ rather than src/, and it has to.
#
# Eleven of chapter 6's packages are also packages in packages/order -- bash,
# coreutils, sed, grep, gawk, findutils, diffutils, gzip, tar, xz -- and both
# chapters build the same tarball. The difference is the compiler: chapter 6
# cross-compiles with $LFS_TGT-gcc into $LFS, packages/ builds natively with
# musl-gcc into obj/.
#
# Neither uses a separate build directory, because the book does not. So
# sharing src/bash-5.3 between them means the second configure overwrites the
# first's Makefile and config.status while the first's .o files are still
# lying there, and make has no reason to rebuild the ones whose sources have
# not changed. The result links objects from two different compilers and two
# different C libraries, installs cleanly, and fails somewhere else entirely.
#
# That is the exact failure mode this whole chapter exists to make impossible,
# so it would be a poor place to introduce it. Separate trees, and the cost is
# disk that "clean" reclaims.
cross_src_directory=${src_directory}/cross

unpack_cross(){
  local pattern=$1
  local directory=$2
  local archive

  mkdir -p "${cross_src_directory}"

  if [ -d "${cross_src_directory}/${directory}" ]; then
    echo "already unpacked: cross/${directory}" >&2
    echo "${cross_src_directory}/${directory}"
    return 0
  fi

  archive=$(ls ${sources_directory}/${pattern} 2>/dev/null | head -1)

  if [ -z "${archive}" ]; then
    echo "no ${pattern} in ${sources_directory}; run ./download.sh --list wget-list-toolchain" >&2
    return 1
  fi

  echo "unpacking ${archive##*/} into cross/" >&2

  if ! tar -xf "${archive}" -C "${cross_src_directory}"; then
    echo "cannot unpack ${archive}" >&2
    return 1
  fi

  if [ ! -d "${cross_src_directory}/${directory}" ]; then
    echo "${archive##*/} did not unpack to ${directory}" >&2
    return 1
  fi

  echo "${cross_src_directory}/${directory}"
}

# The same, but from the tarball every time.
#
# Two of chapter 6's packages -- ncurses and file -- build twice out of one
# tree: a native helper in build/ that the cross build needs to exist (tic to
# compile the terminfo database, file to compile the magic database), and then
# the cross build in the tree itself, because that is how the book configures
# both. The second one writes into the directory the first one configures
# against, so the tree that a successful run leaves behind is not a tree the
# next run can start from:
#
#   file:    configure: error: source directory already configured;
#            run "make distclean" there first
#
#   ncurses: cc1: fatal error: ../ncurses/expanded.c: No such file or directory
#
#            -- because VPATH in build/ncurses is "../../ncurses", where the
#            last cross build left its generated expanded.c. make finds that
#            copy, concludes there is nothing to generate, and the recipe then
#            compiles "../ncurses/expanded.c", which from build/ncurses is the
#            file it just declined to write.
#
# Both are the same failure: a step that worked once and then could not be run
# again, which is the property everything in this repository is supposed to
# have. "make distclean" would fix file and would have to be trusted to fix
# ncurses; unpacking again is what the book assumes anyway and costs one tar.
unpack_cross_fresh(){
  local directory=$2

  rm -rf "${cross_src_directory:?}/${directory}"

  unpack_cross "$@"
}

# The chapter 6 configure line.
#
# Almost every package in that chapter is configured identically:
#
#   ./configure --prefix=/usr --host=$LFS_TGT --build=$(<somewhere>/config.guess)
#
# and differs only in extra options and in where config.guess happens to live.
# Seventeen copies of that with nothing to say about any of them would be
# noise, so it is written once here and the per-package scripts carry only
# what is actually specific to them.
#
# config.guess is located rather than named. The book spells the path out per
# package -- build-aux/config.guess for m4, ./config.guess for ncurses,
# support/config.guess for bash -- which is information about where a project
# keeps its autotools files and not a decision anyone is making. Searching the
# three known locations gets the same answer and does not go stale when a
# package rearranges itself.
#
# --build is what makes this a cross-compile as far as autoconf is concerned:
# it describes the machine doing the building, --host describes the machine
# that will run the result, and a configure script that sees them differ stops
# trying to run the programs it compiles. Without it, a test would execute an
# $LFS_TGT binary on this workstation, which works by accident here -- same
# architecture -- and would be answering the wrong question either way.
cross_configure(){
  local guess=

  local candidate
  for candidate in build-aux/config.guess config.guess support/config.guess; do
    if [ -f "${candidate}" ]; then
      guess=${candidate}
      break
    fi
  done

  if [ -z "${guess}" ]; then
    echo "no config.guess in $(pwd)" >&2
    return 1
  fi

  ./configure --prefix=/usr                \
              --host="${LFS_TGT}"          \
              --build="$(sh "${guess}")"   \
              "$@"
}

# Apply a patch from sources/ unless it is already in.
#
# Same reversal test as packages/common.sh: a failed build leaves its tree
# patched, these scripts are re-run after every failure, and a second
# application fails on every hunk. Unlike that one this is not optional --
# a missing patch here is a missing patch, not a package that did not need
# one -- so it returns non-zero rather than quietly doing nothing.
apply_patch(){
  local pattern=$1
  local patch_file

  patch_file=$(ls ${sources_directory}/${pattern} 2>/dev/null | head -1)

  if [ -z "${patch_file}" ]; then
    echo "no ${pattern} in ${sources_directory}" >&2
    return 1
  fi

  if patch -Np1 -R --dry-run -i "${patch_file}" > /dev/null 2>&1; then
    echo "already applied: ${patch_file##*/}" >&2
    return 0
  fi

  echo "applying ${patch_file##*/}" >&2
  patch -Np1 -i "${patch_file}"
}
