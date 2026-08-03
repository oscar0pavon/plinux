#!/bin/bash
#
# Build a static bash against musl, from the source tree this script sits in.
#
# Adapted from build_static.sh in robxu9/bash-static, which downloads bash and
# musl from upstream and verifies them. Everything here is local, so the
# download, GPG and patching machinery is gone.
#
# Copyright © 2015 Robert Xu <robxu9@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the “Software”), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")" || exit 1

musl_gcc=${MUSL_GCC:-$(command -v musl-gcc || true)}
jobs=${JOBS:-$(nproc)}

if [ -z "${musl_gcc}" ]; then
  echo "! musl-gcc not found; set MUSL_GCC to its path" >&2
  exit 1
fi

echo "= using ${musl_gcc}"

# The tree still holds objects from whatever it was configured with last. They
# would be mixed silently into a musl build, so start clean.
if [ -f Makefile ]; then
  echo "= cleaning previous build"
  make distclean &> /dev/null || make clean &> /dev/null || true
fi

export CC=${musl_gcc}
export CFLAGS="${CFLAGS:-} -Os -static"
export CPPFLAGS="${CFLAGS}"   # some versions read the flags from only one

echo "= configuring bash"

# bash_cv_termcap_lib=gnutermcap selects the termcap bundled in ./lib/termcap
# instead of linking ncurses. The image has no ncurses, and a static binary
# still needing libncursesw.so.6 would defeat the point.
./configure \
  --without-bash-malloc \
  --enable-static-link \
  --enable-silent-rules \
  bash_cv_termcap_lib=gnutermcap

echo "= building bash"
make -s -j"${jobs}"

strip -s bash

echo "= done"
file bash
ls -la bash
