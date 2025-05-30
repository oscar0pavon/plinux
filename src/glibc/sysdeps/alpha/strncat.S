/* Copyright (C) 1996-2025 Free Software Foundation, Inc.
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
   License along with the GNU C Library.  If not, see
   <https://www.gnu.org/licenses/>.  */

/* Append no more than COUNT characters from the null-terminated string SRC
   to the null-terminated string DST.  Always null-terminate the new DST.  */

#include <sysdep.h>

	.text

ENTRY(strncat)
	ldgp	gp, 0(pv)
#ifdef PROF
	.set noat
	lda	AT, _mcount
	jsr	AT, (AT), _mcount
	.set at
#endif
	.prologue 1

	mov	a0, v0		# set up return value
	beq	a2, $zerocount

	/* Find the end of the string.  */

	ldq_u   t0, 0(a0)	# load first quadword (a0 may be misaligned)
	lda     t1, -1(zero)
	insqh   t1, a0, t1
	andnot  a0, 7, a0
	or      t1, t0, t0
	cmpbge  zero, t0, t1	# t1 <- bitmask: bit i == 1 <==> i-th byte == 0
	bne     t1, $found

$loop:	ldq     t0, 8(a0)
	addq    a0, 8, a0	# addr += 8
	cmpbge  zero, t0, t1
	beq     t1, $loop

$found:	negq    t1, t2		# clear all but least set bit
	and     t1, t2, t1

	and     t1, 0xf0, t2	# binary search for that set bit
	and	t1, 0xcc, t3
	and	t1, 0xaa, t4
	cmovne	t2, 4, t2
	cmovne	t3, 2, t3
	cmovne	t4, 1, t4
	addq	t2, t3, t2
	addq	a0, t4, a0
	addq	a0, t2, a0

	/* Now do the append.  */

	jsr	t9, __stxncpy

	/* Worry about the null termination.  */

	zapnot	t0, t8, t1	# was last byte a null?
	bne	t1, 0f
	ret

0:	and	t10, 0x80, t1
	bne	t1, 1f

	/* Here there are bytes left in the current word.  Clear one.  */
	addq	t10, t10, t10	# end-of-count bit <<= 1
	zap	t0, t10, t0
	stq_u	t0, 0(a0)
	ret

1:	/* Here we must read the next DST word and clear the first byte.  */
	ldq_u	t0, 8(a0)
	zap	t0, 1, t0
	stq_u	t0, 8(a0)

$zerocount:
	ret

	END(strncat)
