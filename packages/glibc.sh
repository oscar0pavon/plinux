#!/bin/bash
#
# glibc - the GNU C library.
#
# LFS 12.4 section 8.5.
#
# Present because udev is part of systemd, and systemd does not build against
# musl: even the udev-only subset compiles src/basic and src/shared, which use
# glibc-specific interfaces. eudev was the usual way around that and is no
# longer maintained.
#
# glibc and musl coexist in the image the same way they do on the build host.
# They share no filenames and each binary names its own interpreter, so
# /lib64/ld-linux-x86-64.so.2 and /lib/ld-musl-x86_64.so.1 sit side by side.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'glibc-*.tar.xz' 'glibc-2.42')
cd "${directory}"

apply_patch 'glibc-*-fhs-1.patch'

# The C library is built with the host compiler; common.sh defaults CC to
# musl-gcc, which would be nonsense here.
export CC=gcc

# And without common.sh's -march. The book warns that untested -march values
# can break the toolchain packages and names Glibc among them, and glibc
# already selects AVX2 string and memory routines at runtime through ifunc, so
# building it for one CPU wins nothing that is not already happening.
unset CFLAGS CXXFLAGS

# The book's sed on stdlib/abort.c is skipped: it fixes Valgrind, which is a
# BLFS concern and not part of this system.

mkdir -p build
cd build

# ldconfig and sln otherwise land in /usr/sbin only by accident of the default
echo "rootsbindir=/usr/sbin" > configparms

# libc_cv_slibdir is an absolute path *inside the image*. The install below
# must therefore go through DESTDIR: without it, libc.so.6 and the dynamic
# loader are written straight into the build host's /usr/lib, replacing the
# running system's C library.
../configure --prefix=/usr                   \
             --disable-werror                \
             --disable-nscd                  \
             libc_cv_slibdir=/usr/lib        \
             --enable-stack-protector=strong \
             --enable-kernel=5.4

make

# LFS 8.5, two steps that only matter when the install goes to a real root.
#
# Neither was needed while this package only ever installed under DESTDIR:
# glibc's install skips both paths when it is staging into a directory that
# is not the running system. Installing into the chroot, where / is the
# target, is the first time either has been reached.
#
# ld.so.conf: the install warns about it being absent. Harmless, and one
# empty file quieter.
mkdir -p "${build_directory}/etc"
touch "${build_directory}/etc/ld.so.conf"

# test-installation.pl: a post-install sanity check that links a program
# against every library glibc believes it installed. It believes in libnsl
# and libnss_dns, which a modern glibc does not build -- libnsl moved out of
# glibc entirely and the nss_dns module is inside libc now -- so the check
# fails on a correct installation. The book calls it "an outdated sanity
# check that fails with a modern Glibc configuration" and replaces the perl
# invocation with an echo.
#
# Anchored on $(PERL), which the sed removes, so a second run finds nothing
# to do rather than nesting echoes.
sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile

make DESTDIR="${build_directory}" install

# make install stages the locale *sources* -- usr/share/i18n -- but compiles
# none of them, so the image had no locale at all and setlocale() could
# satisfy nothing beyond the built-in C. shell_config.sh exports
# LANG=C.UTF-8, and the first program to take that at its word was foot,
# which requires a UTF-8 locale and refused to start with "invalid locale".
#
# C.UTF-8 is the book's minimum (section 8.5, "some locales ... are highly
# recommended") and all a one-user system whose files are ASCII and UTF-8
# needs. The book's other recommendations are national locales.
#
# Outside the chroot this is the host's localedef writing the image's locale
# archive, which works because the compiled format is tied to the glibc
# version and the host runs the same 2.42 this package stages. Inside the
# chroot it is the image's own localedef writing its own archive, which needs
# no such argument. I18NPATH points at the sources staged above either way.
#
# --prefix is passed only when there is one. An empty build_directory means
# the chroot, where the prefix is / and "--prefix=" is not a way of saying
# that -- localedef takes it as an empty path and puts the archive somewhere
# that is not /usr/lib/locale.
mkdir -p "${build_directory}/usr/lib/locale"
I18NPATH="${build_directory}/usr/share/i18n" \
localedef ${build_directory:+--prefix="${build_directory}"} -i C -f UTF-8 C.UTF-8
