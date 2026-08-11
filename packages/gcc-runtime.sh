#!/bin/bash
#
# gcc-runtime - the support libraries GCC links into what it compiles.
#
# Copied from the host toolchain rather than built, and that needs justifying
# because nothing else here works that way.
#
# These three are part of GCC, not of glibc. A C++ program needs libstdc++,
# anything using exceptions or stack unwinding needs libgcc_s, and anything
# built with -fopenmp needs libgomp. GCC links them by soname and the loader
# finds them the ordinary way, so they have to be in the image -- but building
# them means building GCC, which is the self-hosting toolchain this project
# has not started.
#
# Nothing needed them until now: everything staged was C, and none of it used
# OpenMP. mesa is C++ throughout, and mesa turns OpenMP on unconditionally on
# x86_64 with gcc, with no option to refuse:
#
#   if host_machine.cpu_family() == 'x86_64' and cc.get_id() == 'gcc'
#     dep_openmp = dependency('openmp', required : false)
#
# This is also the edge of what --sysroot can do. GCC's own headers are not
# sysroot-relative -- #include <string> resolves to the host's
# /usr/include/c++/15.2.0/string even under --sysroot=obj, while #include
# <stdio.h> comes from obj. So the C++ standard library is the host's at build
# time by construction, and copying the matching runtime here is what keeps
# the two consistent. Reading the paths out of gcc rather than hardcoding them
# is what keeps them consistent after a host GCC upgrade; rebuild this package
# when that happens.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

# -print-file-name resolves a library against the compiler's own search path,
# which is exactly the question being asked. It echoes the name back unchanged
# when it finds nothing, so a missing library is detectable.
for library in libstdc++.so.6 libgcc_s.so.1 libgomp.so.1; do
  path=$(gcc -print-file-name="${library}")

  if [ "${path}" = "${library}" ] || [ ! -f "${path}" ]; then
    echo "gcc cannot find ${library}" >&2
    exit 1
  fi

  # readlink -f to get past the soname symlink to the real file, then install
  # under the soname, which is the only name DT_NEEDED ever asks for. The .so
  # development symlinks are not copied: nothing in the image compiles.
  real=$(readlink -f "${path}")
  install -D -m 755 "${real}" "${build_directory}/usr/lib/${library}"

  # The host ships these with debug information, which is 23M across the three
  # and of no use in an image that has no debugger. --strip-unneeded keeps the
  # dynamic symbol table, which is what the loader resolves against.
  strip --strip-unneeded "${build_directory}/usr/lib/${library}"

  echo "staged ${library} from ${real}"
done
