
#include <unistd.h>
#include <time.h>
//#define _XOPEN_SOURCE 200809L
#include <signal.h>
#include <sys/wait.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/swap.h>

#include <sys/reboot.h>

/* loopback, configured with SIOCSIF* rather than by running ip(8) */
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>

#include <string.h>

#include <stdlib.h>
#include <sys/types.h>
#include <stdbool.h>

#define	LINUX_REBOOT_CMD_RESTART	0x01234567
#define	LINUX_REBOOT_CMD_POWER_OFF	0x4321FEDC

int symlink(const char *target, const char *linkpath);

static char * const mount_sys_commnad[] = {"sysfs","/sys", "sysfs"};
static char * const mount_proc_commnad[] = {"proc","/proc", "proc"};
static char * const mount_dev_commnad[] = {"dev","/dev", "devtmpfs"};
static char * const mount_pts_commnad[] = {"devpts","/dev/pts", "devpts"};

static char * const mount_efivars_commnad[] = {"efivarfs","/sys/firmware/efi/efivars", "efivarfs"};

static char * const mount_shm_commnad[] = {"tmpfs","/dev/shm", "tmpfs"};

static char * const mount_run_commnad[] = {"tmpfs","/run", "tmpfs"};

/* The block devices come from /etc/fstab rather than from this file, so one
   pinit boots both the workstation and the VM image. -F forks per device, so
   filesystems on different drives mount in parallel while filesystems on the
   same drive stay in fstab order. libmount needs /proc, which is mounted
   before this runs. */
static char * const mount_all_command[] = {"/bin/mount","-a","-F", NULL};

/* swap likewise: "swap" lines in the same fstab */
static char * const swapon_all_command[] = {"/sbin/swapon","-a", NULL};

/* Shutdown, and the same argument as mounting: umount(8) already reads the
   mount table in the right order. -r remounts anything it cannot unmount
   read-only, which includes the root filesystem it is running from. */
static char * const umount_all_command[]  = {"/bin/umount","-a","-r", NULL};
static char * const swapoff_all_command[] = {"/sbin/swapoff","-a", NULL};

/* pgetty takes the tty as argv[1]; it parses no options */
static char * const mingetty1[] = {"/bin/pgetty", "tty1",NULL};

static char * const mingetty2[] = {"/bin/pgetty", "tty2",NULL};

/* serial console; matches console=ttyS0 in the kernel parameters */
static char * const gettyS0[] = {"/bin/pgetty", "ttyS0",NULL};

/* A getty exits every time someone logs out, and until it is started again
   that terminal is gone for the rest of the boot. Keeping the list here lets
   main.c match a dead child against the getty it was and start another. */
static char * const * const getty_table[] = {mingetty1, mingetty2, gettyS0};

#define GETTY_COUNT (sizeof(getty_table) / sizeof(getty_table[0]))

static char * const pulseaudio[] = {"/bin/pulseaudio",NULL};


static char * const udev_script[] = {"/udev.sh",NULL};



/* No network commands here any more. Loopback is set with ioctls in main.c,
   and iwd configures the wireless interface itself over rtnetlink. */

