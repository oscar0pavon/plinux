#!/bin/bash
#
# vim - the editor.
#
# LFS 12.4 section 8.73. Until now the image had no way to change a file in
# place: no vi, no ed, nothing. Editing /etc/fstab or an iwd config meant
# rebuilding the image from this workstation.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

version=9.1.1629
runtime=vim91

directory=$(unpack "vim-*.tar.gz" "vim-${version}")
cd "${directory}"

# glibc, not musl: vim links libncursesw for the terminal handling, and
# ncurses here is a glibc build.
export CC=gcc

# The book appends this to move the system vimrc out of /usr/share/vim.
# Guarded because these scripts are re-run after a failure, and appending it
# twice would define the macro twice.
if ! grep -q SYS_VIMRC_FILE src/feature.h; then
  echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
fi

# The book runs a bare ./configure, which is right inside a chroot that has
# no X headers. This workstation has them, and vim's configure then finds
# GTK3 and builds the GUI: gvim, linked against gtk-3, X11, wayland-client,
# cairo, pango, harfbuzz, glib and libcanberra, none of which are in the
# image. Every vim binary installed that way fails at startup. "./build.sh
# check" reported it as 226 unresolved dependencies -- the same list of
# missing libraries once per installed binary.
#
# distclean first: configure caches its answers, so changing these options
# on a tree that was already built is otherwise ignored.
make distclean > /dev/null 2>&1 || true

# --without-wayland is separate from --without-x. Vim 9.1 gained a Wayland
# clipboard backend, and it links libwayland-client whether or not X is in
# the build; the image has no wayland libraries until the sway chain exists.
./configure --prefix=/usr    \
            --enable-gui=no  \
            --without-x      \
            --without-wayland  \
            --disable-canberra \
            --disable-selinux  \
            --disable-gpm      \
            --disable-desktop-database-update

make

# vim's "make install" creates ex, view, rvim, rview and vimdiff with a plain
# "ln -s" and no -f, so it fails on a tree that already has them. These
# scripts are re-run after every failure, which made the second run fail on
# the first run's work. Clearing the names first keeps it re-runnable.
rm -f "${build_directory}"/usr/bin/{vim,vimdiff,evim,eview,ex,view,rvim,rview,vimtutor,xxd,vi}

make DESTDIR="${build_directory}" install

# vi is what fifty years of muscle memory types. -f so re-running this does
# not fail on the link it made last time.
ln -sfv vim "${build_directory}/usr/bin/vi"

for page in "${build_directory}"/usr/share/man/man1/vim.1 \
            "${build_directory}"/usr/share/man/*/man1/vim.1; do
  [ -e "${page}" ] && ln -sfv vim.1 "$(dirname "${page}")/vi.1"
done

# Puts the documentation where every other package keeps it
ln -sfnv "../vim/${runtime}/doc" \
         "${build_directory}/usr/share/doc/vim-${version}"

# The system vimrc, from the book. Only written if it is not already there,
# so an edited one survives a rebuild of this package.
if [ ! -f "${build_directory}/etc/vimrc" ]; then
  mkdir -p "${build_directory}/etc"
  cat > "${build_directory}/etc/vimrc" << "EOF"
" Begin /etc/vimrc

" Ensure defaults are set before customizing settings, not after
source $VIMRUNTIME/defaults.vim
let skip_defaults_vim=1

set nocompatible
set backspace=2
set mouse=
syntax on
if (&term == "xterm") || (&term == "putty")
  set background=dark
endif

" End /etc/vimrc
EOF
fi
