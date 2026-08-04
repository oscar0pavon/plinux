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
