#!/bin/bash
#
# LFS 5.5. Glibc-2.42, cross-compiled into $LFS by gcc-pass1.
#
# The step the whole chapter is for. After this the target has a C library,
# and the sanity checks at the bottom can prove something this project has
# never been able to assert before: that the compiler reaches into $LFS for
# its headers, its start files, its libc and its loader, and does not reach
# into this workstation for any of them.
#
# Those checks are the book's, run as tests rather than printed for a human to
# compare against a listing. They are cheap and they are the only thing
# standing between a subtly wrong toolchain and a chapter 8 that fails
# somewhere unrelated, days later.

set -e

source "$(dirname "$(readlink -f "$0")")/common.sh"

toolchain_layout

# LFS 5.5.1. The loader's compatibility names.
#
# glibc installs the real loader as /usr/lib/ld-linux-x86-64.so.2 below
# (libc_cv_slibdir=/usr/lib). These two symlinks put it where an x86_64 ELF
# binary's PT_INTERP actually names it -- /lib64 -- and where the LSB says a
# conforming system provides it. ../lib from inside $LFS/lib64 is $LFS/lib,
# which is the symlink to usr/lib that toolchain_layout made, so both land on
# the real file.
ln -sfn ../lib/ld-linux-x86-64.so.2 "${LFS}/lib64/ld-linux-x86-64.so.2"
ln -sfn ../lib/ld-linux-x86-64.so.2 "${LFS}/lib64/ld-lsb-x86-64.so.3"

directory=$(unpack 'glibc-*.tar.xz' 'glibc-2.42')
cd "${directory}"

# Some glibc programs keep runtime state in /var/db, which is not in the FHS.
# The patch moves them to the compliant locations. packages/glibc.sh applies
# the same patch to the same tree, and apply_patch's reversal test is what
# keeps the second caller from failing on every hunk.
apply_patch 'glibc-*-fhs-1.patch'

# OPEN_TREE_CLONE, guarded.
#
# This is the one place glibc 2.42 does not compile against the kernel in
# src/linux, and it is worth being precise about what the disagreement is,
# because it is smaller than it looks and the obvious fixes are all worse.
#
# sys/mount.h includes <linux/mount.h> when it exists (line 31, behind
# __has_include) and then defines three constants the kernel header also
# defines:
#
#   FSOPEN_CLOEXEC      kernel 0x00000001   glibc 0x00000001
#   OPEN_TREE_CLOEXEC   kernel O_CLOEXEC    glibc O_CLOEXEC
#   OPEN_TREE_CLONE     kernel (1 << 0)     glibc 1
#
# C allows a macro to be redefined when the replacement list is token for
# token identical, so the first two are silently fine and always have been.
# The third is the same *value* spelled differently, which is a redefinition,
# and glibc builds with -Werror. That is the whole failure: umount.c and
# umount2.c are simply the first two files to include the header.
#
# So this is a glibc bug -- it already anticipated the kernel header being
# there and then failed to guard these three -- and not a kernel
# incompatibility. Wrapping the define in #ifndef is what glibc should have
# written, and because the values are equal it cannot change behaviour: either
# spelling produces 1.
#
# The alternatives were considered and are worse. Building glibc against the
# book's linux-6.16.1 headers works (that tarball is in sources/ as the
# fallback) but puts a second kernel source in the tree and compiles the C
# library against a kernel this system does not run. Turning off -Werror hides
# this collision and any other. A newer glibc from git fixes it upstream, but
# LFS 12.4 pins 2.42 against gcc 15.2.0 and tests chapter 8 on that pair, so
# moving it drags packages/glibc.sh, gcc-pass1's --with-glibc-version and the
# whole package set along with it.
#
# Idempotent, because these scripts are re-run: the grep is for the guard, not
# for the define.
mount_header=sysdeps/unix/sysv/linux/sys/mount.h

if ! grep -q '^#ifndef OPEN_TREE_CLONE$' "${mount_header}"; then
  echo "guarding OPEN_TREE_CLONE in ${mount_header}" >&2
  sed -i 's@^#define OPEN_TREE_CLONE\(.*\)$@#ifndef OPEN_TREE_CLONE\n#define OPEN_TREE_CLONE\1\n#endif@' \
      "${mount_header}"
fi

if ! grep -q '^#ifndef OPEN_TREE_CLONE$' "${mount_header}"; then
  echo "glibc: failed to guard OPEN_TREE_CLONE in ${mount_header}" >&2
  exit 1
fi

# build-cross, not build: packages/glibc.sh builds this same source tree
# natively into obj/ and calls its directory "build". Two configures with
# different --host in one directory would each poison the other's cache.
build=$(fresh_build_dir "${directory}")
cd "${build}"

# ldconfig and sln into /usr/sbin rather than glibc's default /sbin. The image
# has no real /sbin -- it is a symlink onto usr/sbin -- so this only decides
# which name the files are installed under, and getting it wrong leaves them
# somewhere the merged-/usr layout does not describe.
echo "rootsbindir=/usr/sbin" > configparms

# --prefix=/usr
#   Where these files will live once $LFS is the root filesystem. Not where
#   they are being written now; DESTDIR below handles that.
#
# --host=$LFS_TGT, --build=$(../scripts/config.guess)
#   The pair that puts glibc's build system into cross-compilation mode, so
#   it uses $LFS/tools/bin/$LFS_TGT-gcc and does not try to run the binaries
#   it produces. config.guess describes this machine; $LFS_TGT describes the
#   target; they differ in the vendor field and that is enough.
#
# --enable-kernel=5.4
#   The oldest kernel this glibc will support. Everything older gets its
#   workarounds compiled out. The kernel in src/linux is far newer, and the
#   image only ever runs that one or the VM's.
#
# libc_cv_slibdir=/usr/lib
#   Install the library into /usr/lib rather than glibc's 64-bit default of
#   /lib64. packages/glibc.sh sets the same variable for the same reason.
#
# --disable-nscd
#   The name service cache daemon, which glibc itself no longer uses.
# libc_cv_cxx_link_ok=no is not in the book, and it is here because these
# scripts can be re-run and the book's cannot.
#
# glibc's configure tests whether the C++ compiler can link a program, and
# builds support/links-dso-program if it can. That program links C++, so it
# needs libgcc_s -- the *shared* libgcc, which does not exist, because
# gcc-pass1 is configured --disable-shared exactly as LFS 5.3 specifies.
#
# On a first run through the chapter the test answers no on its own: glibc is
# built before libstdc++, $LFS_TGT-g++ has no C++ library to link against, and
# configure skips the program. Build the chapter once and then rebuild glibc
# alone -- "toolchain glibc", or "toolchain force" -- and libstdc++ is now
# installed from the step *after* this one, the same test answers yes, and the
# link fails on -lgcc_s.
#
# That is a step whose result depends on whether a later step has run, which
# is the one thing a resumable build cannot have. Pinning the answer to the
# one the book's ordering produces makes this step mean the same thing however
# many times it is run and in whatever order.
#
# Nothing is lost: links-dso-program is test-support code, chapter 5 runs no
# test suite, and packages/glibc.sh -- the native chapter 8 build, where
# libgcc_s does exist -- is a separate script and is not touched by this.
../configure --prefix=/usr                      \
             --host="${LFS_TGT}"                \
             --build="$(../scripts/config.guess)" \
             --disable-nscd                     \
             libc_cv_slibdir=/usr/lib           \
             libc_cv_cxx_link_ok=no             \
             --enable-kernel=5.4

make

# DESTDIR is doing something different here from everywhere else in this
# repository. In packages/ it redirects a native install away from the build
# host. Here the compiler is already aimed at $LFS and DESTDIR only says where
# to write the files; --prefix=/usr above is what they will be once $LFS is /.
#
# The book's warning applies with full force: if $LFS were empty this line
# would install a cross-compiled glibc over this workstation's own and leave
# it unbootable. common.sh sets LFS unconditionally and toolchain_layout has
# already created it, so by the time execution reaches here it cannot be
# empty -- but this is the line to be careful editing.
make DESTDIR="${LFS}" install

# ldd is a shell script with the loader's path written into it, and glibc
# writes it as /usr/lib/ld-linux-x86-64.so.2 -- correct as a path inside the
# image, wrong as the RTLDLIST the script execs, which wants /lib64. Stripping
# the /usr prefix is the book's fix.
sed '/RTLDLIST=/s@/usr@@g' -i "${LFS}/usr/bin/ldd"

##############################################################################
# LFS 5.5.1, the sanity checks.
#
# Compile the smallest possible program with the cross compiler, ask the
# compiler and linker to say what they did, and read the answers. Every one of
# these is a statement about which tree a search resolved in.
##############################################################################

check_dir=$(mktemp -d)
trap 'rm -rf "${check_dir}"' EXIT
cd "${check_dir}"

echo 'int main(){}' | "${LFS_TGT}-gcc" -x c - -v -Wl,--verbose &> dummy.log

sanity_failed=0

fail(){
  echo "  FAIL: $1" >&2
  sanity_failed=1
}

# 1. The interpreter the binary asks for. It has to be the absolute path
#    /lib64/ld-linux-x86-64.so.2, which resolves once the chroot makes $LFS
#    the root -- and must not carry $LFS, which would be a path that exists
#    only on this workstation and would not resolve in the image at all.
interp=$(readelf -l a.out | grep 'program interpreter' || true)

case "${interp}" in
  *"${LFS}"*)
    fail "the loader path has ${LFS} baked into it: ${interp}" ;;
  *"/lib64/ld-linux-x86-64.so.2"*)
    echo "  ok: interpreter is /lib64/ld-linux-x86-64.so.2" ;;
  *)
    fail "unexpected program interpreter: ${interp:-none}" ;;
esac

# 2. The start files. Scrt1.o, crti.o and crtn.o all have to come out of
#    $LFS. Finding this workstation's would mean every binary chapter 6
#    produces starts with this machine's crt code.
crt_found=$(grep -E -o "${LFS}/lib.*/S?crt[1in].*succeeded" dummy.log | wc -l)

if [ "${crt_found}" -eq 3 ]; then
  echo "  ok: Scrt1.o, crti.o and crtn.o all came from ${LFS}"
else
  fail "expected 3 start files under ${LFS}, found ${crt_found}"
  grep -E -o "S?crt[1in]\.o.*succeeded" dummy.log >&2 || true
fi

# 3. The header search path ends at $LFS/usr/include and includes no
#    directory outside $LFS or $LFS/tools. This is the check that would have
#    caught vim finding the host's GTK3.
if grep -q "^ ${LFS}/usr/include\$" dummy.log; then
  echo "  ok: ${LFS}/usr/include is on the include path"
else
  fail "${LFS}/usr/include is not on the include search path"
fi

stray_include=$(sed -n '/#include <...> search starts here:/,/End of search list/p' dummy.log |
                grep '^ /' | grep -v "^ ${LFS}/" || true)

if [ -n "${stray_include}" ]; then
  fail "include path reaches outside ${LFS}:"
  echo "${stray_include}" >&2
else
  echo "  ok: no include directory outside ${LFS}"
fi

# 4. The linker's search directories. Every one has to begin with "=", which
#    is ld's marker for "prefix this with the sysroot" -- an entry without it
#    is an absolute path on this machine.
bad_search=$(grep -o 'SEARCH_DIR("[^"]*")' dummy.log |
             grep -v 'SEARCH_DIR("=' || true)

if [ -n "${bad_search}" ]; then
  fail "linker search directories not relative to the sysroot:"
  echo "${bad_search}" >&2
else
  echo "  ok: every linker search directory is sysroot-relative"
fi

# 5. The libc that was actually opened, and 6. the loader that was found.
if grep -q "attempt to open ${LFS}/usr/lib/libc.so.6 succeeded" dummy.log; then
  echo "  ok: linked against ${LFS}/usr/lib/libc.so.6"
else
  fail "did not link against ${LFS}/usr/lib/libc.so.6"
  grep "/libc.so.6 " dummy.log >&2 || true
fi

if grep -q "found ld-linux-x86-64.so.2 at ${LFS}/usr/lib/ld-linux-x86-64.so.2" dummy.log; then
  echo "  ok: loader found at ${LFS}/usr/lib/ld-linux-x86-64.so.2"
else
  fail "loader not found under ${LFS}"
  grep '^found ' dummy.log >&2 || true
fi

if [ "${sanity_failed}" -ne 0 ]; then
  echo >&2
  echo "the cross toolchain is not correctly aimed at ${LFS}." >&2
  echo "do not continue to chapter 6; the log is ${check_dir}/dummy.log" >&2
  trap - EXIT
  exit 1
fi

echo "  cross toolchain resolves entirely inside ${LFS}"
