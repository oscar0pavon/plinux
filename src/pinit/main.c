#include "programs.h"
#include <stdio.h>

#define TIMEO	30

sigset_t set_of_signals;

FILE* boot_time; 
clock_t init_time; 

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

/* The ip commands are ordered: the address has to exist before the route and
   the link that use it. The whole sequence runs in one child so PID 1 never
   blocks waiting for the network. */
static void network_setup(void){
  if(fork() != 0)
    return;

  sigprocmask(SIG_UNBLOCK, &set_of_signals, NULL);
  setsid();

  run_sync(ip_addr_lo_command);
  run_sync(ip_lo_up);

  run_sync(ip_set_up_command);
  run_sync(wpa_command);            /* -B, daemonises itself */
  run_sync(ip_addr_command);
  run_sync(ip_route_command);

  _exit(0);
}

static void launch_program(char* const command[]){
  int result;

  if(fork() == 0){
		sigprocmask(SIG_UNBLOCK, &set_of_signals, NULL);
		setsid();
		result = execvp(command[0], command);
    if(result == -1){
      printf("Can't execvp %s\n",command[0]);
    }
		perror("execvp");
  }
}

static void launch_getty(const char* getty_exec,char* const arguments[]){
  int result;

  if(fork() == 0){
		sigprocmask(SIG_UNBLOCK, &set_of_signals, NULL);
		setsid();
		result = execvp(getty_exec, arguments);
    if(result == -1){
      printf("Can't execvp %s\n",mingetty1[0]);
    }
		perror("execvp");
  }
}


struct MountCommand{
  char * const *arguments;
  unsigned long int mode; 
};

void* mount_threaded(void*command_line){
  struct MountCommand* mount_command = (struct MountCommand*)command_line;

  char* const* command = (char* const *)(mount_command->arguments);

  mount(command[0], command[1], command[2],
      mount_command->mode,NULL);

  return NULL;
}

static void mount_now(char* const command[], unsigned long int mode){
  mount(command[0], command[1], command[2], mode, NULL);
}

/* Only block devices are worth a thread: their superblock read and journal
   recovery run outside namespace_sem, so they genuinely overlap (~6ms each).
   Pseudo-filesystems cost ~12us and serialise on that lock anyway.
   These are static so they outlive initialize()'s frame. */
static struct MountCommand block_mounts[] = {
  {.arguments = mount_boot_commnad,  .mode = 0},
  {.arguments = mount_disk_commnad,  .mode = 0},
  {.arguments = mount_disk2_commnad, .mode = 0},
};

#define BLOCK_MOUNT_COUNT (sizeof(block_mounts)/sizeof(block_mounts[0]))


static void signal_reap(void)
{
	while (waitpid(-1, NULL, WNOHANG) > 0)
		;
	alarm(TIMEO);
}

void initialize(){

  pthread_t block_thread[BLOCK_MOUNT_COUNT];

  /* The kernel already mounted devtmpfs on /dev (CONFIG_DEVTMPFS_MOUNT=y), so
     the device nodes are here. Start the slow mounts first, then do everything
     else while their I/O is in flight. */
  for(size_t i = 0; i < BLOCK_MOUNT_COUNT; i++)
    pthread_create(&block_thread[i], NULL, mount_threaded, &block_mounts[i]);

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

  network_setup();

  //swapon("/dev/nvme0n1p4", SWAP_FLAG_DISCARD);

  launch_getty(mingetty1[0],mingetty1);
  launch_getty(mingetty2[0],mingetty2);
  launch_getty(gettyS0[0],gettyS0);

  //launch_program(pulseaudio);

  for(size_t i = 0; i < BLOCK_MOUNT_COUNT; i++)
    pthread_join(block_thread[i], NULL);

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
