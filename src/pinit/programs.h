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
 * A filesystem is {source, target, type} and is passed to mount(2) directly.
 * A command is an argv, NULL terminated, and is passed to execvp(3). */

static char * const proc_filesystem[]    = {"proc",     "/proc",    "proc"};
static char * const sysfs_filesystem[]   = {"sysfs",    "/sys",     "sysfs"};
static char * const dev_filesystem[]     = {"dev",      "/dev",     "devtmpfs"};
static char * const run_filesystem[]     = {"tmpfs",    "/run",     "tmpfs"};
static char * const pts_filesystem[]     = {"devpts",   "/dev/pts", "devpts"};
static char * const shm_filesystem[]     = {"tmpfs",    "/dev/shm", "tmpfs"};
static char * const efivars_filesystem[] = {"efivarfs",
                                            "/sys/firmware/efi/efivars",
                                            "efivarfs"};

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
