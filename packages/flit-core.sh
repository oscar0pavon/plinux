#!/bin/bash
#
# flit-core - a python build backend. LFS 12.4 section 8.52.
#
# First of the four python modules pip needs before it can install meson.
# They are all built and installed the same way, and the pattern is worth
# explaining once here.
#
#   pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
#   pip3 install --no-index --find-links dist <name>
#
# --no-build-isolation, --no-deps and --no-index between them forbid pip from
# reaching the network. Built in the right order it never needs to; the
# options are there so that a mistake in the order fails rather than quietly
# downloading something.
#
# --root is the part that is not in the book, and it matters. Inside the
# chroot build_directory is empty and pip installs into /usr, which is the
# image. Outside it, pip with no --root installs into the *build host's*
# /usr/lib/python3.x/site-packages -- this workstation's python, not the
# image's. So --root is passed exactly when there is somewhere to stage to.
#
# One honest caveat about the host path: pip stages under the version
# directory of whichever python is running it, and this workstation's python
# is not the image's. The copy that ends up in the image is the one the
# chroot build produces, which is the build that counts now.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'flit_core-*.tar.gz' 'flit_core-3.12.0')
cd "${directory}"

pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "${PWD}"

pip3 install ${build_directory:+--root="${build_directory}"} \
     --no-index --find-links dist flit_core
