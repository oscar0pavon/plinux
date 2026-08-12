#ifndef PDAEMON_DAEMONS_H
#define PDAEMON_DAEMONS_H

/* for NULL, so this header stands on its own rather than relying on whatever
   main.c happened to include before it */
#include <stddef.h>

/* The daemons pdaemon supervises, in start order.
 *
 * Each one is:
 *
 *   name       what the log file is called, /var/log/<name>.log
 *   directory  created before starting, or NULL. /run is a fresh tmpfs every
 *              boot, so anything wanting a socket directory under it has to
 *              say so here; nothing else will have made it
 *   setup      one command run to completion first, or NULL
 *   command    the daemon itself, and it must not fork
 *
 * That last point is the whole reason this program exists. udevd was started
 * with --daemon and dbus-daemon with neither --fork nor --nofork, which means
 * both detached and left no child to watch. Nothing could supervise them, so
 * "is it running?" had to be answered by asking pgrep whether a process with
 * a matching *name* existed -- a guess, made three separate times in two
 * shell scripts, each of which had to be fixed separately when it turned out
 * seatd had no such guard at all.
 *
 * Run in the foreground they are ordinary children: pdaemon knows their pids,
 * knows when they die, and never has to guess. */

struct daemon {
  const char  *name;
  const char  *directory;
  char *const *setup;
  char *const *command;
};

/* udevd without --daemon. The coldplug pass that follows it stays in
   pdevices, which init_os still runs: it is three udevadm calls that exit,
   not a daemon, and it has to happen after the device nodes are wanted
   rather than at boot. */
static char *const udevd_command[]   = {"/sbin/udevd", NULL};

/* seatd already ran in the foreground -- init_os backgrounded it with & --
   so it needed no change. */
static char *const seatd_command[]   = {"seatd", NULL};

/* --nofork is the addition. Without it dbus-daemon forks and exits, which is
   what made the pid file in /run/dbus outlive it and produce "The pid file
   /run/dbus/pid exists" on the second run. --nopidfile because the pid file
   existed for the benefit of whoever had to find the process; pdaemon knows
   the pid.

   --nosyslog because a --system bus logs to syslog by default and there is no
   syslog daemon on this machine, so anything it had to say went nowhere. Its
   log stays empty either way -- dbus-daemon simply says nothing when it
   starts correctly -- but a failure now lands in the file instead of being
   addressed to a listener that does not exist. */
static char *const dbus_setup[]      = {"dbus-uuidgen",
                                        "--ensure=/etc/machine-id", NULL};
static char *const dbus_command[]    = {"dbus-daemon", "--system", "--nofork",
                                        "--nopidfile", "--nosyslog", NULL};

/* iwd, which set_ip used to exec. It needs the system bus, so it is last;
   ordering here is the whole of the dependency handling, and it is enough
   because there are four of them. */
static char *const iwd_command[]     = {"/usr/libexec/iwd", NULL};

static const struct daemon daemon_table[] = {
  {"udevd", NULL,        NULL,       udevd_command},
  {"seatd", NULL,        NULL,       seatd_command},
  {"dbus",  "/run/dbus", dbus_setup, dbus_command},
  {"iwd",   NULL,        NULL,       iwd_command},
};

#define DAEMON_COUNT ((int)(sizeof(daemon_table) / sizeof(daemon_table[0])))

#endif
