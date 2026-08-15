#!/bin/bash
# uses pushd/popd and [ "$1" == ... ], so it needs bash and not plain sh

export MAKEFLAGS=-j32

# Resolve to the repository root rather than the caller's directory, so the
# script works from anywhere. Taking $(pwd) meant running it as
# ../build.sh from virtual_machine/ looked for virtual_machine/obj.
cd "$(dirname "$(readlink -f "$0")")" || exit 1

working_directory=$(pwd)
src_directory=${working_directory}/src
build_directory=${working_directory}/obj
sources_directory=${working_directory}/sources

# $LFS for the chapter 5 cross toolchain, and eventually for the chroot that
# replaces this build model. Deliberately not obj/: the two trees are built by
# different toolchains and obj/ stays bootable while lfs/ is being grown.
lfs_directory=${LFS:-${working_directory}/lfs}

# Where the redistributable firmware blobs are taken from, and which ones.
# The build host is the machine the image is for, so what it loads is what
# the image needs.
#
#   amdgpu       the Radeon card. DRM_AMDGPU is a module and will not
#                initialise without these, 57M of them
#   iwlwifi-so-a0-gf-a0-*
#                Intel Wi-Fi 6E AX211. CONFIG_IWLWIFI is built in, so there
#                is no module to load, but the firmware still has to be here
#                or the radio never comes up and iwd has nothing to drive.
#                The whole API-version family, not just the -89 this kernel
#                asks for today: the driver walks down from the newest it
#                knows to the first one present, so a kernel change would
#                otherwise silently lose the adapter
#   regulatory.db
#                cfg80211 loads it separately from any driver; without it
#                the regulatory domain falls back to the most restrictive
#                set of channels
firmware_source=${FIRMWARE_SOURCE:-/usr/lib/firmware}
firmware_wanted=(amdgpu iwlwifi-so-a0-gf-a0-*.ucode regulatory.db regulatory.db.p7s)

pushd(){
  command pushd "$@" > /dev/null
}

popd(){
  command popd "$@" > /dev/null
}

usage(){
  cat <<'USAGE'
Usage: ./build.sh [command]

Builds plinux into obj/, which is the staged root filesystem.

Commands:
  (none)      Build everything into obj/: this project's own components --
              pboot, the kernel, pinit, pdaemon, pgetty, plogin -- then any
              package in packages/order not yet installed, then sys/ on top.
              The stamps keep the package walk cheap, so with the packages
              built this is the quick component build it always was
  virt        Copy obj/ and the bootloader into virtual_machine/disk.raw.
              Builds nothing, so run a plain ./build.sh first if any
              source changed
  usb <dev>   Write obj/ to a USB disk as a bootable rescue system. Erases
              the device, which must be named in full: there is no default.
              Partitions it GPT, makes the filesystems, then writes a
              pboot.conf and an /etc/fstab carrying that disk's own
              identifiers, so the stick boots itself and not the machine it
              is plugged into. USB_YES=1 skips the typed confirmation
  packages    Build the LFS packages listed in packages/order into obj/.
              Already-installed ones are skipped. On a terminal the package
              being built is shown on a line pinned to the top of the screen

                packages <name>   rebuild just that one, skipped or not
                packages force    rebuild every one of them

              "Installed" means a stamp in obj/.packages, so "clean all"
              makes the next run build everything again. Cleaning the
              source trees does not: they unpack again when needed
  quiet       Not a command: add it to any of the above, or set VERBOSE=0,
              to only log build output instead of streaming it. Output is
              streamed by default; "verbose" is accepted and is the default
  check       Report installed binaries whose shared libraries are missing
              from obj/. Those programs build and install cleanly but fail
              at startup, so nothing else notices. Exits non-zero if any
  clean       Clean the cloned source trees and bash's configure output,
              and delete the unpacked package trees, which unpack again
              from sources/ on the next build
  clean all   As above, and delete obj/ entirely. It does not touch lfs/:
              the cross toolchain is hours of work and is not something to
              lose to a command aimed at the package tree
  toolchain   Build the LFS chapter 5 cross toolchain into lfs/, following
              toolchain/order. Each step is stamped in lfs/.toolchain and
              runs under "env -i", so nothing this workstation exports
              reaches it. Not part of a plain build: it is built once and
              then used

                toolchain <name>  rebuild just that step
                toolchain force   rebuild all of them

  chroot      Mount the virtual kernel filesystems into lfs/ and chroot into
              it, per LFS 7.3 and 7.4. Needs root. sources/ and
              toolchain/chroot/ are bind mounted read-only inside so the
              tarballs and step scripts are reachable. The mounts come back
              down on every exit path, and "clean" refuses to run while any
              of them is up

                chroot            interactive shell in lfs/
                chroot build      run toolchain/chroot/order inside it
                chroot <name>     run just that step
                chroot umount     take the mounts down by hand

  help        This message

Notes:
  Can be run from any directory; paths resolve relative to the script.
  virt needs root: it uses losetup and mount.
  Components are built with MAKEFLAGS=-j32.

Examples:
  ./build.sh              # full build into obj/
  ./build.sh virt         # push obj/ into the VM image
  ./build.sh clean all    # start over
  ./build.sh toolchain    # build the chapter 5 cross toolchain into lfs/
USAGE
}

if [ "$1" == "help" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
  usage
  exit 0
fi

# Without this an unrecognised argument falls through to a full build, so a
# typo like "./build.sh vrit" rebuilds everything instead of staging the image
case "${1:-}" in
  ""|virt|usb|clean|toolchain|chroot|packages|check|verbose|quiet) ;;
  *)
    echo "unknown command: $1" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac

# Build output is streamed by default. It still goes to logs/ either way, but
# watching a compile happen is worth more than a clean screen, and a build that
# has silently stalled is otherwise indistinguishable from one that is working.
#
# "quiet" turns it off, and either word may appear as any argument, so both
# combine with force and all. VERBOSE=0 in the environment also silences it.
verbose=1

if [ "${VERBOSE:-1}" == "0" ]; then
  verbose=
fi

for argument in "$@"; do
  case "${argument}" in
    verbose) verbose=1 ;;
    quiet)   verbose=  ;;
  esac
done

log_directory=${working_directory}/logs
mkdir -p "${log_directory}"

failed=0
skipped=0

# Seconds into "4m07s". Every build step reports how long it took and the
# build its total, because "the packages take about 40 minutes" was measured
# once by hand and then repeated from memory: a build that prints its own
# times is one that can say when it got slower.
format_duration(){
  local total=$1

  if [ "${total}" -ge 60 ]; then
    printf '%dm%02ds' $((total / 60)) $((total % 60))
  else
    printf '%ds' "${total}"
  fi
}

# Output goes to a log rather than /dev/null, and only the tail is shown when
# something breaks. Discarding it meant a failed build was reported as nothing
# more than the "cp" that came after it.
run(){
  local name=$1
  shift

  local started=${SECONDS}
  local status

  # While the step runs, redraw the status line once a second with the
  # step's elapsed time and the build's total. A forked loop rather than
  # anything cleverer: SECONDS keeps counting in a subshell, and the step
  # itself has the terminal, so this is the only way the clock can move
  # while make has the foreground. In quiet mode it is the only sign of
  # life the terminal gives at all.
  #
  # The pid is global, not local: an interrupt leaves this function through
  # the trap rather than through the kill below, and status_stop has to be
  # able to find it.
  if [ -n "${status_active}" ]; then
    (
      while :; do
        printf '\e7\e[1;1H\e[2K\e[7m %s   %s, build %s \e[0m\e8' \
          "${status_text}" \
          "$(format_duration $((SECONDS - started)))" \
          "$(format_duration ${SECONDS})"
        sleep 1
      done
    ) &
    status_ticker=$!
  fi

  if [ -n "${verbose}" ]; then
    # tee so the log is still written for later. The status has to come from
    # PIPESTATUS: in a pipeline $? is tee's, which succeeds even when the
    # build it is printing has failed.
    "$@" 2>&1 | tee "${log_directory}/${name}.log"
    status=${PIPESTATUS[0]}
  else
    "$@" > "${log_directory}/${name}.log" 2>&1
    status=$?
  fi

  ticker_stop

  if [ "${status}" -eq 0 ]; then
    # the log name doubles as the step name; packages arrive as package-<name>
    echo "  ${name#package-}: $(format_duration $((SECONDS - started)))"
    return 0
  fi

  echo "  FAILED: $*" >&2

  # in verbose mode the output has already gone past
  if [ -z "${verbose}" ]; then
    echo "  last lines of ${log_directory}/${name}.log:" >&2
    sed 's/^/    /' <<< "$(tail -15 "${log_directory}/${name}.log")" >&2
  fi

  return 1
}

# A line pinned to the top of the terminal naming the package being built.
# Build output scrolls underneath it: the terminal's scroll region is set to
# everything below row 1, so nothing can overwrite the status.
#
# Only when stdout is a terminal. Redirected to a file or a pipe these escapes
# would just be noise in the log.
status_active=

status_start(){
  [ -t 1 ] || return 0

  status_rows=$(tput lines 2>/dev/null) || status_rows=${LINES:-24}
  status_active=1

  printf '\e[2;%dr' "${status_rows}"   # scroll region: row 2 to the bottom
  printf '\e[%d;1H' "${status_rows}"   # park the cursor inside it

  # restore the terminal however this exits, including Ctrl-C: a shell left
  # with a scroll region set behaves as if the top line were stuck
  trap status_stop EXIT
  trap 'status_stop; exit 130' INT
  trap 'status_stop; exit 143' TERM
}

status_stop(){
  ticker_stop

  [ -n "${status_active}" ] || return 0
  status_active=

  printf '\e[r'                        # whole screen scrolls again
  printf '\e[1;1H\e[2K'                # wipe the status row
  printf '\e[%d;1H' "${status_rows}"
}

# The ticker is a background job, and bash gives a background job started by
# a non-interactive shell an ignored SIGINT. Ctrl-C therefore kills whatever
# is compiling, runs the INT trap, and leaves the clock running: it goes on
# redrawing row 1 over the shell prompt of a script that has already exited,
# and nothing left on screen says where it came from.
#
# Killed here rather than only where it is started, because that line is the
# one an interrupt skips. status_stop is what all three traps call.
status_ticker=

ticker_stop(){
  [ -n "${status_ticker}" ] || return 0

  kill "${status_ticker}" 2>/dev/null
  wait "${status_ticker}" 2>/dev/null
  status_ticker=
}

# \e7 and \e8 save and restore the cursor, so writing the status does not
# disturb where the build output is being written.
#
# The text is kept in status_text as well as printed, so the ticker in run()
# can redraw the same line with the elapsed time appended.
status_text=

status_set(){
  [ -n "${status_active}" ] || return 0
  status_text=$1
  printf '\e7\e[1;1H\e[2K\e[7m %s \e[0m\e8' "$1"
}

mkdir -p obj/usr/bin obj/usr/lib obj/usr/sbin

# The /bin -> /usr/bin merge, as four symlinks.
#
# The target is "usr/bin", not "../../../usr/bin". Both resolve to /usr/bin
# once the tree is the root filesystem -- ".." at "/" is "/" -- but only the
# relative form also resolves correctly when the tree is read from here, as
# obj/usr/bin. The ../../.. form escapes obj entirely and lands on the build
# machine's own /usr, which is why "ls obj/bin" once reported tar and ps as
# installed when neither was: it was listing the host's /usr/bin.
#
# That escape is not only a reporting problem. Anything that searches the
# staged tree by path -- a --sysroot link, INSTALL_MOD_PATH, a check against
# the image's libraries -- silently reaches the host through it, and succeeds,
# because this machine runs plinux and its libraries are the right ones. It
# would only fail in the VM or off the rescue USB.
#
# Repaired unconditionally: trees built before this still hold the old form.
for link in bin:usr/bin sbin:usr/sbin lib:usr/lib lib64:usr/lib;do
  link_name=obj/${link%%:*}
  link_target=${link#*:}

  # obj/sbin used to be a real directory, which left /sbin/ip and /sbin/udevd
  # unreachable. Only replaced when empty, so nothing installed there is lost.
  if [ -d "${link_name}" ] && [ ! -L "${link_name}" ];then
    rmdir "${link_name}" 2>/dev/null || {
      echo "${link_name} is a non-empty directory; expected a symlink to ${link_target}" >&2
      exit 1
    }
  fi

  if [ "$(readlink "${link_name}" 2>/dev/null)" != "${link_target}" ];then
    ln -sfn "${link_target}" "${link_name}"
  fi
done

# Mount points and standard directories. pinit mounts tmpfs on /run and
# sysfs on /sys, and a mount whose target does not exist just fails, which is
# how udev ended up unable to create /run/udev. Done unconditionally so trees
# made before these were listed get them too.
mkdir -p obj/{dev,proc,sys,run,var,var/log,boot,mnt,etc,root}

# /var/run is where programs written before /run existed still look. iwd is
# one: the ell it bundles compiles in unix:path=/var/run/dbus/system_bus_socket
# while dbus listens on /run/dbus/system_bus_socket, so without this iwd
# reports "Failed to initialize D-Bus" and exits. Relative, like /bin and
# /lib, so it resolves in the image rather than in obj.
if [ ! -e obj/var/run ]; then
  ln -sf ../run obj/var/run
fi
mkdir -p obj/tmp && chmod 1777 obj/tmp

# The kernel's userspace API headers -- linux/, asm/, asm-generic/, drm/ and
# the rest of uapi. Every package that speaks to the kernel by structure
# rather than through libc needs them, and the GUI stack is nothing but: DRM
# ioctls, evdev, memfd_create.
#
# These were never staged. Everything built so far found them in the build
# machine's /usr/include instead, and nothing complained, because that is a
# copy of the same headers. Under --sysroot it is the first thing to fail,
# and correctly so: obj was never a complete place to compile against.
#
# INSTALL_HDR_PATH ends in /usr because the kernel appends "include" to it.
stage_kernel_headers(){
  [ -d "${src_directory}/linux" ] || return 0

  local status=0

  pushd "${src_directory}/linux"
  make headers_install INSTALL_HDR_PATH="${build_directory}/usr" > /dev/null || status=$?
  popd

  return ${status}
}

# Cheap, but not free, so only when they are absent -- the kernel step below
# refreshes them whenever the kernel itself is rebuilt. input.h is the check
# because it is the one libinput and libevdev fail on.
if [ ! -f obj/usr/include/linux/input.h ];then
  echo "Installing kernel headers into obj/usr/include"
  stage_kernel_headers || echo "kernel headers not installed" >&2
fi

if [ -d obj ];then

  musl_directory=${build_directory}

  target=$(uname -m)-plinux-gnu
fi

# Every shared library an installed binary names has to be in the image too.
# Getting this wrong is silent: the package builds against the host's copy,
# installs cleanly, and the program only fails when someone runs it. That is
# how kmod shipped unable to start, and how dmesg and lsblk went unnoticed.
if [ "$1" == "check" ]; then
  echo "Checking installed binaries against the image's libraries"

  unresolved=0
  mixed=0
  checked=0

  for binary in ${build_directory}/usr/bin/* ${build_directory}/usr/sbin/* \
                ${build_directory}/usr/lib/*.so*; do
    [ -f "${binary}" ] || continue

    # skips scripts, symlinks and the static ones, which have no NEEDED
    readelf -d "${binary}" > /dev/null 2>&1 || continue

    checked=$((checked + 1))

    needed=$(readelf -d "${binary}" 2>/dev/null |
             sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')

    # Two C libraries in one image means a binary can name one and be loaded
    # by the other, and the check above cannot see it: both libc.so.6 and
    # musl's loader are present, so every name resolves and the program still
    # dies at startup. This is not hypothetical -- it is what LDFLAGS did to
    # every musl package for as long as obj/usr/lib came first on the link
    # line, since that is where glibc's libc.so is.
    interpreter=$(readelf -l "${binary}" 2>/dev/null |
                  sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')

    case "${interpreter}" in
      *ld-musl*)
        if grep -q '^libc\.so\.6$' <<< "${needed}"; then
          echo "  ${binary#${build_directory}} is musl but needs glibc's libc.so.6"
          mixed=$((mixed + 1))
        fi
        ;;
      *ld-linux*)
        if grep -qx 'libc\.so' <<< "${needed}"; then
          echo "  ${binary#${build_directory}} is glibc but needs musl's libc.so"
          mixed=$((mixed + 1))
        fi
        ;;
    esac

    for library in ${needed}; do
      # the loader itself is named by absolute path and lives in /usr/lib
      case "${library}" in ld-*) continue ;; esac

      # musl's libc.so is its loader, which is already mapped by the time a
      # NEEDED is looked at; it lives in /usr/lib/musl and is resolved by
      # name rather than found on the search path
      if [ "${library}" == "libc.so" ] && [ -e "${build_directory}/usr/lib/musl/libc.so" ]; then
        continue
      fi

      if [ ! -e "${build_directory}/usr/lib/${library}" ]; then
        echo "  ${binary#${build_directory}} needs ${library}"
        unresolved=$((unresolved + 1))
      fi
    done
  done

  echo
  echo "checked ${checked} binaries"

  if [ "${mixed}" -ne 0 ]; then
    echo "${mixed} binary(s) mix the two C libraries" >&2
    echo "those were linked against the wrong libc and cannot start" >&2
    exit 1
  fi

  if [ "${unresolved}" -ne 0 ]; then
    echo "${unresolved} unresolved dependencies" >&2
    echo "each of those programs fails at startup in the image" >&2
    exit 1
  fi

  echo "every dependency resolves inside the image"
  exit
fi

# The packages walk, shared by "./build.sh packages" and the plain build,
# which runs it after the components so that one command produces the whole
# image.
#
# The first argument selects what to rebuild: empty for whatever is not
# stamped, "force" for everything, a package name for just that one.
# "brief" as the second collapses the per-package "have" lines into one
# count; the plain build passes it, because 68 lines of "have" would bury
# the component output around them.
build_packages(){
  local package_selector=${1:-}
  local package_brief=${2:-}

  echo "Building packages"

  # A package that installed successfully leaves a stamp, so a rerun picks up
  # where it stopped instead of rebuilding everything. "packages force"
  # ignores them.
  #
  # The stamps live inside obj because that is what they are a statement
  # about: this package is installed in *this* tree. Keeping them under logs/
  # meant "clean all" removed obj and left the stamps behind, so every package
  # reported "have" while the tree stayed empty. The leading dot keeps them
  # out of the "cp -a obj/*" that populates the image.
  local stamp_directory=${build_directory}/.packages
  mkdir -p "${stamp_directory}"

  # verbose and quiet are not selectors, they are the output setting handled
  # above, passed through when the command line reads "packages quiet"
  local package_force=
  local package_only=

  case "${package_selector}" in
    ''|verbose|quiet) ;;
    force)            package_force=1 ;;
    *)                package_only=${package_selector} ;;
  esac

  local package_total
  package_total=$(grep -cv -e '^[[:space:]]*$' -e '^[[:space:]]*#' \
                    "${working_directory}/packages/order")

  local package_number=0
  local package_matched=
  local package_have=0
  local package_failed=0
  local packages_started=${SECONDS}
  local script

  # In the plain build the components have already put the status line up;
  # only start (and later stop) one here when running standalone, so the
  # line survives into the steps that follow the walk.
  local status_was_active=${status_active}

  [ -z "${status_was_active}" ] && status_start
  status_set "starting"

  while read -r package; do
    case "${package}" in ''|\#*) continue ;; esac

    package_number=$((package_number + 1))

    # naming one package builds only it, whatever its stamp says
    if [ -n "${package_only}" ]; then
      if [ "${package}" != "${package_only}" ]; then
        continue
      fi
      package_matched=1
    fi

    script=${working_directory}/packages/${package}.sh

    if [ ! -x "${script}" ]; then
      echo "  ${package}: no ${script}" >&2
      package_failed=$((package_failed + 1))
      continue
    fi

    if [ -f "${stamp_directory}/${package}" ] &&
       [ -z "${package_force}" ] && [ -z "${package_only}" ]; then
      if [ -n "${package_brief}" ]; then
        package_have=$((package_have + 1))
      else
        echo "  have ${package}"
      fi
      continue
    fi

    # The tarballs are downloaded, not tracked, so a fresh clone has none --
    # and a plain ./build.sh walks the packages now, so that clone reaches
    # this loop rather than stopping at a step it was never told to run.
    # Checked once, and only when there is something to build: a tree whose
    # packages are all stamped needs no sources at all, which is the state
    # "./build.sh clean" leaves behind.
    if [ -z "${sources_checked}" ]; then
      sources_checked=1

      if ! ls "${sources_directory}"/*.tar.* > /dev/null 2>&1; then
        status_stop
        echo "no source tarballs in ${sources_directory}" >&2
        echo "run ./download.sh all first; ./configure too, if src/linux is missing" >&2
        exit 1
      fi
    fi

    echo "  ${package}"
    status_set "${package}   [${package_number}/${package_total}]"

    if run "package-${package}" "${script}"; then
      touch "${stamp_directory}/${package}"
    else
      package_failed=$((package_failed + 1))
      status_set "${package}   [${package_number}/${package_total}]   FAILED"
      # later packages link against earlier ones, so carrying on would only
      # produce a second, more confusing failure
      break
    fi
  done < "${working_directory}/packages/order"

  [ -z "${status_was_active}" ] && status_stop

  if [ "${package_have}" -ne 0 ]; then
    echo "  ${package_have} already installed"
  fi

  echo

  # a name that is in no order file is a typo, not a request to build nothing
  if [ -n "${package_only}" ] && [ -z "${package_matched}" ]; then
    echo "no such package: ${package_only}" >&2
    echo "packages are listed in ${working_directory}/packages/order" >&2
    exit 1
  fi

  if [ "${package_failed}" -ne 0 ]; then
    echo "${package_failed} package(s) failed; logs are in ${log_directory}" >&2
    exit 1
  fi

  echo "packages installed into ${build_directory} in $(format_duration $((SECONDS - packages_started)))"
}

# The LFS chapter 5 cross toolchain, built into lfs/ rather than obj/.
#
# Alongside, not in place: obj/ holds a system that boots and it keeps booting
# until this one can replace it. The two trees never touch.
#
# Every step runs under "env -i". That is not tidiness -- it is the same
# discipline as the sysroot in packages/common.sh, applied to the environment
# instead of the search path. This workstation's PATH carries rust, go, the
# jdk, rocm, texlive and /musl/bin, and its shell exports MAKEFLAGS, CFLAGS
# and a locale. Any of those reaching a configure script in chapter 5 is a
# decision made by this machine about the compiler that is supposed to be
# independent of it. toolchain/common.sh rebuilds the environment the book
# specifies from nothing.
build_toolchain(){
  local toolchain_selector=${1:-}

  echo "Building the cross toolchain into ${lfs_directory}"

  local stamp_directory=${lfs_directory}/.toolchain
  mkdir -p "${stamp_directory}"

  local toolchain_force=
  local toolchain_only=

  case "${toolchain_selector}" in
    ''|verbose|quiet) ;;
    force)            toolchain_force=1 ;;
    *)                toolchain_only=${toolchain_selector} ;;
  esac

  local toolchain_total
  toolchain_total=$(grep -cv -e '^[[:space:]]*$' -e '^[[:space:]]*#' \
                      "${working_directory}/toolchain/order")

  local toolchain_number=0
  local toolchain_matched=
  local toolchain_have=0
  local toolchain_started=${SECONDS}
  local script

  local status_was_active=${status_active}
  [ -z "${status_was_active}" ] && status_start
  status_set "starting"

  while read -r step; do
    case "${step}" in ''|\#*) continue ;; esac

    toolchain_number=$((toolchain_number + 1))

    if [ -n "${toolchain_only}" ]; then
      if [ "${step}" != "${toolchain_only}" ]; then
        continue
      fi
      toolchain_matched=1
    fi

    script=${working_directory}/toolchain/${step}.sh

    if [ ! -x "${script}" ]; then
      status_stop
      echo "  ${step}: no ${script}" >&2
      exit 1
    fi

    if [ -f "${stamp_directory}/${step}" ] &&
       [ -z "${toolchain_force}" ] && [ -z "${toolchain_only}" ]; then
      echo "  have ${step}"
      toolchain_have=$((toolchain_have + 1))
      continue
    fi

    echo "  ${step}"
    status_set "${step}   [${toolchain_number}/${toolchain_total}]"

    # HOME and TERM are the only two carried through. TERM because the book
    # carries it and because make's output is unreadable without it; HOME
    # because a configure script that cannot find one occasionally writes
    # into /, and that is the host.
    if run "toolchain-${step}" \
         env -i HOME="${HOME}" TERM="${TERM:-dumb}" \
                LFS="${lfs_directory}" \
                MAKEFLAGS="-j$(nproc)" \
                /bin/bash "${script}"; then
      touch "${stamp_directory}/${step}"
    else
      status_set "${step}   [${toolchain_number}/${toolchain_total}]   FAILED"
      status_stop
      echo >&2
      echo "${step} failed; the log is ${log_directory}/toolchain-${step}.log" >&2
      # Each step here is the ground the next one stands on -- a glibc that
      # did not install cannot be compensated for by carrying on to
      # libstdc++ -- so this stops rather than counting failures.
      exit 1
    fi
  done < "${working_directory}/toolchain/order"

  [ -z "${status_was_active}" ] && status_stop

  if [ "${toolchain_have}" -ne 0 ]; then
    echo "  ${toolchain_have} already built"
  fi

  echo

  if [ -n "${toolchain_only}" ] && [ -z "${toolchain_matched}" ]; then
    echo "no such toolchain step: ${toolchain_only}" >&2
    echo "steps are listed in ${working_directory}/toolchain/order" >&2
    exit 1
  fi

  echo "cross toolchain built in $(format_duration $((SECONDS - toolchain_started)))"
}

if [ "$1" == "toolchain" ]; then
  build_toolchain "${2:-}"
  exit
fi

# LFS chapter 7: the chroot.
#
# Everything above this point builds *for* lfs/ from the outside. From here on
# the work happens inside it, with lfs/ as / and the host kernel the only
# thing still shared. That is the whole point of the exercise -- there is no
# host /usr to find any more, because there is no host.
#
# The mounts are the dangerous part of this file. A bind mount of /dev inside
# a directory this repository also deletes things in is worth being careful
# about, so:
#
#   - only what LFS 7.3 lists is mounted, plus two read-only binds so the
#     scripts and tarballs are reachable from inside
#   - the repository is mounted read-only, so nothing in the chroot can write
#     back out into it
#   - unmounting is checked rather than hoped for, runs in reverse order, and
#     happens on every exit path including a failed build
#   - "clean" refuses to run while any of it is mounted
chroot_mounts(){
  # Reverse order of mounting: dev/shm and dev/pts sit inside dev.
  echo "${lfs_directory}/dev/shm" \
       "${lfs_directory}/dev/pts" \
       "${lfs_directory}/dev"     \
       "${lfs_directory}/proc"    \
       "${lfs_directory}/sys"     \
       "${lfs_directory}/run"     \
       "${lfs_directory}/sources" \
       "${lfs_directory}/toolchain"
}

chroot_mounted_any(){
  local point
  for point in $(chroot_mounts); do
    if mountpoint -q "${point}" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

chroot_umount(){
  local point
  local status=0

  for point in $(chroot_mounts); do
    if mountpoint -q "${point}" 2>/dev/null; then
      if ! umount "${point}" 2>/dev/null; then
        # A second try after a moment: something in the chroot may still be
        # exiting and holding a file open.
        sleep 1
        if ! umount "${point}" 2>/dev/null; then
          echo "cannot unmount ${point}" >&2
          echo "something is still using it; lsof +f -- ${point}" >&2
          status=1
        fi
      fi
    fi
  done

  return ${status}
}

chroot_mount(){
  if [ "$(id -u)" -ne 0 ]; then
    echo "the chroot needs root: it mounts /dev, /proc and /sys into lfs/" >&2
    exit 1
  fi

  if [ ! -x "${lfs_directory}/usr/bin/bash" ]; then
    echo "no ${lfs_directory}/usr/bin/bash" >&2
    echo "chapters 5 and 6 have to finish first: ./build.sh toolchain" >&2
    exit 1
  fi

  mkdir -p "${lfs_directory}"/{dev,proc,sys,run,sources,toolchain}

  # LFS 7.3.1. The book bind-mounts the host's /dev rather than mounting a
  # devtmpfs, because it will not assume the host kernel has one. This one
  # does, but the bind is what the book specifies and it behaves identically
  # here.
  mountpoint -q "${lfs_directory}/dev" || mount --bind /dev "${lfs_directory}/dev"

  # gid=5 is the tty group and mode=0620 is what grantpt() expects. Named by
  # number because the host's tty group may have a different one, and it is
  # the *chroot's* /etc/group that matters -- where 5 is tty, as written by
  # the layout step.
  mkdir -p "${lfs_directory}/dev/pts"
  mountpoint -q "${lfs_directory}/dev/pts" ||
    mount -t devpts devpts -o gid=5,mode=0620 "${lfs_directory}/dev/pts"

  mountpoint -q "${lfs_directory}/proc" || mount -t proc  proc  "${lfs_directory}/proc"
  mountpoint -q "${lfs_directory}/sys"  || mount -t sysfs sysfs "${lfs_directory}/sys"
  mountpoint -q "${lfs_directory}/run"  || mount -t tmpfs tmpfs "${lfs_directory}/run"

  # On a host where /dev/shm is a symlink into /run, the bind above already
  # brought the link across and only the directory it names has to exist.
  # Where it is a real mount point, the bind gave us an empty directory and a
  # tmpfs has to go on it.
  if [ -h "${lfs_directory}/dev/shm" ]; then
    install -d -m 1777 "${lfs_directory}$(realpath /dev/shm)"
  else
    mkdir -p "${lfs_directory}/dev/shm"
    mountpoint -q "${lfs_directory}/dev/shm" ||
      mount -t tmpfs -o nosuid,nodev tmpfs "${lfs_directory}/dev/shm"
  fi

  # The two read-only binds. Not in the book, which has you copy the tarballs
  # into $LFS/sources beforehand; this keeps the one copy that already exists
  # in the repository and makes the step scripts reachable by the same trick.
  #
  # Read-only in two steps because "mount --bind -o ro" does not actually
  # apply ro on the first call -- the kernel needs the remount to set it. A
  # writable bind of the repository into the chroot would let a mistaken rm in
  # there reach the source tree, which is the sort of thing worth spending two
  # syscalls to prevent.
  if ! mountpoint -q "${lfs_directory}/sources"; then
    mount --bind "${sources_directory}" "${lfs_directory}/sources"
    mount -o remount,bind,ro "${lfs_directory}/sources"
  fi

  if ! mountpoint -q "${lfs_directory}/toolchain"; then
    mount --bind "${working_directory}/toolchain/chroot" "${lfs_directory}/toolchain"
    mount -o remount,bind,ro "${lfs_directory}/toolchain"
  fi
}

# The chroot invocation itself, LFS 7.4.
#
# env -i again, for the same reason as chapter 5, and this time the book
# agrees. Note what is *not* in PATH: /tools/bin. From here on the cross
# toolchain is finished -- everything runs natively inside the chroot -- and
# leaving it out is what makes that true rather than merely intended.
chroot_run(){
  chroot "${lfs_directory}" /usr/bin/env -i     \
      HOME=/root                                \
      TERM="${TERM:-dumb}"                      \
      PS1='(lfs chroot) \u:\w\$ '               \
      PATH=/usr/bin:/usr/sbin                   \
      MAKEFLAGS="-j$(nproc)"                    \
      TESTSUITEFLAGS="-j$(nproc)"               \
      "$@"
}

build_chroot(){
  local chroot_selector=${1:-}

  chroot_mount

  # Whatever happens below -- a failed build, a Ctrl-C, an exit from the
  # interactive shell -- the mounts come back down.
  trap 'chroot_umount' EXIT

  if [ "${chroot_selector}" == "shell" ] || [ -z "${chroot_selector}" ]; then
    echo "entering ${lfs_directory}; exit to unmount"
    chroot_run /bin/bash --login
    return
  fi

  echo "Building chapter 7 inside ${lfs_directory}"

  local stamp_directory=${lfs_directory}/.toolchain
  mkdir -p "${stamp_directory}"

  local chroot_force=
  local chroot_only=

  case "${chroot_selector}" in
    build|verbose|quiet) ;;
    force)               chroot_force=1 ;;
    *)                   chroot_only=${chroot_selector} ;;
  esac

  local chroot_total
  chroot_total=$(grep -cv -e '^[[:space:]]*$' -e '^[[:space:]]*#' \
                   "${working_directory}/toolchain/chroot/order")

  local chroot_number=0
  local chroot_matched=
  local chroot_have=0
  local chroot_started=${SECONDS}

  local status_was_active=${status_active}
  [ -z "${status_was_active}" ] && status_start
  status_set "starting"

  while read -r step; do
    case "${step}" in ''|\#*) continue ;; esac

    chroot_number=$((chroot_number + 1))

    if [ -n "${chroot_only}" ]; then
      if [ "${step}" != "${chroot_only}" ]; then
        continue
      fi
      chroot_matched=1
    fi

    if [ ! -x "${working_directory}/toolchain/chroot/${step}.sh" ]; then
      status_stop
      echo "  ${step}: no toolchain/chroot/${step}.sh" >&2
      exit 1
    fi

    # chroot-<name>, so these stamps and logs do not collide with the
    # chapter 5 and 6 ones of the same name -- util-linux is in both.
    if [ -f "${stamp_directory}/chroot-${step}" ] &&
       [ -z "${chroot_force}" ] && [ -z "${chroot_only}" ]; then
      echo "  have ${step}"
      chroot_have=$((chroot_have + 1))
      continue
    fi

    echo "  ${step}"
    status_set "chroot ${step}   [${chroot_number}/${chroot_total}]"

    if run "chroot-${step}" chroot_run /bin/bash "/toolchain/${step}.sh"; then
      touch "${stamp_directory}/chroot-${step}"
    else
      status_set "chroot ${step}   FAILED"
      status_stop
      echo >&2
      echo "${step} failed; the log is ${log_directory}/chroot-${step}.log" >&2
      exit 1
    fi
  done < "${working_directory}/toolchain/chroot/order"

  [ -z "${status_was_active}" ] && status_stop

  if [ "${chroot_have}" -ne 0 ]; then
    echo "  ${chroot_have} already built"
  fi

  echo

  if [ -n "${chroot_only}" ] && [ -z "${chroot_matched}" ]; then
    echo "no such chroot step: ${chroot_only}" >&2
    echo "steps are listed in ${working_directory}/toolchain/chroot/order" >&2
    exit 1
  fi

  echo "chapter 7 built in $(format_duration $((SECONDS - chroot_started)))"
}

if [ "$1" == "chroot" ]; then
  case "${2:-}" in
    umount)
      if chroot_umount; then
        echo "unmounted"
      else
        exit 1
      fi
      ;;
    *)
      build_chroot "${2:-}"
      ;;
  esac
  exit
fi

if [ "$1" == "packages" ]; then
  build_packages "${2:-}"
  exit
fi

if [ "$1" == "virt" ]; then
  echo "Virtual Machine"

  pushd virtual_machine

  if [ ! -e disk.raw ]; then
    echo "disk.raw does not exist; create it with ./configure.sh" >&2
    exit 1
  fi

  mkdir -p disk/boot disk/root

  # A free device rather than a hardcoded /dev/loop0, which fails with "Device
  # or resource busy" whenever anything else holds it. This also drops the two
  # unconditional umounts that used to run first and always complained about
  # having no mount point.
  loop=$(losetup -f --show -P disk.raw)
  if [ -z "${loop}" ]; then
    echo "cannot attach disk.raw to a loop device" >&2
    exit 1
  fi

  # Partition nodes are created asynchronously, so they are not there the
  # instant losetup returns
  for _ in $(seq 50); do
    [ -e "${loop}p1" ] && [ -e "${loop}p2" ] && break
    sleep 0.1
  done

  mount "${loop}p1" disk/boot
  mount "${loop}p2" disk/root

  # If a mount silently failed, the writes below would land in the plain
  # directories under the mountpoints instead of the image, and the rm would
  # delete the working tree rather than the image contents.
  if ! mountpoint -q disk/boot || ! mountpoint -q disk/root; then
    echo "mount failed, refusing to touch disk/" >&2
    umount disk/boot 2>/dev/null
    umount disk/root 2>/dev/null
    losetup -d "${loop}"
    exit 1
  fi

  ##### Boot
  mkdir -p disk/boot/EFI/BOOT
  cp ${build_directory}/pboot disk/boot/EFI/BOOT/BOOTX64.EFI
  cp pboot.conf disk/boot

  cp ${build_directory}/vmlinuz disk/boot/vmlinuz

  ##### Root filesystem
  rm -rf disk/root/*

  # -a, not -r: the root filesystem depends on bin/lib/lib64 staying symlinks
  # and on permissions being preserved
  cp -a ${build_directory}/* disk/root

  umount disk/boot
  umount disk/root

  losetup -d "${loop}"

  popd

  echo "disk.raw updated"

  exit
fi

if [ "$1" == "usb" ]; then
  usb_device=$2

  if [ -z "${usb_device}" ]; then
    echo "usage: ./build.sh usb /dev/sdX" >&2
    echo "no default: this erases the device it is given" >&2
    exit 1
  fi

  if [ ! -b "${usb_device}" ]; then
    echo "${usb_device} is not a block device" >&2
    exit 1
  fi

  # Refuse a partition. Handing this /dev/sdb1 and having it repartition
  # /dev/sdb would be a surprise worth avoiding.
  #
  # -d matters: without it lsblk reports the device and its children, and
  # every child names this disk as its parent, so a whole disk looks like a
  # partition and nothing could ever be written.
  if [ -n "$(lsblk -dno PKNAME "${usb_device}" 2>/dev/null)" ]; then
    echo "${usb_device} is a partition; give the whole disk" >&2
    exit 1
  fi

  # The disk this machine is running from, which is the one mistake that
  # cannot be undone
  usb_name=${usb_device#/dev/}
  root_source=$(findmnt -no SOURCE / 2>/dev/null)
  root_disk=$(lsblk -dno PKNAME "${root_source}" 2>/dev/null | head -1)

  if [ -n "${root_disk}" ] && [ "${root_disk}" == "${usb_name}" ]; then
    echo "${usb_device} is the disk this system is running from" >&2
    exit 1
  fi

  if findmnt -rno SOURCE | grep -q "^${usb_device}"; then
    echo "${usb_device} has mounted partitions; unmount them first" >&2
    findmnt -rno SOURCE,TARGET | grep "^${usb_device}" >&2
    exit 1
  fi

  usb_size=$(lsblk -dno SIZE "${usb_device}" 2>/dev/null | tr -d ' ')
  usb_model=$(lsblk -dno MODEL "${usb_device}" 2>/dev/null | sed 's/ *$//')
  usb_removable=$(lsblk -dno RM "${usb_device}" 2>/dev/null | tr -d ' ')

  echo "About to erase ${usb_device}"
  echo "  model     ${usb_model:-unknown}"
  echo "  size      ${usb_size:-unknown}"
  echo "  removable ${usb_removable:-unknown}"

  if [ "${usb_removable}" != "1" ]; then
    echo "  warning: this device does not report itself as removable" >&2
  fi

  # USB_YES=1 for a scripted run. Typed confirmation otherwise, and not y/n:
  # the whole point is that it should not be reachable by leaning on return.
  if [ "${USB_YES:-}" != "1" ]; then
    printf "Type ERASE to continue: "
    read -r usb_answer
    if [ "${usb_answer}" != "ERASE" ]; then
      echo "cancelled"
      exit 1
    fi
  fi

  echo "Partitioning ${usb_device}"

  # 256M ESP, the rest for the root filesystem. The partition type GUIDs are
  # what the firmware looks for: C12A7328 marks the EFI system partition and
  # 0FC63DAF is a plain Linux filesystem.
  sfdisk --quiet --wipe always --wipe-partitions always "${usb_device}" <<'PARTITIONS'
label: gpt
size=256M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI System"
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="plinux root"
PARTITIONS

  partprobe "${usb_device}" 2>/dev/null || true
  udevadm settle 2>/dev/null || true

  # Partition nodes appear asynchronously, the same way they do for the loop
  # device in the virt step. p1/p2 on nvme and mmc, 1/2 on everything else.
  if [ -b "${usb_device}p1" ]; then
    usb_esp=${usb_device}p1
    usb_root=${usb_device}p2
  else
    usb_esp=${usb_device}1
    usb_root=${usb_device}2
  fi

  for _ in $(seq 50); do
    [ -b "${usb_esp}" ] && [ -b "${usb_root}" ] && break
    sleep 0.1
  done

  if [ ! -b "${usb_esp}" ] || [ ! -b "${usb_root}" ]; then
    echo "partitions did not appear on ${usb_device}" >&2
    exit 1
  fi

  echo "Making filesystems"

  # mkfs.fat, not mkfs.vfat: dosfstools installs the vfat name only as a
  # compatibility symlink, and this build host does not have it. FAT32
  # because it is what UEFI implementations agree on for removable media.
  mkfs.fat -F 32 -n PLINUXESP "${usb_esp}" > /dev/null
  mkfs.ext4 -q -F -L plinuxroot "${usb_root}"

  udevadm settle 2>/dev/null || true

  # Read back what the filesystems and the partition table actually got,
  # rather than assuming a value and writing it into the configuration.
  #
  # These are two different kinds of identifier and they are not
  # interchangeable. The kernel resolves root=PARTUUID= on its own, from the
  # GPT, before any filesystem is mounted -- root=UUID= would need an
  # initramfs to run blkid, which this system does not have. /etc/fstab is
  # read later by mount(8), which does have libblkid, so UUID= is right
  # there.
  usb_root_partuuid=$(blkid -s PARTUUID -o value "${usb_root}")
  usb_esp_uuid=$(blkid -s UUID -o value "${usb_esp}")

  if [ -z "${usb_root_partuuid}" ] || [ -z "${usb_esp_uuid}" ]; then
    echo "cannot read the identifiers back from ${usb_device}" >&2
    exit 1
  fi

  echo "  root PARTUUID ${usb_root_partuuid}"
  echo "  ESP UUID      ${usb_esp_uuid}"

  usb_mount=$(mktemp -d)
  mkdir -p "${usb_mount}/boot" "${usb_mount}/root"

  mount "${usb_esp}"  "${usb_mount}/boot"
  mount "${usb_root}" "${usb_mount}/root"

  if ! mountpoint -q "${usb_mount}/boot" || ! mountpoint -q "${usb_mount}/root"; then
    echo "mount failed, refusing to write" >&2
    umount "${usb_mount}/boot" 2>/dev/null
    umount "${usb_mount}/root" 2>/dev/null
    rmdir "${usb_mount}/boot" "${usb_mount}/root" "${usb_mount}" 2>/dev/null
    exit 1
  fi

  echo "Copying the system"

  mkdir -p "${usb_mount}/boot/EFI/BOOT"
  cp ${build_directory}/pboot   "${usb_mount}/boot/EFI/BOOT/BOOTX64.EFI"
  cp ${build_directory}/vmlinuz "${usb_mount}/boot/vmlinuz"

  # Written here rather than copied from virtual_machine/pboot.conf, which
  # names the VM's disk. Every stick gets its own root=, so one that is
  # plugged into a machine that already runs plinux still boots itself:
  # sharing a PARTUUID with the internal disk would leave the kernel to pick
  # whichever it enumerated first, which for a rescue disk is the wrong one.
  cat > "${usb_mount}/boot/pboot.conf" <<CONFIGURATION
m 0
e 0
n "plinux"
k "vmlinuz"
p "root=PARTUUID=${usb_root_partuuid} rw init=/pinit rootwait console=tty0 console=ttyS0,115200"
CONFIGURATION

  # -a for the same reason as the virt step: bin, lib and lib64 have to stay
  # symlinks and the permissions have to survive
  cp -a ${build_directory}/* "${usb_mount}/root"

  # This stick's own fstab. The image ships one describing the VM disk, and
  # /dev/nvme0n1p1 does not exist here.
  cat > "${usb_mount}/root/etc/fstab" <<FSTAB
# /etc/fstab for a plinux rescue disk, written by ./build.sh usb
#
# UUID rather than a device name: this disk is /dev/sda on one machine and
# /dev/sdc on the next. mount(8) resolves UUID= through libblkid.
UUID=${usb_esp_uuid}  /boot  vfat  defaults,noauto  0 0
FSTAB

  sync

  umount "${usb_mount}/boot"
  umount "${usb_mount}/root"
  rmdir "${usb_mount}/boot" "${usb_mount}/root" "${usb_mount}" 2>/dev/null

  echo "${usb_device} is ready"
  exit
fi

if [ "$1" == "clean" ]; then
  # Never delete anything while the chroot's mounts are up. /dev is bind
  # mounted into lfs/ at that point, and "clean all" removes obj/ rather than
  # lfs/ -- but the margin between those two is not where this should be
  # relying on getting a path right.
  if chroot_mounted_any; then
    echo "the chroot is still mounted; refusing to clean" >&2
    echo "run ./build.sh chroot umount first" >&2
    exit 1
  fi

  echo "Cleaning source trees"

  for component in pboot linux pinit pgetty plogin; do
    if [ -d ${src_directory}/${component} ]; then
      echo "  ${component}"
      pushd ${src_directory}/${component}
      make clean &> /dev/null
      popd
    fi
  done

  # bash keeps a configure-generated Makefile; distclean removes it so the
  # next build reconfigures with the right prefix
  if [ -f ${src_directory}/bash/Makefile ]; then
    echo "  bash"
    pushd ${src_directory}/bash
    make distclean &> /dev/null
    popd
  fi

  # The package trees are unpacked tarballs, not clones, so they are removed
  # rather than "make clean"ed: the tarball is the source of truth and the
  # unpacked directory is itself a build artifact. This also drops any patches
  # applied in place, which "make clean" would leave behind.
  #
  # Only directories that can be recreated are removed. A versioned name with
  # no matching tarball in sources/ is left alone, so nothing unrecoverable
  # goes: re-extracting it would be impossible without downloading again.
  #
  # Installed packages are not affected. Their stamps live in obj and say the
  # package is installed in *that* tree, which is still true; "clean all"
  # removes obj and takes the stamps with it.
  removed=0

  for tree in ${src_directory}/*-[0-9]*/; do
    [ -d "${tree}" ] || continue

    name=$(basename "${tree}")

    if ! ls "${sources_directory}/${name}".tar.* > /dev/null 2>&1; then
      echo "  keeping ${name}, no tarball to unpack it from again"
      continue
    fi

    echo "  ${name}"
    rm -rf "${tree}"
    removed=$((removed + 1))
  done

  if [ "${removed}" -ne 0 ]; then
    echo "removed ${removed} package tree(s); they unpack again on the next build"
  fi

  # "clean all" also discards the staged root filesystem
  if [ "$2" == "all" ]; then
    if [ -n "${build_directory}" ] && [ -d "${build_directory}" ]; then
      echo "Removing ${build_directory}"
      rm -rf "${build_directory}"
    fi
  fi

  exit

fi

################## Build ###################

stage(){
  if [ ! -f "$1" ]; then
    echo "  FAILED: $1 was not produced" >&2
    return 1
  fi

  if ! cp "$1" "$2"; then
    echo "  FAILED: cannot copy $1 to $2" >&2
    return 1
  fi

  return 0
}

# Sources come and go as components move to their own repositories, so a
# missing tree is reported and skipped instead of aborting the whole build.
have_source(){
  echo "$1"
  status_set "$1"

  if [ ! -d "$2" ]; then
    echo "  skipping, $2 is not present" >&2
    status_set "$1   skipped, no source"
    skipped=$((skipped + 1))
    return 1
  fi

  return 0
}

# Every component below announces itself through have_source, so the status
# line follows the build without each step having to set it.
status_start

if have_source "Building bootloader" ${src_directory}/pboot; then
  pushd ${src_directory}/pboot
  # the Makefile's target is pboot.efi; pboot alone is the raw pboot.bin stage
  if run pboot make; then
    stage pboot.efi ${build_directory}/pboot || failed=$((failed + 1))
  else
    failed=$((failed + 1))
  fi
  popd
fi

if have_source "Building kernel" ${src_directory}/linux; then
  pushd ${src_directory}/linux

  # ./configure normally puts this in place; do it here too so a build works on
  # a tree that was cloned by hand
  if [ ! -f .config ]; then
    cp ${working_directory}/sys/kernel_config .config
  fi

  # The config was saved from 6.14.6 and the clone tracks mainline, so it will
  # be missing symbols the current kernel has added. olddefconfig takes the
  # default for each of them instead of prompting and stalling the build.
  # Refreshed with the kernel, so a config or version change that adds an
  # ioctl or a structure field reaches the packages built against it.
  run kernel-headers make headers_install INSTALL_HDR_PATH=${build_directory}/usr \
    || failed=$((failed + 1))

  if run kernel-config make olddefconfig && run kernel make; then
    # x86_64 was merged into arch/x86 in 2.6.24; arch/x86_64 has not existed
    # for a very long time
    stage arch/x86/boot/bzImage ${build_directory}/vmlinuz || failed=$((failed + 1))

    # The config builds around 40 modules, amdgpu among them, and none of
    # them used to be installed: the image booted with no GPU driver at all
    # on real hardware. The VM hid this, because virtio-gpu is built in.
    #
    # INSTALL_MOD_PATH ends in /usr on purpose. The kernel appends
    # "lib/modules" to it, and obj/lib is a symlink; back when it pointed at
    # ../../../usr/lib, passing obj alone here installed this kernel's modules
    # over the build machine's own. The symlink is relative now, so both spell
    # the same directory, but naming the real path leaves nothing to resolve.
    if ! run kernel-modules make modules_install       \
             INSTALL_MOD_PATH=${build_directory}/usr   \
             INSTALL_MOD_STRIP=1; then
      failed=$((failed + 1))
    fi
  else
    failed=$((failed + 1))
  fi

  popd
fi

# Firmware the drivers ask the kernel for at probe time. Not built from
# anything here: these are redistributable blobs, taken from the build host,
# which is the machine the image is for.
#
# Only what this hardware loads. All of /usr/lib/firmware is 1.1G against a
# 922M root partition, so copying the lot is not an option even if it were
# worth it.
if [ -d "${firmware_source}" ]; then
  echo "Installing firmware"

  mkdir -p ${build_directory}/usr/lib/firmware

  for entry in "${firmware_wanted[@]}"; do
    # A glob that matches nothing expands to itself, which would then be
    # reported as a missing file. Let the shell tell us instead.
    for match in ${firmware_source}/${entry}; do
      if [ -e "${match}" ]; then
        cp -a "${match}" ${build_directory}/usr/lib/firmware/
      else
        echo "  no firmware matching ${entry}" >&2
      fi
    done
  done
fi

if have_source "Building init PID 1" ${src_directory}/pinit; then
  pushd ${src_directory}/pinit
  if run pinit make; then
    stage pinit ${build_directory}/pinit || failed=$((failed + 1))
  else
    failed=$((failed + 1))
  fi
  popd
fi

# The daemon supervisor. Into /usr/sbin rather than / like pinit: pinit has
# to be at a path the kernel is told about in pboot.conf, this one only has
# to be on a path pinit can exec.
if have_source "Building daemon supervisor" ${src_directory}/pdaemon; then
  pushd ${src_directory}/pdaemon
  if run pdaemon make; then
    stage pdaemon ${build_directory}/usr/sbin/pdaemon || failed=$((failed + 1))
  else
    failed=$((failed + 1))
  fi
  popd
fi

if have_source "Building getty" ${src_directory}/pgetty; then
  pushd ${src_directory}/pgetty
  if run pgetty make; then
    stage pgetty ${build_directory}/usr/bin/pgetty || failed=$((failed + 1))
  else
    failed=$((failed + 1))
  fi
  popd
fi

if have_source "Building login" ${src_directory}/plogin; then
  pushd ${src_directory}/plogin
  if run plogin make; then
    # must match LOGIN_PROGRAM in src/pgetty/main.c
    stage plogin ${build_directory}/usr/bin/plogin || failed=$((failed + 1))
  else
    failed=$((failed + 1))
  fi
  popd
fi

# bash is a package now, in packages/order. It was a component here, and the
# component steps have no stamps: every ./build.sh reran build_static.sh,
# which began by throwing away its own objects, so bash reconfigured and
# recompiled from zero each time. That was seventeen seconds of a
# twenty-five-second no-op build, for a tree that never changes.


# glibc is built by packages/glibc.sh, from the tarball download.sh fetches.
# The step that used to be here worked on src/glibc, a clone that no longer
# exists, so every build printed "Building glibc" and then skipped it. It also
# predated the fhs patch and the configparms rootsbindir the package sets.


# The packages, after the components: one plain ./build.sh produces the
# whole image now. After rather than before, because the thing most
# recently edited is almost always a component, and its build -- or its
# failure -- should surface first, not behind a walk of the order file.
build_packages "" brief

echo "Installing system configuration"
status_set "Installing system configuration"

mkdir -p ${build_directory}/root
mkdir -p ${build_directory}/etc

# Everything under sys/etc, whatever it is, rather than a cp line per file.
# There are two sources of /etc in this image and they are not the same kind
# of thing:
#
#   packages install their own defaults straight into obj/etc through
#   DESTDIR -- mke2fs.conf, vimrc, dbus-1/, ssl/, xattr.conf, udev/. Those
#   are build output. "clean all" deletes them and rebuilding puts them back,
#   so editing one there does not survive
#
#   sys/etc is this machine's configuration, kept in the repository. Adding a
#   file here used to mean adding a cp line as well, which is why it held
#   only passwd, group and fstab
#
# Copied last, after the components and the packages both, so the machine's
# version wins over a package default of the same name. A bare "./build.sh
# packages" can still put a default back on top; the next plain build fixes
# it.
#
# What is in there today:
#   passwd, group  without a user database getpwuid(0) fails and bash's \u
#                  shows "I have no name!". Nothing authenticates yet: plogin
#                  execs the shell directly, and the x defers to an
#                  /etc/shadow that does not exist, so no password is valid
#                  rather than none being needed
#   fstab          pinit runs "mount -a -F" over it, so this decides what the
#                  image mounts. The workstation keeps its own; this one
#                  describes the VM disk
cp -a ${working_directory}/sys/etc/. ${build_directory}/etc/

# plogin sets HOME=/root and chdir()s there, so without these the login shell
# falls back to bash's default prompt and none of this configuration loads.
cp ${working_directory}/sys/root/.bash_profile ${build_directory}/root/
cp ${working_directory}/sys/root/.bashrc       ${build_directory}/root/

# .bashrc looks for the repo copy first and this one second; on the target
# there is no /root/plinux, so this is the one that gets sourced
cp ${working_directory}/sys/root/shell_config.sh ${build_directory}/root/

# on the workstation these are reached through /root/plinux/sys/scripts on
# PATH, which does not exist on the target
cp ${working_directory}/sys/scripts/* ${build_directory}/usr/bin/

status_stop

echo
if [ "${skipped}" -ne 0 ]; then
  echo "${skipped} component(s) skipped for missing sources"
fi

if [ "${failed}" -ne 0 ]; then
  echo "${failed} component(s) failed; logs are in ${log_directory}" >&2
  exit 1
fi

echo "SUCCESS you have plinux in $(format_duration ${SECONDS})"
exit
