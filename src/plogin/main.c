#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/resource.h>

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
  putenv("SHELL=/bin/bash");
  putenv("USER=root");
  putenv("PATH=/usr/bin:/usr/sbin");
  chdir("/root");
  setuid(0);

  printf("plogin\n");

  execl("/bin/bash", "-bash", "-l", (char*)NULL);

  return 0;
}
