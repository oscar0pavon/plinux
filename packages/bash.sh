#!/bin/bash
#
# bash - the shell, static against musl.
#
# This was src/bash/build_static.sh, run by build.sh as one of this project's
# own components. It is a package: third-party source, built from a tarball,
# installed into obj/ like the other thirty-two. Being a component cost a full
# rebuild on every ./build.sh -- distclean, configure and all -- because the
# component steps have no stamps and the script cleaned its own tree first.
# That was seventeen of the twenty-five seconds a no-op build took, for a tree
# that never changes. As a package it is skipped once its stamp is in
# obj/.packages, and "./build.sh packages bash" rebuilds it on demand.
#
# The distclean is gone with it. It existed because the tree was reused across
# builds and could still hold objects from whatever compiler configured it
# last; unpack() gives a fresh tree from the tarball instead, and a tree that
# is already unpacked is one this script itself built.
#
# Adapted from build_static.sh in robxu9/bash-static, which downloads bash and
# musl from upstream and verifies them. download.sh does that part now.
#
# Copyright (c) 2015 Robert Xu <robxu9@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'bash-*.tar.gz' 'bash-5.3')
cd "${directory}"

# Static, unlike everything else here. plogin execs this shell, and pinit execs
# plogin, so a dynamic bash makes the login path depend on the loader and on
# every library it names being staged correctly. Static, it either exists or it
# does not.
#
# --sysroot is dropped for the same reason: with -static there is nothing to
# resolve at run time, and musl-gcc supplies its own headers and startfiles
# through its specs anyway, so the sysroot has nothing to contribute.
export CFLAGS="-Os -static"
export CPPFLAGS="${CFLAGS}"   # some versions read the flags from only one
export LDFLAGS="-static"

# bash_cv_termcap_lib=gnutermcap selects the termcap bundled in ./lib/termcap
# instead of linking ncurses. The image does have ncurses now, but a static
# binary that still needed libncursesw.so.6 would defeat the point.
./configure --prefix=/usr           \
            --without-bash-malloc   \
            --enable-static-link    \
            --enable-silent-rules   \
            bash_cv_termcap_lib=gnutermcap

make

strip -s bash

install -D -m 755 bash "${build_directory}/usr/bin/bash"

# Every script in sys/scripts starts #!/bin/sh, and so does most of what will
# ever be written for this system. Without this they do not fail at the first
# command, they fail to execute at all.
ln -sfv bash "${build_directory}/usr/bin/sh"
