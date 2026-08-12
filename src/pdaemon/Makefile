CC=musl-gcc
CFLAGS := -Wextra -Wall -Os
LDFLAGS := -s -static


pdaemon: main.c daemons.h
	$(CC) -std=gnu99 $(CFLAGS) $(LDFLAGS) main.c -o pdaemon
	upx pdaemon


clean:
	rm -f pdaemon

install:
	cp -f pdaemon /usr/sbin/
