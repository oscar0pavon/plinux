#include "programs.h"
#include <stdio.h>
#include <errno.h>

#define TIMEO	30

sigset_t set_of_signals;

FILE* boot_time;
clock_t init_time;

/* write(2) rather than fprintf: this is also called from freshly forked
   children, where stdio's lock may be held by whoever forked them. */
static void report_error(const char *action, const char *object, int error_number){
  char message[256];
  int length = snprintf(message, sizeof(message), "pinit: %s %s: %s\n",
                        action, object, strerror(error_number));

  if(length > 0)
    write(STDERR_FILENO, message, (size_t)length);
}

/* Run a command to completion. Used where the next step depends on this one
   having finished; fork+exec is already concurrent, so everything else just
   gets launched and left alone. */
static void run_sync(char* const command[]){
  pid_t pid = fork();

  if(pid == 0){
    sigprocmask(SIG_UNBLOCK, &set_of_signals, NULL);
    execvp(command[0], command);
    _exit(127);
  }

  if(pid > 0)
    waitpid(pid, NULL, 0);
}

/* Loopback, configured here rather than by running ip(8) twice.

   This is the only interface pinit touches. wlan0 does not exist this early
   -- the wireless firmware finishes around 1.7s -- and iwd owns it once it
   does, setting the address over rtnetlink itself. So iproute2 was being
   carried for 127.0.0.1 and nothing else.

   The SIOCSIF* ioctls are enough for a single IPv4 address and predate
   netlink by a decade; they are still the shortest path to a loopback that
   works. Two forks, two execs and a package dependency for three ioctls. */
static void loopback_setup(void){
  int socket_handle = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
  struct ifreq request;
  struct sockaddr_in *address = (struct sockaddr_in *)&request.ifr_addr;

  if(socket_handle < 0){
    report_error("socket", "lo", errno);
    return;
  }

  memset(&request, 0, sizeof(request));
  strcpy(request.ifr_name, "lo");

  address->sin_family = AF_INET;
  address->sin_addr.s_addr = htonl(INADDR_LOOPBACK);   /* 127.0.0.1 */

  if(ioctl(socket_handle, SIOCSIFADDR, &request) < 0)
    report_error("SIOCSIFADDR", "lo", errno);

  address->sin_addr.s_addr = htonl(0xFF000000);        /* /8 */

  if(ioctl(socket_handle, SIOCSIFNETMASK, &request) < 0)
    report_error("SIOCSIFNETMASK", "lo", errno);

  /* Read the flags back before setting them: the kernel already has
     IFF_LOOPBACK on this interface and writing a hand-built set would clear
     whatever else it has decided belongs there. */
  if(ioctl(socket_handle, SIOCGIFFLAGS, &request) < 0){
    report_error("SIOCGIFFLAGS", "lo", errno);
  } else {
    request.ifr_flags |= IFF_UP | IFF_RUNNING;

    if(ioctl(socket_handle, SIOCSIFFLAGS, &request) < 0)
      report_error("SIOCSIFFLAGS", "lo", errno);
  }

  close(socket_handle);
}

/* The block devices and swap live in /etc/fstab, and mount(8) already knows
   how to read it: option parsing, mount order for nested targets, and with -F
   one process per device so separate drives overlap. Running it here instead
   of reimplementing it keeps the machine-specific configuration out of this
   binary entirely.

   Forked and not waited for, so the mounts proceed while the gettys start. */
static void storage_setup(void){
  if(fork() != 0)
    return;

  sigprocmask(SIG_UNBLOCK, &set_of_signals, NULL);
  setsid();

  run_sync(mount_all_command);
  run_sync(swapon_all_command);

  _exit(0);
}

/* execvp only returns on failure, and the child must not carry on running
   initialize() when it does: it would fork more children, and rejoin the
   signal loop as a second process believing it is init. */
static void launch_program(char* const command[]){
  if(fork() == 0){
		sigprocmask(SIG_UNBLOCK, &set_of_signals, NULL);
		setsid();
		execvp(command[0], command);
    report_error("execvp", command[0], errno);
    _exit(127);
  }
}

static void launch_getty(const char* getty_exec,char* const arguments[]){
  if(fork() == 0){
		sigprocmask(SIG_UNBLOCK, &set_of_signals, NULL);
		setsid();
		execvp(getty_exec, arguments);
    report_error("execvp", getty_exec, errno);
    _exit(127);
  }
}

/* Failures used to be silent, which is how two mounts pointing at devices
   that no longer existed went unnoticed.

   EBUSY is not one: it means the filesystem is already there. The kernel
   mounts devtmpfs itself when CONFIG_DEVTMPFS_MOUNT is set, and the call
   below is kept only for kernels built without it. */
static void mount_now(char* const command[], unsigned long int mode){
  if(mount(command[0], command[1], command[2], mode, NULL) != 0 && errno != EBUSY)
    report_error("mount", command[1], errno);
}


static void signal_reap(void)
{
	while (waitpid(-1, NULL, WNOHANG) > 0)
		;
	alarm(TIMEO);
}

void initialize(){

  /* These stay compiled in. They are the same on every machine, they have an
     order fstab cannot express, and keeping them here means a missing or
     broken /etc/fstab still leaves a usable system. /proc comes first because
     libmount reads it, and mount(8) runs from storage_setup() below.

     The kernel already mounted devtmpfs on /dev (CONFIG_DEVTMPFS_MOUNT=y). */
  mount_now(mount_proc_commnad, MS_NOSUID | MS_NOEXEC | MS_NODEV);
  mount_now(mount_sys_commnad,  MS_NOSUID | MS_NOEXEC | MS_NODEV);
  mount_now(mount_dev_commnad,  MS_NOSUID);
  mount_now(mount_run_commnad,  0);

  mount_now(mount_efivars_commnad, 0);          /* needs /sys */

  mkdir("/dev/pts", S_IRWXU | S_IRWXG | S_IRWXO);
  mkdir("/dev/shm", S_IRWXU | S_IRWXG | S_IRWXO);

  mount_now(mount_pts_commnad, 0);
  mount_now(mount_shm_commnad, MS_NOSUID | MS_NODEV);

  symlink("/proc/self/fd/0","/dev/stdin");
  symlink("/proc/self/fd/1","/dev/stdout");
  symlink("/proc/self/fd/2","/dev/stderr");
  symlink("/proc/self/fd","/dev/fd");

  //launch_program(udev_script);

  storage_setup();

  loopback_setup();

  launch_getty(mingetty1[0],mingetty1);
  launch_getty(mingetty2[0],mingetty2);
  launch_getty(gettyS0[0],gettyS0);

  //launch_program(pulseaudio);

  //timing..
  init_time = clock() - init_time;
  double time_taken = ((double)init_time)/CLOCKS_PER_SEC;

  fprintf(boot_time,"init config time = %f seconds\n",time_taken);

  fclose(boot_time);
}

void reboot_system(){
  sync();
  reboot(LINUX_REBOOT_CMD_RESTART);
}

void poweroff_system(){
  sync();
  reboot(LINUX_REBOOT_CMD_POWER_OFF);
}

int main(){
  printf("pboot!\n");
  
  boot_time = fopen("boot_time","w");
  if(!boot_time){
    printf("Can't create boot file\n");
  }
  
 init_time = clock();

  if(getpid() != 1){
    printf("Need to be PID 1\n");
    _exit(1);
  }

  chdir("/");

  sigfillset(&set_of_signals);
  sigprocmask(SIG_BLOCK, &set_of_signals, NULL);
  
  initialize();
  
  int signal;

  while(1){
    alarm(30) ;
    sigwait(&set_of_signals,&signal);
    if(signal == SIGCHLD || signal == SIGALRM){
      signal_reap();
    }
    if(signal == SIGINT){
      printf("reboot!!!!!!\n");
      reboot_system();
    }
    if(signal == SIGUSR2){
      printf("poweroff!!!!!!\n");
      poweroff_system();
    }
    
  }

  return 0;
}
