/* Wrapper for printf.  IEEE128 version.
   Copyright (C) 2019-2025 Free Software Foundation, Inc.
   This file is part of the GNU C Library.

   The GNU C Library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   The GNU C Library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with the GNU C Library; if not, see
   <https://www.gnu.org/licenses/>.  */

#include <stdarg.h>
#include <libio/libioP.h>

extern int
___ieee128_printf (const char *format, ...)
{
  va_list ap;
  int done;

  va_start (ap, format);
  done = __vfprintf_internal (stdout, format, ap,
			      PRINTF_LDBL_USES_FLOAT128);
  va_end (ap);

  return done;
}
strong_alias (___ieee128_printf, __printfieee128)
