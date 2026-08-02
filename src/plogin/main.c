#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/resource.h>

#define SHELL_PROGRAM "/bin/bash"

int main(){
  
  struct rlimit memlimit;
  memlimit.rlim_cur = RLIM_INFINITY; // Soft limit
  memlimit.rlim_max = RLIM_INFINITY; // Hard limit

  struct rlimit rtprio;
  rtprio.rlim_cur = 95; // Soft limit
  rtprio.rlim_max = 95; // Hard limit

  if (setrlimit(RLIMIT_MEMLOCK, &memlimit) != 0) {
      perror("Failed to set memlock");
  }
  if (setrlimit(RLIMIT_RTPRIO, &rtprio) != 0) {
      perror("Failed to set rtprio");
  }

  putenv("HOME=/root");
  putenv("SHELL=" SHELL_PROGRAM);
  putenv("USER=root");
  putenv("PATH=/usr/bin:/usr/sbin");
  chdir("/root");
  setuid(0);

  printf("plogin\n");
  fflush(stdout); /* execl would discard anything still buffered */

  execl(SHELL_PROGRAM, "-bash", "-l", (char*)NULL);

  /* only reached when execl failed */
  perror("plogin: can't exec " SHELL_PROGRAM);

  return 1;
}
