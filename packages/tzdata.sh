#!/bin/bash
#
# tzdata - the timezone database, and the machine's own zone.
#
# LFS 12.4 section 8.5.2.2. Without this the kernel's idea of time -- seconds
# since 1970, counted in UTC -- has nothing to convert it with, so every
# timestamp on the system reads as UTC: three hours ahead of the wall clock
# here, and three hours away from anything the build host wrote.
#
# Not a compiled package. zic reads the source files and writes the binary
# zone files; nothing links against any of it.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

version=2025b
timezone=${PLINUX_TIMEZONE:-America/Asuncion}

# This tarball has no top-level directory: it unpacks into the current one.
# unpack() from common.sh expects the directory to appear, so the extraction
# is done here instead.
directory=${src_directory}/tzdata${version}

if [ ! -f "${directory}/southamerica" ]; then
  archive=$(ls ${sources_directory}/tzdata${version}.tar.gz 2>/dev/null | head -1)

  if [ -z "${archive}" ]; then
    echo "no tzdata${version}.tar.gz in ${sources_directory}" >&2
    exit 1
  fi

  mkdir -p "${directory}"
  tar -xf "${archive}" -C "${directory}"
fi

cd "${directory}"

zoneinfo=${build_directory}/usr/share/zoneinfo
mkdir -p "${zoneinfo}"/{posix,right}

# The whole database, not just the one zone this machine sits in. It is a
# couple of megabytes, and having only the local zone means every foreign
# timestamp is unreadable and moving the machine needs a rebuild.
#
# Three copies of each, as the book has it: the plain tree and posix/ are
# built without leap seconds, right/ with them.
for region in etcetera southamerica northamerica europe africa antarctica \
              asia australasia backward; do
  zic -L /dev/null   -d "${zoneinfo}"       ${region}
  zic -L /dev/null   -d "${zoneinfo}/posix" ${region}
  zic -L leapseconds -d "${zoneinfo}/right" ${region}
done

cp -v zone.tab zone1970.tab iso3166.tab "${zoneinfo}"

# posixrules. New York because POSIX wants the daylight saving rules to
# follow the US ones, which is a standards quirk and not a statement about
# where this machine is.
zic -d "${zoneinfo}" -p America/New_York

# The machine's own zone. Relative so it still resolves when the tree is
# looked at from outside, and -n so a re-run replaces the link rather than
# creating one inside the directory it already points at.
mkdir -p "${build_directory}/etc"
ln -sfnv "../usr/share/zoneinfo/${timezone}" "${build_directory}/etc/localtime"
