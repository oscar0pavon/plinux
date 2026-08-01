/*  pgetty - minimal console getty, based on mingetty
 *
 *  Copyright (C) 1996 Florian La Roche  <laroche@redhat.com>
 *  Copyright (C) 2002, 2003 Red Hat, Inc
 *
 *  This program is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU General Public License
 *  as published by the Free Software Foundation; either version
 *  2 of the License, or (at your option) any later version.
 */

#define _GNU_SOURCE 1		       /* Needed to get vhangup() */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <stdarg.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/stat.h>

#define LOGIN_PROGRAM "/usr/bin/login2"

/* on which tty line are we sitting? (e.g. tty1) */
static char *tty;

/* error() - complain and die */
static void error (const char *fmt, ...)
	__attribute__ ((format (printf, 1, 2), noreturn));

static void error (const char *fmt, ...)
{
	va_list va;

	va_start (va, fmt);
	vfprintf (stderr, fmt, va);
	va_end (va);
	fputc ('\n', stderr);
	sleep (5);
	exit (EXIT_FAILURE);
}

/* open_tty - set up tty as standard { input, output, error } */
static void open_tty (void)
{
	struct sigaction sa, sa_old;
	char buf[64];
	int fd;

	if (tty[0] == '/') {
		strncpy (buf, tty, sizeof (buf) - 1);
		buf[sizeof (buf) - 1] = '\0';
	} else {
		strcpy (buf, "/dev/");
		strncat (buf, tty, sizeof (buf) - strlen (buf) - 1);
	}

	/* There is always a race between this reset and the call to
	   vhangup() that s.o. can use to get access to your tty. */
	if (chown (buf, 0, 0) || chmod (buf, 0600))
		if (errno != EROFS)
			error ("%s: %s", tty, strerror (errno));

	/* We become our own session leader so we can claim a controlling
	   tty; when started by init we already are one. */
	if (getsid (0) != getpid ())
		setsid ();

	sa.sa_handler = SIG_IGN;
	sa.sa_flags = 0;
	sigemptyset (&sa.sa_mask);
	sigaction (SIGHUP, &sa, &sa_old);

	/* vhangup() will replace all open file descriptors in the kernel
	   that point to our controlling tty by a dummy that will deny
	   further reading/writing to our device. It will also reset the
	   tty to sane defaults, so we don't have to modify the tty device
	   for sane settings. We also get a SIGHUP/SIGCONT. */
	if ((fd = open (buf, O_RDWR, 0)) < 0)
		error ("%s: cannot open tty: %s", tty, strerror (errno));
	if (ioctl (fd, TIOCSCTTY, (void *) 1) == -1)
		error ("%s: no controlling tty: %s", tty, strerror (errno));
	if (!isatty (fd))
		error ("%s: not a tty", tty);

	if (vhangup ())
		error ("%s: vhangup() failed", tty);
	/* Get rid of the present stdout/stderr. */
	close (2);
	close (1);
	close (0);
	close (fd);
	if ((fd = open (buf, O_RDWR, 0)) != 0)
		error ("%s: cannot open tty: %s", tty, strerror (errno));
	if (ioctl (fd, TIOCSCTTY, (void *) 1) == -1)
		error ("%s: no controlling tty: %s", tty, strerror (errno));

	/* Set up stdin/stdout/stderr. */
	if (dup2 (fd, 0) != 0 || dup2 (fd, 1) != 1 || dup2 (fd, 2) != 2)
		error ("%s: dup2(): %s", tty, strerror (errno));
	if (fd > 2)
		close (fd);

	sigaction (SIGHUP, &sa_old, NULL);
}

int main (int argc, char **argv)
{
	if (argc < 2)
		error ("usage: %s tty (e.g. tty1)", argv[0] ? argv[0] : "pgetty");

	tty = argv[1];
	if (strncmp (tty, "/dev/", 5) == 0) /* ignore leading "/dev/" */
		tty += 5;

	putenv ("TERM=linux");

	open_tty ();

	execl (LOGIN_PROGRAM, LOGIN_PROGRAM, NULL);
	error ("%s: can't exec %s: %s", tty, LOGIN_PROGRAM, strerror (errno));
}
