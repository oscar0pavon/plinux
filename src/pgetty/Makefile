CC=musl-gcc
CFLAGS=-O2 -Wall -W -pipe -D_GNU_SOURCE
LDFLAGS := -s -static

all: pgetty 

install:	all
		cp pgetty /bin/pgetty

pgetty: main.c
	$(CC) main.c $(LDFLAGS) $(CFLAGS) -o pgetty
	upx --ultra-brute pgetty


clean:
		rm -f *.o pgetty

