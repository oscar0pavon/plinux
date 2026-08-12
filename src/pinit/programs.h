#ifndef PINIT_PROGRAMS_H
#define PINIT_PROGRAMS_H

#include <unistd.h>
#include <time.h>
#include <signal.h>
#include <sys/wait.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/reboot.h>

/* loopback, configured with SIOCSIF* rather than by running ip(8) */
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>

/* Two shapes live here, and they are not interchangeable.
 *
 * A filesystem is {source, target, type, data} and is passed to mount(2)
 * directly. A command is an argv, NULL terminated, and is passed to
 * execvp(3).
 *
 * The fourth element is mount(2)'s data argument and was NULL for every
 * filesystem until /tmp needed one. Flags and data are not the same thing:
 * nosuid, nodev and noexec are flags, while size= and mode= are strings the
 * filesystem parses itself, and there is no flag that can express them. It
 * matters because /etc/fstab cannot supply them either -- pinit mounts these
 * before "mount -a" runs, and mount(8) skips a target that is already
 * mounted, so options written in fstab for any of these lines are read by
 * nobody. */

static char * const proc_filesystem[]    = {"proc",     "/proc",    "proc",    NULL};
static char * const sysfs_filesystem[]   = {"sysfs",    "/sys",     "sysfs",   NULL};
static char * const dev_filesystem[]     = {"dev",      "/dev",     "devtmpfs", NULL};
static char * const run_filesystem[]     = {"tmpfs",    "/run",     "tmpfs",   NULL};
static char * const pts_filesystem[]     = {"devpts",   "/dev/pts", "devpts",  NULL};
static char * const shm_filesystem[]     = {"tmpfs",    "/dev/shm", "tmpfs",   NULL};
static char * const efivars_filesystem[] = {"efivarfs",
                                            "/sys/firmware/efi/efivars",
                                            "efivarfs",
                                            NULL};

/* /tmp on a tmpfs, which is a change of behaviour and not just of location.
 *
 * It was part of the root filesystem, and nothing on this system has ever
 * cleaned it: no systemd-tmpfiles, no cron. The workstation's had reached
 * 7.3G across 487 entries, 438 of them untouched for over a month. A tmpfs
 * is empty after every boot because it never existed before it, so the
 * cleaning stops being a task that gets forgotten.
 *
 * It is also faster, and it stops a directory whose entire purpose is to be
 * thrown away from being written to an SSD -- both drives here are DRAM-less
 * controllers, which handle small sustained writes worst.
 *
 * And XDG_RUNTIME_DIR lives under it. The specification says that directory
 * must be cleared when the user logs out and must not survive a reboot; on
 * disk it survived both, which is the bug .bash_profile documents -- a
 * directory created once hid the fact that nothing was creating it.
 *
 * size=25% rather than the 50% default, because one pinit boots two machines:
 * 25% is about 7.8G on the 31G workstation and 2G in the 8G VM, and the
 * workstation has 32G of swap, so overflow degrades instead of failing.
 *
 * mode=1777 is the sticky bit. This is a single-user system where it guards
 * nothing, but /tmp with the wrong mode is the kind of difference that
 * surprises a program that checks.
 *
 * What must not move here is anything wanted after a crash. Blender autosaves
 * to TMPDIR -- 686M each on this machine -- and an autosave in RAM dies with
 * the machine, which is the case it exists for. Those belong in /var/tmp,
 * which FHS defines as the temporary directory that survives a reboot. */
static char * const tmp_filesystem[]     = {"tmpfs",    "/tmp",     "tmpfs",
                                            "mode=1777,size=25%"};

/* The block devices come from /etc/fstab rather than from this file, so one
   pinit boots both the workstation and the VM image. -F forks per device, so
   filesystems on different drives mount in parallel while filesystems on the
   same drive stay in fstab order. libmount needs /proc, which is mounted
   before this runs. */
static char * const mount_all_command[] = {"/bin/mount", "-a", "-F", NULL};

/* swap likewise: "swap" lines in the same fstab */
static char * const swapon_all_command[] = {"/sbin/swapon", "-a", NULL};

/* Shutdown, and the same argument as mounting: umount(8) already reads the
   mount table in the right order. -r remounts anything it cannot unmount
   read-only, which includes the root filesystem it is running from. */
static char * const umount_all_command[]  = {"/bin/umount", "-a", "-r", NULL};
static char * const swapoff_all_command[] = {"/sbin/swapoff", "-a", NULL};

/* pgetty takes the tty as argv[1]; it parses no options. ttyS0 is the serial
   console and matches console=ttyS0 in the kernel parameters. */
static char * const getty_tty1[]  = {"/bin/pgetty", "tty1",  NULL};
static char * const getty_tty2[]  = {"/bin/pgetty", "tty2",  NULL};
static char * const getty_ttyS0[] = {"/bin/pgetty", "ttyS0", NULL};

/* A getty exits every time a session ends -- including when sway quits, since
   .bash_profile starts it from the tty1 login shell -- and until one is
   started again that terminal is gone for the rest of the boot. Keeping the
   list here lets main.c match a dead child against the getty it was. */
static char * const * const getty_table[] = {getty_tty1, getty_tty2,
                                             getty_ttyS0};

#define GETTY_COUNT (sizeof(getty_table) / sizeof(getty_table[0]))

/* No network commands here any more. Loopback is set with ioctls in main.c,
   and iwd configures the wireless interface itself over rtnetlink. */

#endif
