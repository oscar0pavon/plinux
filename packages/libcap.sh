#!/bin/bash
#
# libcap - POSIX capabilities. LFS 12.4 section 8.26.
#
# udev links against libcap.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'libcap-*.tar.xz' 'libcap-2.76')
cd "${directory}"

export CC=gcc

# no configure script; the static library is not wanted
sed -i '/install -m.*STA/d' libcap/Makefile

# PAM_CAP=no, which the book does not need to say and this build does.
#
# Make.Rules decides whether to build the PAM module with a shell test on the
# build machine's filesystem:
#
#   PAM_CAP ?= $(shell if [ -f /usr/include/security/pam_modules.h ]; ...)
#
# No compiler flag reaches that. --sysroot moves where the *compile* looks
# for headers, not where a Makefile's [ -f ] looks, so on a host with
# Linux-PAM installed the answer is yes and pam_cap.c then stops on a header
# the sysroot has hidden from it. LFS never meets this because it builds
# inside a chroot, where the test sees the same tree the compiler does.
#
# no rather than a workaround, because it is also the right answer: nothing
# in this image has PAM. plogin execs the shell directly, shadow is not
# built, and a PAM module here would have nothing to load it.
make prefix=/usr lib=lib PAM_CAP=no

make prefix=/usr lib=lib PAM_CAP=no DESTDIR="${build_directory}" install
