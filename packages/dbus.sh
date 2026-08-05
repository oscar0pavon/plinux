#!/bin/bash
#
# dbus - the message bus.
#
# Not an LFS package: the book builds no D-Bus at all, and mentions it only to
# create the messagebus user. This recipe therefore does not come from
# docs/LFS-BOOK-12.4.txt.
#
# Here because iwd refuses to start without a system bus -- it registers
# net.connman.iwd and exits with "Failed to initialize D-Bus" if it cannot --
# and because seatd and sway want one later.
#
# dbus 1.16 dropped autotools upstream: there is no ./configure in the
# tarball, only meson.build and CMakeLists.txt.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'dbus-*.tar.xz' 'dbus-1.16.2')
cd "${directory}"

# glibc, like the rest of the udev/iwd chain
export CC=gcc

mkdir -p build
cd build

# systemd and x11_autolaunch are disabled because neither exists here; without
# that, meson finds the host's and links against them.
#
# The socket paths are set explicitly rather than left to the localstatedir
# default, which would put the system socket under /var/run.
meson setup --prefix=/usr \
            --sysconfdir=/etc \
            --localstatedir=/var \
            .. \
            --buildtype=release \
            -D dbus_user=messagebus \
            -D message_bus=true \
            -D system_socket=/run/dbus/system_bus_socket \
            -D system_pid_file=/run/dbus/pid \
            -D session_socket_dir=/tmp \
            -D systemd=disabled \
            -D x11_autolaunch=disabled \
            -D modular_tests=disabled \
            -D doxygen_docs=disabled \
            -D ducktype_docs=disabled \
            -D xml_docs=disabled

ninja

DESTDIR="${build_directory}" ninja install

# dbus-daemon --system creates its socket here and drops to the messagebus
# user; the directory has to exist for either to work. pinit mounts a tmpfs on
# /run, so this is only the mount point.
mkdir -p "${build_directory}/run/dbus"
