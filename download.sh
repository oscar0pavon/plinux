#!/bin/bash
#
# Fetch the LFS package tarballs and patches listed in wget-list-sysv.
#
# Follows LFS 12.4 section 3.1: wget --continue over the list, then verify
# against md5sums. Downloads are checked one at a time so a single bad mirror
# is reported by name instead of failing the whole run silently.

cd "$(dirname "$(readlink -f "$0")")" || exit 1

# Split by what gets built, not by which book a package came from.
#
# wget-list-core is the console system, one line per entry in packages/order.
# wget-list-gui is the Wayland stack on top of it. wget-list-sysv is the LFS
# book's own list, still here but no longer downloaded by default: about
# sixty of its ninety-one entries are the chapter 5 and 6 temporary
# toolchain, which plinux does not build because it compiles against the host
# toolchain and stages into obj/. Fetching it costs several hundred megabytes
# that nothing unpacks. It stays in the tree as the starting point if the
# self-hosting toolchain is ever built: ./download.sh --list wget-list-sysv.
list_core=${CORE_LIST:-wget-list-core}
list_gui=${GUI_LIST:-wget-list-gui}
sources=${LFS_SOURCES:-sources}
sums=${LFS_SUMS:-md5sums}
failed_log=${sources}/.failed
tries=${LFS_TRIES:-3}
timeout=${LFS_TIMEOUT:-30}

# Separate from --timeout, which is the read timeout and is what a slow
# transfer needs. Reaching a host that is simply not there costs the whole of
# it, three times over, and ftpmirror.gnu.org is exactly that from here: 29
# of the URLs below go through it, so the run spent a minute and a half per
# GNU package waiting to be told what fallback_url already knows. Ten seconds
# is generous for a TCP handshake and turns each of those into a quick fall
# through to ftp.gnu.org.
connect_timeout=${LFS_CONNECT_TIMEOUT:-10}

# Seconds into "4m07s", the same shape build.sh reports its steps in.
format_duration(){
  local total=$1

  if [ "${total}" -ge 60 ]; then
    printf '%dm%02ds' $((total / 60)) $((total % 60))
  else
    printf '%ds' "${total}"
  fi
}

# A line pinned to the top of the terminal, the way build.sh pins the package
# being built: the scroll region is everything below row 1, so wget's own
# progress bars scroll underneath without disturbing it.
#
# It exists because wget says nothing at all between being started and the
# first byte arriving. A host that is not answering therefore looks exactly
# like one that is: the file's name is printed, and then the terminal sits
# there. With a clock on the line the difference is obvious, which matters
# most on the one list entry that is going to fail.
#
# Only when stdout is a terminal; redirected to a file these escapes would be
# noise in something worth keeping.
status_active=
status_text=

status_start(){
  [ -t 1 ] || return 0

  status_rows=$(tput lines 2>/dev/null) || status_rows=${LINES:-24}
  status_active=1

  printf '\e[2;%dr' "${status_rows}"
  printf '\e[%d;1H' "${status_rows}"

  # a shell left holding a scroll region behaves as if its top line were
  # stuck, so put it back however this exits, Ctrl-C included
  trap status_stop EXIT
  trap 'status_stop; exit 130' INT
  trap 'status_stop; exit 143' TERM
}

status_stop(){
  [ -n "${status_active}" ] || return 0
  status_active=

  printf '\e[r'
  printf '\e[1;1H\e[2K'
  printf '\e[%d;1H' "${status_rows}"
}

status_set(){
  [ -n "${status_active}" ] || return 0
  status_text=$1
  printf '\e7\e[1;1H\e[2K\e[7m %s \e[0m\e8' "$1"
}

usage(){
  cat <<'USAGE'
Usage: ./download.sh [command] [--list FILE]

Downloads the sources the build needs into sources/.

Commands:
  (none)      wget-list-core, the console system. Already complete files are
              skipped, partial ones are resumed
  gui         wget-list-gui, the Wayland stack, on its own
  all         Both of the above
  verify      Check sources/ against md5sums, if that file is present
  retry       Download only the entries that failed on the last run
  help        This message

Options:
  --list FILE  Download this list instead. Repeatable. This is how to fetch
               wget-list-sysv, the LFS book's own list, which is not part of
               any command because roughly sixty of its entries are the
               temporary toolchain plinux does not build

Environment:
  CORE_LIST    console system list      (default wget-list-core)
  GUI_LIST     Wayland stack list       (default wget-list-gui)
  LFS_SOURCES  download directory       (default sources)
  LFS_SUMS     checksum file            (default md5sums)
  LFS_TRIES    attempts per file        (default 3)
  LFS_TIMEOUT  seconds per attempt      (default 30)

A line is a URL, optionally followed by a filename to save it as. Forge
archive URLs end in the tag rather than the project, so seatd would
otherwise arrive as "0.9.1.tar.gz".

The md5sums file is not part of this repository. Fetch it from the same
release of the book as wget-list-sysv and place it beside this script to
enable verify. It lists only the book's tarballs, so anything in
wget-list-gui goes unverified, and several of those have no stable checksum
to record in the first place.

Exit status is 0 only when every file was obtained.
USAGE
}

# ftpmirror.gnu.org redirects to whichever mirror is nearest, and that
# redirect is not always reachable. ftp.gnu.org is the canonical host and
# carries everything; the path gains a /gnu component. 29 of the URLs in
# wget-list-sysv go through ftpmirror, so this is worth trying before
# calling a download failed.
fallback_url(){
  local file

  case "$1" in
    https://ftpmirror.gnu.org/*)
      echo "https://ftp.gnu.org/gnu/${1#https://ftpmirror.gnu.org/}"
      ;;
    https://download.savannah.gnu.org/*|https://download.savannah.nongnu.org/*)
      # savannah is not reachable from here either. Void's distfile mirror
      # keeps the same tarballs under <name>-<version>/<file>.
      file=${1##*/}
      echo "https://sources.voidlinux.org/${file%.tar.*}/${file}"
      ;;
  esac
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

  # comments as well as blank lines, or the [n/total] counter reads short
  # against a list that explains itself
  total=$(grep -cve '^[[:space:]]*$' -e '^[[:space:]]*#' "${input}")
  ok=0
  skipped=0
  bad=0

  # Collected separately and moved into place at the end: in retry mode the
  # input *is* the failed log, and truncating it here would discard the list
  # before the loop reads it.
  tmp_failed=$(mktemp) || return 1

  local started=${SECONDS}

  status_start
  status_set "starting"

  local n=0
  local rename
  while read -r url rename; do
    # tolerate blank lines and comments in a hand-edited list
    case "${url}" in ''|\#*) continue ;; esac

    n=$((n + 1))

    # An optional second field renames the file. Forge archive URLs end in
    # the tag rather than the project, so seatd arrives as "0.9.1.tar.gz" --
    # which says nothing in sources/ and matches nothing when a package
    # script looks for seatd-*.tar.gz. The tarball itself is fine; only the
    # URL's last component is useless.
    name=${rename:-${url##*/}}

    if [ -s "${sources}/${name}" ]; then
      printf '[%3d/%3d] have %s\n' "${n}" "${total}" "${name}"
      skipped=$((skipped + 1))
      continue
    fi

    printf '[%3d/%3d] get  %s\n' "${n}" "${total}" "${name}"
    status_set "${name}   [${n}/${total}]   ${url#https://}"

    # --continue only without a rename: wget refuses to resume into an
    # explicit -O target, and these archive URLs are small enough that
    # restarting one costs nothing.
    fetch(){
      local started=${SECONDS}
      local ticker=
      local status

      # The clock on the status line, redrawn once a second while wget has
      # the terminal. Started per attempt, so a fallback begins from zero
      # and the host being tried is the one named.
      if [ -n "${status_active}" ]; then
        (
          while :; do
            printf '\e7\e[1;1H\e[2K\e[7m %s   %s \e[0m\e8' \
              "${status_text}" "$(format_duration $((SECONDS - started)))"
            sleep 1
          done
        ) &
        ticker=$!
      fi

      if [ -n "${rename}" ]; then
        wget --tries="${tries}" \
             --timeout="${timeout}" \
             --connect-timeout="${connect_timeout}" \
             --quiet --show-progress \
             -O "${sources}/${name}" \
             "$1"
        status=$?
      else
        wget --continue \
             --tries="${tries}" \
             --timeout="${timeout}" \
             --connect-timeout="${connect_timeout}" \
             --quiet --show-progress \
             --directory-prefix="${sources}" \
             "$1"
        status=$?
      fi

      if [ -n "${ticker}" ]; then
        kill "${ticker}" 2>/dev/null
        wait "${ticker}" 2>/dev/null
      fi

      return ${status}
    }

    alternate=$(fallback_url "${url}")

    if fetch "${url}"; then
      ok=$((ok + 1))
    elif [ -n "${alternate}" ] && printf '  retrying via %s\n' "${alternate}" \
         && status_set "${name}   [${n}/${total}]   ${alternate#https://}" \
         && fetch "${alternate}"; then
      ok=$((ok + 1))
    else
      echo "  FAILED ${url}" >&2
      # the rename goes into the log too, so retry parses it the same way
      echo "${url} ${rename}" >> "${tmp_failed}"
      bad=$((bad + 1))
      # a failed transfer leaves a stub that would look complete next run
      [ -s "${sources}/${name}" ] || rm -f "${sources}/${name}"
    fi
  done < "${input}"

  status_stop

  mv "${tmp_failed}" "${failed_log}"

  echo
  echo "downloaded ${ok}, already present ${skipped}, failed ${bad} in $(format_duration $((SECONDS - started)))"

  if [ "${bad}" -ne 0 ]; then
    echo "failed URLs written to ${failed_log}; rerun with: ./download.sh retry" >&2
    return 1
  fi

  return 0
}

wanted=()
command=

while [ $# -gt 0 ]; do
  case "$1" in
    --list)
      if [ -z "${2:-}" ]; then
        echo "--list needs a file" >&2
        exit 1
      fi
      wanted+=("$2")
      shift 2
      ;;
    help|-h|--help)
      usage
      exit 0
      ;;
    verify)
      verify
      exit $?
      ;;
    gui|all|retry)
      command=$1
      shift
      ;;
    *)
      echo "unknown command: $1" >&2
      echo >&2
      usage >&2
      exit 1
      ;;
  esac
done

# --list on its own replaces the default rather than adding to it; naming a
# command as well asks for both.
case "${command}" in
  gui)   wanted+=("${list_gui}") ;;
  all)   wanted+=("${list_core}" "${list_gui}") ;;
  retry) ;;
  *)     [ ${#wanted[@]} -eq 0 ] && wanted=("${list_core}") ;;
esac

if ! command -v wget > /dev/null; then
  echo "wget is required" >&2
  exit 1
fi

if ! mkdir -p "${sources}"; then
  echo "cannot create ${sources}" >&2
  exit 1
fi

if [ "${command}" == "retry" ]; then
  if [ ! -s "${failed_log}" ]; then
    echo "nothing to retry"
    exit 0
  fi
  echo "retrying $(grep -c . "${failed_log}") failed downloads"
  download "${failed_log}" || exit 1
else
  for one in "${wanted[@]}"; do
    if [ ! -f "${one}" ]; then
      echo "${one} not found" >&2
      exit 1
    fi
  done

  # Joined into one input rather than calling download once per list: it
  # writes the failed log at the end of a run, so a second call would replace
  # the first list's failures instead of adding to them, and "retry" would
  # then skip them silently.
  joined=$(mktemp) || exit 1
  trap 'rm -f "${joined}"' EXIT
  cat "${wanted[@]}" > "${joined}"

  download "${joined}" || exit 1
fi

verify
