#!/bin/bash
#
# udev - device node creation and management.
#
# LFS 12.4 section 8.76. udev is part of systemd; only the udev targets are
# built out of that tree, which is why the install below is a list of explicit
# copies rather than "ninja install".
#
# This is the reason glibc is in the image at all: systemd does not build
# against musl.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'systemd-*.tar.gz' 'systemd-257.8')
cd "${directory}"

export CC=gcc

# render and sgx are not groups this system has
sed -e 's/GROUP="render"/GROUP="video"/' \
    -e 's/GROUP="sgx", //'               \
    -i rules.d/50-udev-default.rules.in

# drop the one rule that needs a full systemd
sed -i '/systemd-sysctl/s/^/#/' rules.d/99-systemd.rules.in

# a standalone udev keeps its network configuration under /usr/lib/udev
sed -e '/NETWORK_DIRS/s/systemd/udev/' \
    -i src/libsystemd/sd-network/network-util.h

mkdir -p build
cd build

# link-udev-shared=false keeps udev out of libsystemd-shared, which exists to
# be shared between systemd components none of which are installed here.
# logind and vconsole belong to those other components.
meson setup ..                  \
      --prefix=/usr             \
      --buildtype=release       \
      -D mode=release           \
      -D dev-kvm-mode=0660      \
      -D link-udev-shared=false \
      -D logind=false           \
      -D vconsole=false

# the helper programs udev invokes, taken from its own build definition
udev_helpers=$(grep "'name' :" ../src/udev/meson.build | \
               awk '{print $3}' | tr -d ",'" | grep -v 'udevadm')

# only the udev targets, not the rest of systemd
ninja udevadm systemd-hwdb                                           \
      $(ninja -n | grep -Eo '(src/(lib)?udev|rules.d|hwdb.d)/[^ ]*') \
      $(realpath libudev.so --relative-to .)                         \
      ${udev_helpers}

# Installed by hand because only a subset was built. Every path is prefixed
# with the staging directory; the book writes to / because it runs in a
# chroot where / already is the target.
d=${build_directory}

install -vm755 -d ${d}/usr/lib/udev/{hwdb.d,rules.d,network}
install -vm755 -d ${d}/etc/udev/{hwdb.d,rules.d,network}
install -vm755 -d ${d}/usr/{lib,share}/pkgconfig
install -vm755 -d ${d}/usr/{bin,sbin,include}

install -vm755 udevadm                       ${d}/usr/bin/
install -vm755 systemd-hwdb                  ${d}/usr/bin/udev-hwdb
ln      -svfn ../bin/udevadm                 ${d}/usr/sbin/udevd
cp      -av    libudev.so{,*[0-9]}           ${d}/usr/lib/
install -vm644 ../src/libudev/libudev.h      ${d}/usr/include/
install -vm644 src/libudev/*.pc              ${d}/usr/lib/pkgconfig/
install -vm644 src/udev/*.pc                 ${d}/usr/share/pkgconfig/
install -vm644 ../src/udev/udev.conf         ${d}/etc/udev/
install -vm644 rules.d/* ../rules.d/README   ${d}/usr/lib/udev/rules.d/
install -vm644 $(find ../rules.d/*.rules \
                 -not -name '*power-switch*') ${d}/usr/lib/udev/rules.d/
install -vm644 hwdb.d/* ../hwdb.d/{*.hwdb,README} ${d}/usr/lib/udev/hwdb.d/
install -vm755 ${udev_helpers}               ${d}/usr/lib/udev
install -vm644 ../network/99-default.link    ${d}/usr/lib/udev/network

# The book also installs man pages and the udev-lfs rules here. Man pages are
# skipped; the hwdb binary database is built on the target by "udev-hwdb
# update", since it has to be generated where the files live.
