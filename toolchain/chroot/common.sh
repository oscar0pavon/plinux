# Sourced by the chapter 7 scripts, which run *inside* the chroot. Not meant
# to be run from the host, where the paths below do not exist.
#
# The difference from toolchain/common.sh is that almost everything it does is
# no longer necessary. There is no $LFS to point a sysroot at, no $LFS_TGT, no
# --host/--build pair, and no DESTDIR: lfs/ is / now, /usr is the real /usr,
# and "make install" installs. Chapter 5 and 6 existed to reach this state and
# this file is what is left of them once it is reached.
#
# What does still matter is that nothing here reintroduces the host. It
# cannot: there is no host filesystem mounted except /dev, /proc and /sys, and
# the two read-only binds carrying the tarballs and these scripts. A configure
# script that goes looking for a library outside this tree will not find one,
# which is the property the whole exercise was for.

# /sources is the repository's sources/ bind mounted read-only by
# build.sh, so nothing here can write to it -- which is why the unpack below
# extracts somewhere else rather than beside the tarball the way packages/ does.
sources_directory=/sources

# Writable, inside the chroot, and not /tmp: chapter 8 will want these trees
# to still be there after a failure, and /tmp is a plausible thing for
# something else to clear.
build_root=/var/tmp/toolchain

export MAKEFLAGS=${MAKEFLAGS:--j$(nproc)}

umask 022

# Unpack an archive from /sources into the build root unless it is already
# there, and print where it landed. Progress to stderr so the path stays
# usable as $(unpack ...).
unpack(){
  local pattern=$1
  local directory=$2
  local archive

  mkdir -p "${build_root}"

  if [ -d "${build_root}/${directory}" ]; then
    echo "already unpacked: ${directory}" >&2
    echo "${build_root}/${directory}"
    return 0
  fi

  archive=$(ls ${sources_directory}/${pattern} 2>/dev/null | head -1)

  if [ -z "${archive}" ]; then
    echo "no ${pattern} in ${sources_directory}" >&2
    return 1
  fi

  echo "unpacking ${archive##*/}" >&2

  if ! tar -xf "${archive}" -C "${build_root}"; then
    echo "cannot unpack ${archive}" >&2
    return 1
  fi

  if [ ! -d "${build_root}/${directory}" ]; then
    echo "${archive##*/} did not unpack to ${directory}" >&2
    return 1
  fi

  echo "${build_root}/${directory}"
}
