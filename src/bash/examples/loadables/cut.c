/* cut,lcut - extract specified fields from a line and assign them to an array
	      or print them to the standard output */

/*
   Copyright (C) 2020,2022,2023 Free Software Foundation, Inc.

   Bash is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   Bash is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with Bash.  If not, see <http://www.gnu.org/licenses/>.
*/

/* See Makefile for compilation details. */

#include <config.h>

#if defined (HAVE_UNISTD_H)
#  include <unistd.h>
#endif
#include "bashansi.h"
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>

#include "loadables.h"
#include "shmbutil.h"

#define CUT_ARRAY_DEFAULT	"CUTFIELDS"

#define NOPOS	-2		/* sentinel for unset startpos/endpos */

#define BOL	0		
#define EOL	INT_MAX
#define NORANGE	-1		/* just a position, no range */

#define BFLAG	(1 << 0)
#define CFLAG	(1 << 1)
#define DFLAG	(1 << 2)
#define FFLAG	(1 << 3)
#define SFLAG	(1 << 4)

struct cutpos
{
  int startpos, endpos;		/* zero-based, correction done in getlist() */
};

struct cutop
{
  int flags;
  int delim;
  int npos;
  struct cutpos *poslist;
};

static int
poscmp (const void *a, const void *b)
{
  struct cutpos *p1, *p2;

  p1 = (struct cutpos *)a;
  p2 = (struct cutpos *)b;
  return (p1->startpos - p2->startpos);
}

static int
getlist (char *arg, struct cutpos **opp)
{
  char *ntok, *ltok, *larg;
  int s, e;
  intmax_t num;
  struct cutpos *poslist;
  int npos, nsize;

  poslist = 0;
  nsize = npos = 0;
  s = e = 0;
  larg = arg;
  while (ltok = strsep (&larg, ","))
    {
      if (*ltok == 0)
        continue;

      ntok = strsep (&ltok, "-");
      if (*ntok == 0)
        s = BOL;
      else
	{
	  if (valid_number (ntok, &num) == 0 || (int)num != num || num <= 0)
	    {
	      builtin_error ("%s: invalid list value", ntok);
	      *opp = poslist;
	      return -1;
	    }
	  s = num;
	  s--;		/* fields are 1-based */
	}
      if (ltok == 0)
	e = NORANGE;
      else if (*ltok == 0)
	e = EOL;
      else
	{
	  if (valid_number (ltok, &num) == 0 || (int)num != num || num <= 0)
	    {
	      builtin_error ("%s: invalid list value", ltok);
	      *opp = poslist;
	      return -1;
	    }
	  e = num;
	  e--;
	  if (e == s)
	    e = NORANGE;
	}

      if (npos == nsize)
	{
	  nsize += 4;
	  poslist = (struct cutpos *)xrealloc (poslist, nsize * sizeof (struct cutpos));
	}
      poslist[npos].startpos = s;
      poslist[npos].endpos = e; 
      npos++;
    }
  if (npos == 0)
    {
      builtin_error ("missing list of positions");
      *opp = poslist;
      return -1;
    }

  qsort (poslist, npos, sizeof(poslist[0]), poscmp);
  *opp = poslist;

  return npos;
}

static int
cutbytes (SHELL_VAR *v, arrayind_t ind, char *line, struct cutop *ops)
{
  char *buf, *bmap;
  size_t llen;
  int i, b, n, s, e;

  llen = strlen (line);
  buf = xmalloc (llen + 1);
  bmap = xmalloc (llen + 1);
  memset (bmap, 0, llen);

  for (n = 0; n < ops->npos; n++)
    {
      s = ops->poslist[n].startpos;		/* no translation needed yet */
      e = ops->poslist[n].endpos;
      if (e == NORANGE)
        e = s;
      else if (e == EOL || e >= llen)
	e = llen - 1;
      /* even if a column is specified multiple times, it will only be printed
         once */
      for (i = s; i <= e; i++)
	bmap[i] = 1;
    }

  b = 0;
  for (i = 0; i < llen; i++)
    if (bmap[i])
      buf[b++] = line[i];
  buf[b] = 0; 

#if defined (ARRAY_VARS)
  if (v)
    bind_array_element (v, ind, buf, 0);
  else
#endif
    printf ("%s\n", buf);

  free (buf);
  free (bmap);

  return 1;
}

static int
cutchars (SHELL_VAR *v, arrayind_t ind, char *line, struct cutop *ops)
{
  char *buf, *bmap;
  wchar_t *wbuf, *wb2;
  size_t llen, wlen;
  int i, b, n, s, e;

  if (MB_CUR_MAX == 1)
    return (cutbytes (v, ind, line, ops));
  if (locale_utf8locale && utf8_mbsmbchar (line) == 0)
    return (cutbytes (v, ind, line, ops));

  llen = strlen (line);
  wbuf = (wchar_t *)xmalloc ((llen + 1) * sizeof (wchar_t));

  wlen = mbstowcs (wbuf, line, llen);
  if (MB_INVALIDCH (wlen))
    {
      free (wbuf);
      return (cutbytes (v, ind, line, ops));
    }

  bmap = xmalloc (llen + 1);
  memset (bmap, 0, llen);
  
  for (n = 0; n < ops->npos; n++)
    {
      s = ops->poslist[n].startpos;		/* no translation needed yet */
      e = ops->poslist[n].endpos;
      if (e == NORANGE)
        e = s;
      else if (e == EOL || e >= wlen)
	e = wlen - 1;
      /* even if a column is specified multiple times, it will only be printed
         once */
      for (i = s; i <= e; i++)
	bmap[i] = 1;
    }

  wb2 = (wchar_t *)xmalloc ((wlen + 1) * sizeof (wchar_t));
  b = 0;
  for (i = 0; i < wlen; i++)
    if (bmap[i])
      wb2[b++] = wbuf[i];
  wb2[b] = 0;

  free (wbuf);

  buf = bmap;
  n = wcstombs (buf, wb2, llen);

#if defined (ARRAY_VARS)
  if (v)
    bind_array_element (v, ind, buf, 0);
  else
#endif
    printf ("%s\n", buf);

  free (buf);
  free (wb2);

  return 1;
}

/* The basic strategy is to cut the line into fields using strsep, populate
   an array of fields from 0..nf, then select those fields using the same
   bitmap approach as cut{bytes,chars} and assign them to the array variable
   V or print them on stdout. This function obeys SFLAG. */
static int
cutfields (SHELL_VAR *v, arrayind_t ind, char *line, struct cutop *ops)
{
  char *buf, *bmap, *field, **fields, delim[2];
  size_t llen, fsize;
  int i, b, n, s, e, nf;

  delim[0] = ops->delim;
  delim[1] = '\0';

  fields = 0;
  nf = 0;
  fsize = 0;

  field = buf = line;
  do
    {
      field = strsep (&buf, delim);	/* destructive */
      if (nf == fsize)
	{
	  fsize += 8;
	  fields = xrealloc (fields, fsize * sizeof (char *));
	}
      fields[nf] = field;
      if (field)
	nf++;
    }
  while (field);

  if (nf == 1)
    {
      free (fields);
      if (ops->flags & SFLAG)
	return 0;
#if defined (ARRAY_VARS)
      if (v)
	bind_array_element (v, ind, line, 0);
      else
#endif
	printf ("%s\n", line);

      return 1;
    }

  bmap = xmalloc (nf + 1);
  memset (bmap, 0, nf);

  for (n = 0; n < ops->npos; n++)
    {
      s = ops->poslist[n].startpos;		/* no translation needed yet */
      e = ops->poslist[n].endpos;
      if (e == NORANGE)
        e = s;
      else if (e == EOL || e >= nf)
	e = nf - 1;
      /* even if a column is specified multiple times, it will only be printed
         once */
      for (i = s; i <= e; i++)
	bmap[i] = 1;
    }

  /* build the string and assign or print it all at once */
  buf = xmalloc (strlen (line) + 1);

  for (i = 1, n = b = 0; b < nf; b++)
    {
      if (bmap[b] == 0)
	continue;
      if (i == 0)
	buf[n++] = ops->delim;
      strcpy (buf + n, fields[b]);
      n += STRLEN (fields[b]);
      i = 0;
    }

#if defined (ARRAY_VARS)
  if (v)
    bind_array_element (v, ind, buf, 0);
  else
#endif
    printf ("%s\n", buf);

  free (bmap);
  free (buf);

  return 1;
}

static int
cutline (SHELL_VAR *v, arrayind_t ind, char *line, struct cutop *ops)
{
  int rval;

  if (ops->flags & BFLAG)
    rval = cutbytes (v, ind, line, ops);
  else if (ops->flags & CFLAG)
    rval = cutchars (v, ind, line, ops);
  else
    rval = cutfields (v, ind, line, ops);

  return (rval);
}

static int
cutfile (SHELL_VAR *v, WORD_LIST *list, struct cutop *ops)
{
  int fd, unbuffered_read, r;
  char *line, *b;
  size_t llen;
  WORD_LIST *l;
  ssize_t n;
  arrayind_t ind;

  line = 0;
  llen = 0;
  ind = 0;

  l = list;
  do
    {
      /* for each file */
      if (l == 0 || (l->word->word[0] == '-' && l->word->word[1] == '\0'))
	fd = 0;
      else
	fd = open (l->word->word, O_RDONLY);
      if (fd < 0)
	{
	  file_error (l->word->word);
	  return (EXECUTION_FAILURE);
	}

#ifndef __CYGWIN__
      unbuffered_read = (lseek (fd, 0L, SEEK_CUR) < 0) && (errno == ESPIPE);
#else
      unbuffered_read = 1;
#endif

      while ((n = zgetline (fd, &line, &llen, '\n', unbuffered_read)) != -1)
	{
	  QUIT;
	  if (line[n] == '\n')
	    line[n] = '\0';		/* cutline expects no newline terminator */
	  r = cutline (v, ind, line, ops);	/* can modify line */
	  ind += r;
	}
      if (fd > 0)
	close (fd);

      QUIT;
      if (l)
	l = l->next;
    }
  while (l);

  free (line);
  return EXECUTION_SUCCESS;
}

#define OPTSET(x)	     ((cutflags & (x)) ? 1 : 0)

static int
cut_internal (int which, WORD_LIST *list)
{
  int opt, rval, cutflags, delim, npos;
  char *array_name, *cutstring, *list_arg;
  SHELL_VAR *v;
  struct cutop op;
  struct cutpos *poslist;

  v = 0;
  rval = EXECUTION_SUCCESS;

  cutflags = 0;
  array_name = 0;
  list_arg = 0;
  delim = '\t';

  reset_internal_getopt ();
  while ((opt = internal_getopt (list, "a:b:c:d:f:sn")) != -1)
    {
      switch (opt)
	{
	case 'a':
#if defined (ARRAY_VARS)
	  array_name = list_optarg;
	  break;
#else
	  builtin_error ("arrays not available");
	  return (EX_USAGE);
#endif
	case 'b':
	  cutflags |= BFLAG;
	  list_arg = list_optarg;
	  break;
	case 'c':
	  cutflags |= CFLAG;
	  list_arg = list_optarg;
	  break;
	case 'd':
	  cutflags |= DFLAG;
	  delim = list_optarg[0];
	  if (delim == 0 || list_optarg[1])
	    {
	      builtin_error ("delimiter must be a single non-null character");
	      return (EX_USAGE);
	    }
	  break;
	case 'f':
	  cutflags |= FFLAG;
	  list_arg = list_optarg;
	  break;
	case 'n':
	  break;
	case 's':
	  cutflags |= SFLAG;
	  break;
	CASE_HELPOPT;
	default:
	  builtin_usage ();
	  return (EX_USAGE);
	}
    }
  list = loptend;

  if (array_name && (valid_identifier (array_name) == 0))
    {
      sh_invalidid (array_name);
      return (EXECUTION_FAILURE);
    }

  if (list == 0 && which == 0)
    {
      builtin_error ("string argument required");
      return (EX_USAGE);
    }

  /* options are mutually exclusive and one is required */
  if ((OPTSET (BFLAG) + OPTSET (CFLAG) + OPTSET (FFLAG)) != 1)
    {
      builtin_usage ();
      return (EX_USAGE);
    }

  if ((npos = getlist (list_arg, &poslist)) < 0)
    {
      free (poslist);
      return (EXECUTION_FAILURE);
    }

#if defined (ARRAY_VARS)
  if (array_name)
    {
      v = builtin_find_indexed_array (array_name, 1);
      if (v == 0)
	{
	  free (poslist);
	  return (EXECUTION_FAILURE);
	}
    }
#endif

  op.flags = cutflags;
  op.delim = delim;
  op.npos = npos;
  op.poslist = poslist;

  /* we implement cut as a builtin with a cutfile() function that opens each
     filename in LIST as a filename (or `-' for stdin) and runs cutline on
     every line in the file. lcut just runs cutline on the first string in
     LIST. */
  if (which == 0)
    {
      cutstring = list->word->word;
      if (cutstring == 0 || *cutstring == 0)
	{
	  free (poslist);
	  return (EXECUTION_SUCCESS);
	}
      rval = cutline (v, 0, cutstring, &op);
      /* Normalize rval, because cutline returns an increment for ind */
      rval = (rval >= 0 ? EXECUTION_SUCCESS : EXECUTION_FAILURE);
    }
  else
    rval = cutfile (v, list, &op);

  free (poslist);
  return (rval);
}

int
lcut_builtin (WORD_LIST *list)
{
  return (cut_internal (0, list));
}

int
cut_builtin (WORD_LIST *list)
{
  return (cut_internal (1, list));
}

char *lcut_doc[] = {
	"Extract selected fields from a string.",
	"",
        "Select portions of LINE (as specified by LIST) and assign them to",
        "element 0 of the indexed array ARRAY, or write them to the standard",
        "output if -a is not specified.",
        "",
	"Items specified by LIST are either column positions or fields delimited",
	"by a special character, and are described more completely in cut(1).",
	"",
	"Columns correspond to bytes (-b), characters (-c), or fields (-f). The",
	"field delimiter is specified by -d (default TAB). Column numbering",
	"starts at 1.",
	"",
	"When -a is specified, lcut assigns the selected portions of LINE",
	"to index 0 of ARRAY. The string lcut assigns to ARRAY is identical",
	"to the string it would write to the standard output if -a were not",
	"supplied.",
	(char *)NULL
};

struct builtin lcut_struct = {
	"lcut",			/* builtin name */
	lcut_builtin,		/* function implementing the builtin */
	BUILTIN_ENABLED,	/* initial flags for builtin */
	lcut_doc,		/* array of long documentation strings. */
	"lcut [-a ARRAY] [-b LIST] [-c LIST] [-f LIST] [-d CHAR] [-sn] line",	/* usage synopsis; becomes short_doc */
	0			/* reserved for internal use */
};

char *cut_doc[] = {
	"Extract selected fields from each line of a file.",
	"",
        "Select portions of each line (as specified by LIST) from each FILE",
        "and write them to the standard output, or assign them to the indexed",
        "array ARRAY starting at index 0. cut reads from the standard",
        "input if no FILE arguments are specified or if a FILE argument is a",
        "single hyphen.",
        "",
	"Items specified by LIST are either column positions or fields delimited",
	"by a special character, and are described more completely in cut(1).",
	"",
	"Columns correspond to bytes (-b), characters (-c), or fields (-f). The",
	"field delimiter is specified by -d (default TAB). Column numbering",
	"starts at 1.",
	"",
	"When -a is specified, cut assigns the output from each line it",
	"processes to successive elements of ARRAY, beginning at 0. The",
	"strings cut assigns to ARRAY are identical to the strings it would",
	"write to the standard output if -a were not supplied.",
	(char *)NULL
};

struct builtin cut_struct = {
	"cut",			/* builtin name */
	cut_builtin,		/* function implementing the builtin */
	BUILTIN_ENABLED,	/* initial flags for builtin */
	cut_doc,		/* array of long documentation strings. */
	"cut [-a ARRAY] [-b LIST] [-c LIST] [-f LIST] [-d CHAR] [-sn] [file ...]",	/* usage synopsis; becomes short_doc */
	0			/* reserved for internal use */
};
