CC=musl-gcc
CFLAGS := -Wextra -Wall -Os
LDFLAGS := -s -static


pinit: main.c programs.h
	$(CC) -std=gnu99 $(CFLAGS) $(LDFLAGS) main.c -o pinit
	upx pinit
	
	
clean:
	rm -f pinit

install:
	cp -f pinit /pinit


