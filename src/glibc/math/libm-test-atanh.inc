/* Test atanh.
   Copyright (C) 1997-2025 Free Software Foundation, Inc.
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

#include "libm-test-driver.c"

static const struct test_f_f_data atanh_test_data[] =
  {
    TEST_f_f (atanh, 1, plus_infty, DIVIDE_BY_ZERO_EXCEPTION|ERRNO_ERANGE),
    TEST_f_f (atanh, -1, minus_infty, DIVIDE_BY_ZERO_EXCEPTION|ERRNO_ERANGE),
    TEST_f_f (atanh, qnan_value, qnan_value, NO_INEXACT_EXCEPTION|ERRNO_UNCHANGED),
    TEST_f_f (atanh, -qnan_value, qnan_value, NO_INEXACT_EXCEPTION|ERRNO_UNCHANGED),
    TEST_f_f (atanh, snan_value, qnan_value, INVALID_EXCEPTION),
    TEST_f_f (atanh, -snan_value, qnan_value, INVALID_EXCEPTION),

    /* atanh (x) == qNaN plus invalid exception if |x| > 1.  */
    TEST_f_f (atanh, 1.125L, qnan_value, INVALID_EXCEPTION|ERRNO_EDOM),
    TEST_f_f (atanh, -1.125L, qnan_value, INVALID_EXCEPTION|ERRNO_EDOM),
    TEST_f_f (atanh, max_value, qnan_value, INVALID_EXCEPTION|ERRNO_EDOM),
    TEST_f_f (atanh, -max_value, qnan_value, INVALID_EXCEPTION|ERRNO_EDOM),
    TEST_f_f (atanh, plus_infty, qnan_value, INVALID_EXCEPTION|ERRNO_EDOM),
    TEST_f_f (atanh, minus_infty, qnan_value, INVALID_EXCEPTION|ERRNO_EDOM),

    AUTO_TESTS_f_f (atanh),
  };

static void
atanh_test (void)
{
  ALL_RM_TEST (atanh, 0, atanh_test_data, RUN_TEST_LOOP_f_f, END);
}

static void
do_test (void)
{
  atanh_test ();
}

/*
 * Local Variables:
 * mode:c
 * End:
 */
