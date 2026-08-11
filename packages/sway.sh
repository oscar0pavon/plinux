#!/bin/bash
#
# sway - the compositor.
#
# The last package. i3's window management on wlroots: workspaces, tiling,
# the config file, and the IPC that swaymsg drives.
#
# sys/root/shell_config.sh and sys/scripts/init_os have been written for this
# for months -- init_os runs "dbus-run-session sway" if sway is present and
# says so on the console if it is not. This is the first image where that
# branch is taken.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

export CC=gcc
export CXX=g++

directory=$(unpack 'sway-*.tar.gz' 'sway-1.11')
cd "${directory}"

# -Dtray=disabled: the system tray talks StatusNotifierItem over D-Bus, and
# sway implements that against sd-bus or basu. There is a dbus-daemon in this
# image but neither of those libraries, and a tray with nothing to put in it
# is not worth the dependency.
#
# -Dgdk-pixbuf=disabled: swaybg uses it to load wallpapers in formats other
# than PNG. cairo reads PNG on its own, which is enough, and gdk-pixbuf brings
# the rest of GTK's image loaders with it.
#
# -Dman-pages=disabled needs scdoc, and nothing in this image can read a man
# page yet.
#
# -Ddefault-wallpaper=false drops the bundled backgrounds, which are PNGs of
# the sway logo at every common resolution.
meson_setup build                \
      --sysconfdir=/etc          \
      -Dtray=disabled            \
      -Dgdk-pixbuf=disabled      \
      -Dman-pages=disabled       \
      -Ddefault-wallpaper=false  \
      -Dswaybar=true             \
      -Dswaynag=true             \
      -Dzsh-completions=false    \
      -Dbash-completions=false   \
      -Dfish-completions=false

ninja -C build

DESTDIR="${build_directory}" ninja -C build install
