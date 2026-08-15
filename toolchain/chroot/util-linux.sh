#!/bin/bash
#
# LFS 7.12. Util-linux-2.41.1, the temporary one.
#
# This is the step that breaks the util-linux/udev cycle, and it is worth
# saying so plainly because packages/util-linux.sh currently carries a
# --without-udev that exists only because the native build has no equivalent.
#
# udev links libblkid and libmount, so udev must be built after util-linux.
# But lsblk and findmnt read device properties through libudev, so util-linux
# wants to be built after udev. The book's answer is to build util-linux
# twice: this stripped copy now, and the real one at 8.79, three sections
# after udev at 8.76 -- by which time libudev genuinely exists and 8.79 does
# not need to say --without-udev at all.

set -e

source /toolchain/common.sh

directory=$(unpack 'util-linux-*.tar.xz' 'util-linux-2.41.1')
cd "${directory}"

# The FHS wants the hardware clock's drift file under /var/lib/hwclock rather
# than in /etc. The directory has to exist before the build names it.
mkdir -pv /var/lib/hwclock

# The --disable options name things that need packages not built yet, or that
# plinux replaces outright: login is plogin's job, and chfn, chsh, su and
# runuser all want PAM, which this system does not have.
#
# ADJTIME_PATH matches the directory above. The book notes it is not strictly
# needed for a temporary tool but sets it anyway, so that this build does not
# leave a file somewhere the chapter 8 build will not overwrite or remove.
./configure --libdir=/usr/lib     \
            --runstatedir=/run    \
            --disable-chfn-chsh   \
            --disable-login       \
            --disable-nologin     \
            --disable-su          \
            --disable-setpriv     \
            --disable-runuser     \
            --disable-pylibmount  \
            --disable-static      \
            --disable-liblastlog2 \
            --without-python      \
            ADJTIME_PATH=/var/lib/hwclock/adjtime \
            --docdir=/usr/share/doc/util-linux-2.41.1

make

make install
