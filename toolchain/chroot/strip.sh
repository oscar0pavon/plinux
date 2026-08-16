#!/bin/bash
#
# LFS 8.84: remove debugging symbols and unneeded symbol table entries.
#
# Optional in the book and not optional here -- lfs/ does not fit the VM
# image without it.
#
# The hazard is worth stating before the method. strip rewrites the file it
# is given, in place. If something has that file mapped -- and inside a
# chroot doing the stripping, bash and strip and libc certainly do -- the
# rewrite can crash it mid-write and destroy the binary. The book is blunt
# about the consequence: "this can make the system completely unusable".
#
# LFS avoids it by naming the files that will be in use (save_usrlib,
# online_usrbin, online_usrlib), copying those to /tmp, stripping the copies
# and installing them back, and stripping everything else in place. That
# works, and it carries a warning in bold that the lists are tied to the
# book's exact versions: "If there is any package whose version is different
# from the version specified by the book ... it may be necessary to update
# the library file name ... Failing to do so may render the system
# completely unusable."
#
# This image's versions are not the book's in several places, and the list
# would have to be re-checked against every package bump forever. So nothing
# is stripped in place here. Every file goes through a temporary copy and is
# put back with a rename, which is what makes it safe:
#
#   rename(2) replaces the directory entry, not the inode. Anything that
#   already has the old file mapped keeps the old inode alive and unchanged
#   until it exits. There is no window in which a mapped file is half
#   written, because no mapped file is ever written.
#
# The temporary lives in the same directory as its target, so the rename
# stays within one filesystem and cannot silently degrade into a copy.
#
# The cost is copying about a gigabyte. That is a few seconds and it buys
# not having a version-sensitive list of names that must never be wrong.

set -e

source /toolchain/common.sh

stripped=0
skipped=0
failed=0

# ELF only. Shell scripts, .pc files, terminfo entries and the like are most
# of /usr/bin by count and strip has nothing to do with any of them.
is_elf(){
  local magic
  magic=$(head -c4 "$1" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
  [ "${magic}" = "7f454c46" ]
}

strip_file(){
  local file=$1
  local temporary=${file}.strip.$$

  if [ -L "${file}" ] || [ ! -f "${file}" ]; then
    return 0
  fi

  if ! is_elf "${file}"; then
    skipped=$((skipped + 1))
    return 0
  fi

  # -p to carry mode, ownership and timestamps across, so the rename puts
  # back something indistinguishable from what was there apart from size.
  if ! cp -p "${file}" "${temporary}" 2>/dev/null; then
    failed=$((failed + 1))
    return 0
  fi

  # A file strip cannot handle -- already stripped, or an object format it
  # does not recognise -- is left exactly as it was.
  if strip --strip-unneeded "${temporary}" 2>/dev/null; then
    mv -f "${temporary}" "${file}"
    stripped=$((stripped + 1))
  else
    rm -f "${temporary}"
    skipped=$((skipped + 1))
  fi
}

before=$(du -sh /usr 2>/dev/null | cut -f1)

# /usr/lib/modules is excluded. Kernel modules carry symbol tables the module
# loader itself reads, and --strip-unneeded takes them: the module then fails
# to load rather than merely losing its debug information. The book does not
# strip them either.
#
# .dbg files are excluded because they are nothing but the symbols someone
# deliberately kept.
while IFS= read -r file; do
  strip_file "${file}"
done < <(
  {
    find /usr/lib -type f \( -name '*.so' -o -name '*.so.*' -o -name '*.a' \) \
         -not -path '/usr/lib/modules/*' -not -name '*.dbg'
    find /usr/bin /usr/sbin /usr/libexec -type f
  } 2>/dev/null
)

echo
echo "  stripped ${stripped}, skipped ${skipped}, failed ${failed}"
echo "  /usr ${before} -> $(du -sh /usr 2>/dev/null | cut -f1)"

if [ "${failed}" -ne 0 ]; then
  echo "  ${failed} file(s) could not be copied; nothing was written for those" >&2
fi
