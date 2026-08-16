#!/bin/bash
#
# LFS 7.13.1 and 8.85: everything the build needed and the system does not.
#
# Not in toolchain/chroot/order, and deliberately. That file is chapter 7,
# which runs *before* chapter 8; this runs after it, and running it early
# would delete the compiler chapter 8 is about to be built with. It is
# reached only by naming it: ./build.sh chroot cleanup.
#
# Everything here is idempotent -- it removes things, and removing what is
# already gone is not an error -- so a second run is free.

set -e

source /toolchain/common.sh

report(){
  printf '  %-28s %s\n' "$1" "$2"
}

before=$(du -sh / 2>/dev/null | cut -f1)

# LFS 7.13.1. /tools is the chapter 5 cross toolchain: a compiler that runs
# on the build host and produces target code. Chapter 6 replaced it with one
# that runs here, chapter 8 replaced that with the real one, and nothing has
# needed /tools since the chroot was entered -- it is not even on PATH.
if [ -d /tools ]; then
  report "/tools" "$(du -sh /tools 2>/dev/null | cut -f1)"
  rm -rf /tools
fi

# LFS 8.85. The chapter 6 toolchain installed a second time under its target
# triplet -- /usr/x86_64-lfs-linux-gnu and friends. Partially installed,
# superseded by chapter 8's native binutils and gcc, and confusing to leave
# behind: it is the same programs under a name that implies cross-compiling.
#
# -depth so directories are removed after their contents.
triplet=$(uname -m)-lfs-linux-gnu
stale=$(find /usr -depth -name "${triplet}*" 2>/dev/null || true)

if [ -n "${stale}" ]; then
  report "${triplet}*" "$(echo "${stale}" | wc -l) paths"
  echo "${stale}" | xargs rm -rf
fi

# libtool archives. On a modern system these are useful only to libltdl,
# nothing here is loaded by libltdl, and they carry build-time paths that
# break BLFS packages which read them. The book removes them; so does
# toolchain/libstdcxx.sh, for the same reason, one directory at a time.
la_count=$(find /usr/lib /usr/libexec -name '*.la' 2>/dev/null | wc -l)

if [ "${la_count}" -ne 0 ]; then
  report "*.la" "${la_count} files"
  find /usr/lib /usr/libexec -name '*.la' -delete
fi

# The tester account, created in chapter 7 so chapter 8's test suites had a
# non-root user to run as.
#
# The book says "userdel -r tester". There is no userdel here: shadow is not
# built, because plinux has plogin and a single-user /etc/passwd. So the two
# lines and the home directory go by hand, which is all userdel would have
# done.
# Checked per file rather than once, because the two do not necessarily agree.
# build.sh stages sys/etc over this /etc, and sys/etc/passwd is plinux's
# two-line version -- so by the time this runs, /etc/passwd may already have
# lost the tester line while /etc/group still carries it. Guarding both on
# /etc/passwd left tester in /etc/group, which is exactly what happened.
for account_file in /etc/passwd /etc/group; do
  if grep -q '^tester:' "${account_file}"; then
    report "tester in ${account_file}" "removed"
    sed -i '/^tester:/d' "${account_file}"
  fi
done

rm -rf /home/tester

# Test leftovers. Written as two globs rather than the book's /tmp/{*,.*}
# because that one also matches . and .., and rm complains about both.
rm -rf /tmp/* /tmp/.[!.]*

# Not the book's: the trees chapter 8 unpacked into. /sources-build is
# packages/common.sh's src_directory inside the chroot and /var/tmp/toolchain
# is chapter 7's, and between them they hold ninety unpacked tarballs that
# have already been built and installed.
for tree in /sources-build /var/tmp/toolchain; do
  if [ -d "${tree}" ]; then
    report "${tree}" "$(du -sh "${tree}" 2>/dev/null | cut -f1)"
    rm -rf "${tree}"
  fi
done

echo
echo "  ${before} -> $(du -sh / 2>/dev/null | cut -f1)"
