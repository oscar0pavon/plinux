#!/bin/bash
#
# ncurses - terminal handling. LFS 12.4 section 8.30.
#
# Nine util-linux programs already link libtinfo or libncursesw and could not
# start without it: dmesg, lsblk, more, cal, hexdump, setterm, ul, cfdisk and
# irqtop. They were built against the host's copy and nothing staged it.
#
# The book uses the 6.5-20250809 snapshot from invisible-mirror.net, which is
# not reachable from here. This is plain 6.5 from ftp.gnu.org; same ABI, same
# libncursesw.so.6.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'ncurses-*.tar.gz' 'ncurses-6.5')
cd "${directory}"

# glibc, because the programs that need it are glibc programs
export CC=gcc

# --without-cxx-binding replaces the book's --with-cxx-shared. The C++
# binding in 6.5 does not compile against GCC 15: it declares NCURSES_BOOL as
# unsigned char, which collides with the bool specialisations in <type_traits>
# and <cstddef>, and the build stops on cursesw.o. The book's later snapshot
# carries the fix. Nothing in this image is C++, so the binding is dropped
# rather than patched -- libncurses++w is the only thing lost.
# cf_cv_header_stdbool_h=1 makes the installed curses.h include <stdbool.h>
# instead of deciding it does not have to.
#
# The test behind that cache variable compiles "bool foo = false;" with no
# include at all, and takes success to mean the compiler has bool built in
# and curses.h needs no header for it. That is true of the compiler ncurses
# is built with -- gcc 15 defaults to C23, where bool, true and false are
# keywords -- and it is a statement about the *build*, which then gets
# written into a header the whole image compiles against.
#
# Anything still on an older dialect then gets half a definition: curses.h
# typedefs bool itself but leaves true and false to a header it did not
# include. procps-ng is built -std=gnu99 by its own configure, and watch.c
# stopped on "'false' undeclared" with gcc helpfully pointing at the header
# ncurses had just decided against.
#
# Harmless where it was not needed: under C23 stdbool.h is empty of anything
# new, and under C++ it defines nothing at all.
./configure cf_cv_header_stdbool_h=1 \
            --prefix=/usr           \
            --mandir=/usr/share/man \
            --with-shared           \
            --without-debug         \
            --without-normal        \
            --without-cxx-binding   \
            --enable-pc-files       \
            --with-pkg-config-libdir=/usr/lib/pkgconfig

make

# The book installs to a dest/ directory and then copies into / by hand,
# because overwriting libncursesw.so in place can crash the shell that is
# running the install. That does not apply here: DESTDIR is the image, and
# nothing in it is running.
make DESTDIR="${build_directory}" install

# Force the wide-character ABI in the header, as the book does. Without this
# the non-wide symlinks below would let something build against curses.h and
# link a library with a different struct layout.
sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "${build_directory}/usr/include/curses.h"

# Many programs still ask the linker for -lncurses, -lform, -lpanel or -lmenu.
# Point those at the wide-character libraries, which is safe now that the
# header always selects that ABI.
for library in ncurses form panel menu; do
  ln -sfv lib${library}w.so "${build_directory}/usr/lib/lib${library}.so"
  ln -sfv ${library}w.pc    "${build_directory}/usr/lib/pkgconfig/${library}.pc"
done

ln -sfv libncursesw.so "${build_directory}/usr/lib/libcurses.so"

# The build host splits the terminfo functions into their own libtinfo, so
# everything compiled against it -- dmesg, lsblk, more, cal, hexdump, setterm,
# ul, cfdisk, fdisk, sfdisk -- records libtinfo.so.6 as a dependency. This
# ncurses keeps those functions inside libncursesw instead, where they are all
# still exported (tputs, tgetent, setupterm, tigetstr and the rest), so
# pointing the name at it satisfies both the loader and every symbol.
ln -sfv libncursesw.so.6 "${build_directory}/usr/lib/libtinfo.so.6"
ln -sfv libncursesw.so   "${build_directory}/usr/lib/libtinfo.so"

# And tinfo.pc, which is the same claim made to pkg-config rather than to the
# linker, and was missing.
#
# The libtinfo.so symlink above is what readline's configure finds when it
# looks for the termcap functions, so readline records "Requires.private:
# tinfo" in its own readline.pc. Nothing then described tinfo to pkg-config,
# so anything asking "pkg-config --exists readline" got:
#
#   Package 'tinfo', required by 'readline', not found
#
# which is how iwd stopped, on a readline that is installed and works. Two
# halves of one compatibility shim, and only the linker's half was here.
ln -sfv ncursesw.pc "${build_directory}/usr/lib/pkgconfig/tinfo.pc"
