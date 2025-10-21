#include <stdlib.h>
#include <unistd.h>

int main(){
  putenv("HOME=/root");
  putenv("SHELL=/bin/bash");
  putenv("USER=root");
  putenv("PATH=/usr/bin:/usr/sbin");
  chdir("/root");
  setuid(0);
  setgid(0);
  execl("/bin/bash", "-bash", "-l", (char*)NULL);
  return 0;
}
