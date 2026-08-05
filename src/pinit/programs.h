
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

/* pgetty takes the tty as argv[1]; it parses no options */
static char * const mingetty1[] = {"/bin/pgetty", "tty1",NULL};

static char * const mingetty2[] = {"/bin/pgetty", "tty2",NULL};

/* serial console; matches console=ttyS0 in the kernel parameters */
static char * const gettyS0[] = {"/bin/pgetty", "ttyS0",NULL};

static char * const pulseaudio[] = {"/bin/pulseaudio",NULL};


static char * const udev_script[] = {"/udev.sh",NULL};



/* Only loopback. The wireless interface does not exist yet when pinit runs:
   the driver and its firmware finish around 1.7s, well after this point, so
   configuring wlan0 here never took effect. iwd is what brings it up now, and
   it owns the interface — a second supplicant or a manual address only fights
   it. lo is different: it always exists, so this always works. */
static char * const ip_addr_lo_command[] = {"/sbin/ip","addr", "add" ,
  "127.0.0.1/8", "label", "lo", 
  "dev","lo", NULL};

static char* const ip_lo_up[] = {"/sbin/ip","link", 
  "set", "lo", "up",  NULL};

