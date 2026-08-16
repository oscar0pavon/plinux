#!/bin/bash
#
# LFS 7.5 and 7.6: the rest of the directory tree, and the files that have to
# exist before anything else works.
#
# Chapters 5 and 6 needed only usr/{bin,lib,sbin} and the symlinks onto them.
# This is the full FHS layout, created from inside, where "/" means lfs/.

set -e

source /toolchain/common.sh

# LFS 7.5. All of it is mkdir -p and install -d, so re-running is free.
mkdir -pv /{boot,home,mnt,opt,srv}

mkdir -pv /etc/{opt,sysconfig}
mkdir -pv /lib/firmware
mkdir -pv /media/{floppy,cdrom}
mkdir -pv /usr/{,local/}{include,src}
mkdir -pv /usr/lib/locale
mkdir -pv /usr/local/{bin,lib,sbin}
mkdir -pv /usr/{,local/}share/{color,dict,doc,info,locale,man}
mkdir -pv /usr/{,local/}share/{misc,terminfo,zoneinfo}
mkdir -pv /usr/{,local/}share/man/man{1..8}
mkdir -pv /var/{cache,local,log,mail,opt,spool}
mkdir -pv /var/lib/{color,misc,locate}

ln -sfv /run /var/run
ln -sfv /run/lock /var/lock

# 0750 on /root so it is not world-readable, 1777 on the temporary directories
# so anyone can write but only the owner can delete.
install -dv -m 0750 /root
install -dv -m 1777 /tmp /var/tmp

# The book is emphatic that /usr/lib64 must not exist -- the toolchain was
# configured on the assumption that it does not, and BLFS instructions break
# if it appears. It is easy to create by accident, so it is checked here
# rather than left to be noticed later.
if [ -d /usr/lib64 ] && [ ! -L /usr/lib64 ]; then
  echo "/usr/lib64 exists as a real directory; LFS requires that it not" >&2
  echo "something installed there; find it before continuing" >&2
  exit 1
fi

# LFS 7.6. The kernel keeps the mount list itself and exposes it through
# /proc; this symlink is for programs that still look for /etc/mtab.
ln -sfv /proc/self/mounts /etc/mtab

# Referenced by some test suites and by one of perl's configuration files.
cat > /etc/hosts << EOF
127.0.0.1 localhost $(hostname)
::1        localhost
EOF

# Without these, root has no name and bash prompts with "I have no name!".
#
# This is the book's list rather than plinux's. sys/etc/passwd carries two
# entries -- root and messagebus -- because that is all the finished image
# needs, and it is installed over this by build.sh at the end of a normal
# build. The extra accounts here exist for chapter 8's test suites, which
# expect daemon, nobody and a regular user to resolve.
cat > /etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF

# GID 5 is tty, which is what build.sh's devpts mount names in gid=5, and
# GID 97 is wheel. The rest are the conventional numbers udev's rules expect,
# and udev names eleven of them by hand -- audio, cdrom, dialout, disk, input,
# kmem, kvm, lp, tape, tty, video -- so a device node gets the right group
# rather than root.
#
# netdev:98 is the one addition to the book's list, and it is here because
# iwd installs /usr/share/dbus-1/system.d/iwd-dbus.conf, which opens with
# <policy group="netdev">. Without the group, dbus starts anyway and says so
# in /var/log/dbus.log:
#
#   Unknown group "netdev" in message bus configuration file
#
# and the policy it describes is silently not applied. It used to come from
# sys/etc/group, which was deleted because staging it over this file threw
# away all eleven of udev's -- so the number moved here rather than being
# lost with the file it arrived in.
cat > /etc/group << "EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
mail:x:34:
kvm:x:61:
uuidd:x:80:
wheel:x:97:
users:x:999:
nogroup:x:65534:
netdev:x:98:
EOF

# A regular user for the chapter 8 test suites, which refuse to run several
# things as root. The book deletes this account at the end of chapter 8.
if ! grep -q '^tester:' /etc/passwd; then
  echo "tester:x:101:101::/home/tester:/bin/bash" >> /etc/passwd
  echo "tester:x:101:" >> /etc/group
fi
install -o tester -d /home/tester

# login, agetty and init only write these if they already exist.
touch /var/log/{btmp,lastlog,faillog,wtmp}
chgrp -v utmp /var/log/lastlog
chmod -v 664  /var/log/lastlog
chmod -v 600  /var/log/btmp

# The book's next instruction is "exec /usr/bin/bash --login", to pick up the
# passwd file that now exists. That matters for an interactive session and not
# for this one: each step here is a fresh chroot invocation, so the next one
# starts with a shell that already resolves root by name.
echo "layout: /etc/passwd, /etc/group and the directory tree are in place"
