/* pdaemon - starts the system daemons and keeps them started.
 *
 * They used to be started from init_os, which is a login profile script that
 * runs on tty1. That had four consequences, and each was patched separately
 * over time:
 *
 *   - they only started if somebody logged in on tty1;
 *   - they were children of that login shell;
 *   - init_os runs again whenever the tty1 shell comes back, so every daemon
 *     needed an "is one already running?" guard, and seatd went without one
 *     for months because nobody noticed it was missing;
 *   - nothing restarted them if they died.
 *
 * The guards were the tell. They existed to paper over the script being run
 * more than once, and they answered the question by asking pgrep whether a
 * process with a matching name existed -- which is a guess about somebody
 * else's process. A supervisor does not guess: it forked the child, so it
 * has the pid, and it is told when the pid dies.
 *
 * pinit starts this and restarts it if it exits, which is the same
 * arrangement pinit already has with the gettys. The respawn limit below is
 * pinit's, for the same reason: a daemon that dies instantly and is restarted
 * forever is a busy loop that hides its own cause. */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>

#include "daemons.h"

#define LOG_DIRECTORY  "/var/log"

/* Five starts in ten seconds is the point at which restarting has stopped
   being a recovery and become a loop. Same numbers as pinit's gettys. */
#define RESPAWN_LIMIT  5
#define RESPAWN_WINDOW 10

/* The fallback wakeup, for a SIGCHLD that arrived while another signal was
   being handled. */
#define TIMEO 30

static sigset_t set_of_signals;

static pid_t daemon_pid[DAEMON_COUNT];
static time_t daemon_window_start[DAEMON_COUNT];
static int    daemon_starts[DAEMON_COUNT];
static int    daemon_given_up[DAEMON_COUNT];

static int shutting_down = 0;

static void report_error(const char *action, const char *object,
                         int error_number){
  fprintf(stderr, "pdaemon: %s %s: %s\n", action, object,
          strerror(error_number));
}

/* Run a command to completion. Used for the setup step, which has to finish
   before the daemon it belongs to starts. */
static int run_sync(char *const command[]){
  int status = 0;
  pid_t pid = fork();

  if(pid == 0){
    sigprocmask(SIG_UNBLOCK, &set_of_signals, NULL);
    execvp(command[0], command);
    _exit(127);
  }

  if(pid < 0)
    return -1;

  if(waitpid(pid, &status, 0) < 0 || !WIFEXITED(status))
    return -1;

  return WEXITSTATUS(status);
}

/* Keep one previous generation, which is the same thing init_os did with mv
   and the same reason: the boot whose log matters is usually the one that
   made you reboot.
 *
 * Called once per daemon when pdaemon starts, never on a respawn. A daemon
 * that is failing and being restarted would otherwise rotate away its own
 * first failure -- which is the interesting one -- on every retry. */
static void rotate_log(const char *name){
  char current[64];
  char previous[64];

  snprintf(current,  sizeof current,  LOG_DIRECTORY "/%s.log",   name);
  snprintf(previous, sizeof previous, LOG_DIRECTORY "/%s.log.1", name);

  if(access(current, F_OK) == 0 && rename(current, previous) != 0)
    report_error("rotate", current, errno);
}

/* stdout and stderr to the daemon's log, stdin from /dev/null.
 *
 * O_APPEND rather than O_TRUNC because rotate_log has already run: within one
 * boot a restarted daemon adds to the record instead of erasing what it said
 * the last time it died. */
static void redirect_output(const char *name){
  char path[64];
  int log_fd;
  int null_fd = open("/dev/null", O_RDONLY);

  if(null_fd >= 0){
    dup2(null_fd, STDIN_FILENO);
    if(null_fd > STDERR_FILENO)
      close(null_fd);
  }

  snprintf(path, sizeof path, LOG_DIRECTORY "/%s.log", name);

  log_fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);

  if(log_fd < 0)
    return;                       /* the console is a worse log than none */

  dup2(log_fd, STDOUT_FILENO);
  dup2(log_fd, STDERR_FILENO);

  if(log_fd > STDERR_FILENO)
    close(log_fd);
}

static void daemon_start(int index){
  const struct daemon *entry = &daemon_table[index];
  time_t now = time(NULL);
  pid_t pid;

  if(daemon_given_up[index])
    return;

  if(now - daemon_window_start[index] > RESPAWN_WINDOW){
    daemon_window_start[index] = now;
    daemon_starts[index] = 0;
  }

  if(daemon_starts[index] >= RESPAWN_LIMIT){
    report_error("respawning too fast, giving up on", entry->name, 0);
    daemon_given_up[index] = 1;
    return;
  }

  daemon_starts[index]++;

  if(entry->directory != NULL
     && mkdir(entry->directory, 0755) != 0 && errno != EEXIST)
    report_error("mkdir", entry->directory, errno);

  if(entry->setup != NULL && run_sync(entry->setup) != 0)
    report_error("setup failed for", entry->name, 0);

  pid = fork();

  if(pid < 0){
    report_error("fork", entry->name, errno);
    return;
  }

  if(pid == 0){
    sigprocmask(SIG_UNBLOCK, &set_of_signals, NULL);
    redirect_output(entry->name);
    execvp(entry->command[0], entry->command);

    /* Nothing above this can be reported: stderr is the log file now, which
       is exactly where a failure to exec should be recorded. */
    fprintf(stderr, "pdaemon: exec %s: %s\n",
            entry->command[0], strerror(errno));
    _exit(127);
  }

  daemon_pid[index] = pid;
}

/* Which entry died, if it was one of ours. Anything else reaped here is a
   setup command or a process orphaned onto us, and is simply collected. */
static void daemon_replace(pid_t pid){
  int index;

  for(index = 0; index < DAEMON_COUNT; index++)
    if(daemon_pid[index] == pid){
      daemon_pid[index] = 0;
      daemon_start(index);
      return;
    }
}

static void signal_reap(void){
  pid_t pid;

  while((pid = waitpid(-1, NULL, WNOHANG)) > 0)
    if(!shutting_down)
      daemon_replace(pid);
}

/* SIGTERM to each, a moment to exit, then SIGKILL. pinit sends the same two
   signals to everything at shutdown; doing it here first means the daemons
   are asked in the order that is the reverse of how they were started, so
   iwd releases the bus before dbus goes. */
static void shutdown_daemons(void){
  struct timespec pause = {0, 100 * 1000 * 1000};   /* 0.1s */
  int index;
  int waited;

  shutting_down = 1;

  for(index = DAEMON_COUNT - 1; index >= 0; index--)
    if(daemon_pid[index] > 0)
      kill(daemon_pid[index], SIGTERM);

  for(waited = 0; waited < 50; waited++){
    int remaining = 0;

    while(waitpid(-1, NULL, WNOHANG) > 0)
      ;

    for(index = 0; index < DAEMON_COUNT; index++)
      if(daemon_pid[index] > 0 && kill(daemon_pid[index], 0) == 0)
        remaining++;

    if(remaining == 0)
      return;

    nanosleep(&pause, NULL);
  }

  for(index = 0; index < DAEMON_COUNT; index++)
    if(daemon_pid[index] > 0)
      kill(daemon_pid[index], SIGKILL);
}

int main(void){
  int signal_number;
  int index;

  /* Blocked and collected with sigwait, so there are no handlers running
     between instructions and no restarted syscalls. pinit does the same. */
  sigfillset(&set_of_signals);
  sigprocmask(SIG_BLOCK, &set_of_signals, NULL);

  for(index = 0; index < DAEMON_COUNT; index++){
    rotate_log(daemon_table[index].name);
    daemon_window_start[index] = time(NULL);
    daemon_start(index);
  }

  while(1){
    alarm(TIMEO);
    sigwait(&set_of_signals, &signal_number);

    switch(signal_number){
      case SIGCHLD:
      case SIGALRM:
        signal_reap();
        break;

      case SIGTERM:
      case SIGINT:
        shutdown_daemons();
        return 0;

      default:
        break;
    }
  }

  return 0;
}
