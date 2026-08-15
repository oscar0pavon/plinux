#!/bin/bash
#
# ninja - the build backend meson generates for. LFS 12.4 section 8.56.
#
# Bootstrapped by python rather than built by meson, which is what stops the
# two being circular: meson needs ninja to build anything, ninja needs only a
# C++ compiler and a python to drive it.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'ninja-*.tar.gz' 'ninja-1.13.1')
cd "${directory}"

export CC=gcc

# NINJAJOBS, the book's optional patch, applied.
#
# ninja defaults to cores + 2 parallel jobs and takes no -j from the packages
# that embed it -- which is most meson packages. On a 32-thread machine
# building mesa that is 34 compilers at once, and the reason to want a lever
# is less the CPU than the memory: a C++ link step that runs 34 wide is how a
# build dies in the swap.
#
# Guarded because the sed inserts lines and is not idempotent.
if ! grep -q 'NINJAJOBS' src/ninja.cc; then
  sed -i '/int Guess/a \
  int   j = 0;\
  char* jobs = getenv( "NINJAJOBS" );\
  if ( jobs != NULL ) j = atoi( jobs );\
  if ( j > 0 ) return j;\
' src/ninja.cc
fi

# --bootstrap makes ninja compile itself and then rebuild itself with the
# result, which is also the only test of this package that runs here: the
# real suite needs cmake, which this system does not have.
python3 configure.py --bootstrap --verbose

install -vm755 ninja "${build_directory}/usr/bin/"
install -vDm644 misc/bash-completion \
  "${build_directory}/usr/share/bash-completion/completions/ninja"
install -vDm644 misc/zsh-completion \
  "${build_directory}/usr/share/zsh/site-functions/_ninja"
