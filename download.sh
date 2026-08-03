#!/bin/bash
#
# Fetch the LFS package tarballs and patches listed in wget-list-sysv.
#
# Follows LFS 12.4 section 3.1: wget --continue over the list, then verify
# against md5sums. Downloads are checked one at a time so a single bad mirror
# is reported by name instead of failing the whole run silently.

cd "$(dirname "$(readlink -f "$0")")" || exit 1

list=${LFS_LIST:-wget-list-sysv}
sources=${LFS_SOURCES:-sources}
sums=${LFS_SUMS:-md5sums}
failed_log=${sources}/.failed
tries=${LFS_TRIES:-3}
timeout=${LFS_TIMEOUT:-30}

usage(){
  cat <<'USAGE'
Usage: ./download.sh [command]

Downloads the sources listed in wget-list-sysv into sources/.

Commands:
  (none)      Download everything still missing. Already complete files are
              skipped, partial ones are resumed
  verify      Check sources/ against md5sums, if that file is present
  retry       Download only the entries that failed on the last run
  help        This message

Environment:
  LFS_LIST     list of URLs            (default wget-list-sysv)
  LFS_SOURCES  download directory      (default sources)
  LFS_SUMS     checksum file           (default md5sums)
  LFS_TRIES    attempts per file       (default 3)
  LFS_TIMEOUT  seconds per attempt     (default 30)

The md5sums file is not part of this repository. Fetch it from the same
release of the book as wget-list-sysv and place it beside this script to
enable verify.

Exit status is 0 only when every file was obtained.
USAGE
}

verify(){
  if [ ! -f "${sums}" ]; then
    echo "no ${sums} present, skipping verification" >&2
    return 0
  fi

  echo "verifying against ${sums}"

  # md5sums lists bare filenames, so it has to be checked from inside the
  # download directory
  ( cd "${sources}" && md5sum -c "../${sums}" )
  return $?
}

download(){
  local input=$1
  local total ok skipped bad url name tmp_failed

  total=$(grep -cve '^[[:space:]]*$' "${input}")
  ok=0
  skipped=0
  bad=0

  # Collected separately and moved into place at the end: in retry mode the
  # input *is* the failed log, and truncating it here would discard the list
  # before the loop reads it.
  tmp_failed=$(mktemp) || return 1

  local n=0
  while read -r url; do
    # tolerate blank lines and comments in a hand-edited list
    case "${url}" in ''|\#*) continue ;; esac

    n=$((n + 1))
    name=${url##*/}

    if [ -s "${sources}/${name}" ]; then
      printf '[%3d/%3d] have %s\n' "${n}" "${total}" "${name}"
      skipped=$((skipped + 1))
      continue
    fi

    printf '[%3d/%3d] get  %s\n' "${n}" "${total}" "${name}"

    if wget --continue \
            --tries="${tries}" \
            --timeout="${timeout}" \
            --quiet --show-progress \
            --directory-prefix="${sources}" \
            "${url}"; then
      ok=$((ok + 1))
    else
      echo "  FAILED ${url}" >&2
      echo "${url}" >> "${tmp_failed}"
      bad=$((bad + 1))
      # a failed transfer leaves a stub that would look complete next run
      [ -s "${sources}/${name}" ] || rm -f "${sources}/${name}"
    fi
  done < "${input}"

  mv "${tmp_failed}" "${failed_log}"

  echo
  echo "downloaded ${ok}, already present ${skipped}, failed ${bad}"

  if [ "${bad}" -ne 0 ]; then
    echo "failed URLs written to ${failed_log}; rerun with: ./download.sh retry" >&2
    return 1
  fi

  return 0
}

case "${1:-}" in
  help|-h|--help)
    usage
    exit 0
    ;;
  verify)
    verify
    exit $?
    ;;
  ''|retry)
    ;;
  *)
    echo "unknown command: $1" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac

if ! command -v wget > /dev/null; then
  echo "wget is required" >&2
  exit 1
fi

if ! mkdir -p "${sources}"; then
  echo "cannot create ${sources}" >&2
  exit 1
fi

if [ "${1:-}" == "retry" ]; then
  if [ ! -s "${failed_log}" ]; then
    echo "nothing to retry"
    exit 0
  fi
  echo "retrying $(grep -c . "${failed_log}") failed downloads"
  download "${failed_log}" || exit 1
else
  if [ ! -f "${list}" ]; then
    echo "${list} not found" >&2
    exit 1
  fi
  download "${list}" || exit 1
fi

verify
