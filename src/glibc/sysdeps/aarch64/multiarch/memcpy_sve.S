/* Optimized memcpy for SVE.
   Copyright (C) 2021-2025 Free Software Foundation, Inc.

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

#include <sysdep.h>

/* Assumptions:
 *
 * ARMv8-a, AArch64, Advanced SIMD, SVE, unaligned accesses.
 *
 */

#define dstin	x0
#define src	x1
#define count	x2
#define dst	x3
#define srcend	x4
#define dstend	x5
#define tmp1	x6
#define vlen	x6

#define A_q	q0
#define B_q	q1
#define C_q	q2
#define D_q	q3
#define E_q	q4
#define F_q	q5
#define G_q	q6
#define H_q	q7

/* This implementation supports both memcpy and memmove and shares most code.
   It uses unaligned accesses and branchless sequences to keep the code small,
   simple and improve performance.

   Copies are split into 3 main cases: small copies of up to 32 bytes, medium
   copies of up to 128 bytes, and large copies.  The overhead of the overlap
   check in memmove is negligible since it is only required for large copies.

   Large copies use a software pipelined loop processing 64 bytes per iteration.
   The source pointer is 16-byte aligned to minimize unaligned accesses.
   The loop tail is handled by always copying 64 bytes from the end.
*/

#if HAVE_AARCH64_SVE_ASM

	.arch armv8.2-a+sve

ENTRY (__memcpy_sve)
	PTR_ARG (0)
	PTR_ARG (1)
	SIZE_ARG (2)

	cmp	count, 128
	b.hi	L(copy_long)
	cntb	vlen
	cmp	count, vlen, lsl 1
	b.hi	L(copy32_128)
	whilelo p0.b, xzr, count
	whilelo p1.b, vlen, count
	ld1b	z0.b, p0/z, [src, 0, mul vl]
	ld1b	z1.b, p1/z, [src, 1, mul vl]
	st1b	z0.b, p0, [dstin, 0, mul vl]
	st1b	z1.b, p1, [dstin, 1, mul vl]
	ret

	/* Medium copies: 33..128 bytes.  */
L(copy32_128):
	add	srcend, src, count
	add	dstend, dstin, count
	ldp	A_q, B_q, [src]
	ldp	C_q, D_q, [srcend, -32]
	cmp	count, 64
	b.hi	L(copy128)
	stp	A_q, B_q, [dstin]
	stp	C_q, D_q, [dstend, -32]
	ret

	/* Copy 65..128 bytes.  */
L(copy128):
	ldp	E_q, F_q, [src, 32]
	cmp	count, 96
	b.ls	L(copy96)
	ldp	G_q, H_q, [srcend, -64]
	stp	G_q, H_q, [dstend, -64]
L(copy96):
	stp	A_q, B_q, [dstin]
	stp	E_q, F_q, [dstin, 32]
	stp	C_q, D_q, [dstend, -32]
	ret

	.p2align 4
	/* Copy more than 128 bytes.  */
L(copy_long):
	add	srcend, src, count
	add	dstend, dstin, count

	/* Copy 16 bytes and then align src to 16-byte alignment.  */
	ldr	D_q, [src]
	and	tmp1, src, 15
	bic	src, src, 15
	sub	dst, dstin, tmp1
	add	count, count, tmp1	/* Count is now 16 too large.  */
	ldp	A_q, B_q, [src, 16]
	str	D_q, [dstin]
	ldp	C_q, D_q, [src, 48]
	subs	count, count, 128 + 16	/* Test and readjust count.  */
	b.ls	L(copy64_from_end)
L(loop64):
	stp	A_q, B_q, [dst, 16]
	ldp	A_q, B_q, [src, 80]
	stp	C_q, D_q, [dst, 48]
	ldp	C_q, D_q, [src, 112]
	add	src, src, 64
	add	dst, dst, 64
	subs	count, count, 64
	b.hi	L(loop64)

	/* Write the last iteration and copy 64 bytes from the end.  */
L(copy64_from_end):
	ldp	E_q, F_q, [srcend, -64]
	stp	A_q, B_q, [dst, 16]
	ldp	A_q, B_q, [srcend, -32]
	stp	C_q, D_q, [dst, 48]
	stp	E_q, F_q, [dstend, -64]
	stp	A_q, B_q, [dstend, -32]
	ret

END (__memcpy_sve)


ENTRY (__memmove_sve)
	PTR_ARG (0)
	PTR_ARG (1)
	SIZE_ARG (2)

	cmp	count, 128
	b.hi	L(move_long)
	cntb	vlen
	cmp	count, vlen, lsl 1
	b.hi	L(copy32_128)
	whilelo p0.b, xzr, count
	whilelo p1.b, vlen, count
	ld1b	z0.b, p0/z, [src, 0, mul vl]
	ld1b	z1.b, p1/z, [src, 1, mul vl]
	st1b	z0.b, p0, [dstin, 0, mul vl]
	st1b	z1.b, p1, [dstin, 1, mul vl]
	ret

	.p2align 4
L(move_long):
	add	srcend, src, count
	add	dstend, dstin, count
	/* Only use backward copy if there is an overlap.  */
	sub	tmp1, dstin, src
	cbz	tmp1, L(return)
	cmp	tmp1, count
	b.hs	L(copy_long)

	/* Large backwards copy for overlapping copies.
	   Copy 16 bytes and then align srcend to 16-byte alignment.  */
	ldr	D_q, [srcend, -16]
	and	tmp1, srcend, 15
	bic	srcend, srcend, 15
	sub	count, count, tmp1
	ldp	A_q, B_q, [srcend, -32]
	str	D_q, [dstend, -16]
	ldp	C_q, D_q, [srcend, -64]
	sub	dstend, dstend, tmp1
	subs	count, count, 128
	b.ls	L(copy64_from_start)

L(loop64_backwards):
	str	B_q, [dstend, -16]
	str	A_q, [dstend, -32]
	ldp	A_q, B_q, [srcend, -96]
	str	D_q, [dstend, -48]
	str	C_q, [dstend, -64]!
	ldp	C_q, D_q, [srcend, -128]
	sub	srcend, srcend, 64
	subs	count, count, 64
	b.hi	L(loop64_backwards)

	/* Write the last iteration and copy 64 bytes from the start.  */
L(copy64_from_start):
	ldp	E_q, F_q, [src, 32]
	stp	A_q, B_q, [dstend, -32]
	ldp	A_q, B_q, [src]
	stp	C_q, D_q, [dstend, -64]
	stp	E_q, F_q, [dstin, 32]
	stp	A_q, B_q, [dstin]
L(return):
	ret

END (__memmove_sve)
#endif
