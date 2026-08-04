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
  (none)      Build everything: pboot, kernel, pinit, pgetty, plogin,
              bash and glibc, installing each into obj/
  virt        Copy obj/ and the bootloader into virtual_machine/disk.raw.
              Builds nothing, so run a plain ./build.sh first if any
              source changed
  clean       Clean every source tree, bash's configure output and
              glibc's out-of-tree build directory
  clean all   As above, and delete obj/ entirely
  tools       Accepted but does nothing; the cross toolchain section at
              the end of this script is unreachable
  help        This message

Notes:
  Can be run from any directory; paths resolve relative to the script.
  virt needs root: it uses losetup and mount.
  Components are built with MAKEFLAGS=-j32.

Examples:
  ./build.sh              # full build into obj/
  ./build.sh virt         # push obj/ into the VM image
  ./build.sh clean all    # start over
USAGE
}

if [ "$1" == "help" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
  usage
  exit 0
fi

# Without this an unrecognised argument falls through to a full build, so a
# typo like "./build.sh vrit" rebuilds everything instead of staging the image
case "${1:-}" in
  ""|virt|clean|tools) ;;
  *)
    echo "unknown command: $1" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac

if [ ! -d obj ];then
  mkdir obj
  mkdir -p obj/usr/bin
  mkdir -p obj/usr/lib
  mkdir -p obj/sbin
  mkdir -p obj/dev
  mkdir -p obj/proc

  # These resolve to /usr/... once the tree is the root filesystem, because
  # ".." at "/" is "/". They are dangling here in the build tree.
  ln -sf ../../../usr/bin obj/bin
  ln -sf ../../../usr/lib obj/lib
  # ELF binaries hardcode /lib64/ld-linux-x86-64.so.2 as their interpreter
  ln -sf ../../../usr/lib obj/lib64
fi

# added after the original skeleton, so create it for existing trees too
if [ ! -e obj/lib64 ];then
  ln -sf ../../../usr/lib obj/lib64
fi

if [ -d obj ];then

  musl_directory=${build_directory}

  target=$(uname -m)-plinux-gnu
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

if [ "$1" == "tools" ]; then
  echo "building tools"
else
  echo "Building standard"
fi

if [ "$1" == "clean" ]; then
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

  # glibc builds out of tree, so the build directory is the whole of it
  if [ -d ${src_directory}/glibc/build ]; then
    echo "  glibc"
    rm -rf ${src_directory}/glibc/build
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

log_directory=${working_directory}/logs
mkdir -p "${log_directory}"

failed=0
skipped=0

# Output goes to a log rather than /dev/null, and only the tail is shown when
# something breaks. Discarding it meant a failed build was reported as nothing
# more than the "cp" that came after it.
run(){
  local name=$1
  shift

  if "$@" > "${log_directory}/${name}.log" 2>&1; then
    return 0
  fi

  echo "  FAILED: $*" >&2
  echo "  last lines of ${log_directory}/${name}.log:" >&2
  sed 's/^/    /' <<< "$(tail -15 "${log_directory}/${name}.log")" >&2
  return 1
}

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

  if [ ! -d "$2" ]; then
    echo "  skipping, $2 is not present" >&2
    skipped=$((skipped + 1))
    return 1
  fi

  return 0
}

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
  if run kernel-config make olddefconfig && run kernel make; then
    # x86_64 was merged into arch/x86 in 2.6.24; arch/x86_64 has not existed
    # for a very long time
    stage arch/x86/boot/bzImage ${build_directory}/vmlinuz || failed=$((failed + 1))
  else
    failed=$((failed + 1))
  fi

  popd
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

if have_source "Building bash" ${src_directory}/bash; then
  pushd ${src_directory}/bash
  # Static against musl, with bash's bundled termcap. A dynamic bash would pull
  # in libncursesw.so.6, which nothing in src/ builds.
  if run bash ./build_static.sh; then
    stage bash ${build_directory}/usr/bin/bash || failed=$((failed + 1))
  else
    failed=$((failed + 1))
  fi
  popd
fi


if have_source "Building glibc" ${src_directory}/glibc; then
  pushd ${src_directory}/glibc

  mkdir -p build
  pushd build

  # libc_cv_slibdir is an absolute path inside the image. Without DESTDIR on
  # the install, this writes libc.so.6 and the dynamic loader straight into the
  # host's /usr/lib and replaces the running system's glibc.
  if run glibc-configure ../configure --prefix=/usr \
             --disable-werror                       \
             --disable-nscd                         \
             libc_cv_slibdir=/usr/lib               \
             --enable-stack-protector=strong        \
             --enable-kernel=5.4                    \
     && run glibc make                              \
     && run glibc-install make DESTDIR=${build_directory} install; then
    :
  else
    failed=$((failed + 1))
  fi

  popd
  popd
fi


echo "Installing system configuration"

mkdir -p ${build_directory}/root

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


echo
if [ "${skipped}" -ne 0 ]; then
  echo "${skipped} component(s) skipped for missing sources"
fi

if [ "${failed}" -ne 0 ]; then
  echo "${failed} component(s) failed; logs are in ${log_directory}" >&2
  exit 1
fi

echo "SUCCESS you have plinux"
exit


################## Toolchain ###################

build_directory=""
src_directory=""
musl_directory=""

if [ -d obj ];then

  pushd ${src_directory}

  echo "############# Building Binutils"
  pushd ${src_directory}/binutils
  mkdir obj
  pushd ${src_directory}/binutils/obj
  ../configure --prefix=${build_directory}/tools \
             --with-sysroot=${build_directory} \
             --target=${target}       \
             --disable-nls       \
             --enable-gprofng=no \
             --disable-werror    \
             --enable-new-dtags  \
             --enable-default-hash-style=gnu
  make -j32
  make -j32 install

  popd #src


  pushd ${src_directory}/gcc

  mkdir obj
  pushd ${src_directory}/gcc/obj

  ../configure                              \
    --target=${target}                      \
    --prefix=${build_directory}/tools       \
    --with-glibc-version=2.41               \
    --with-sysroot=${build_directory}       \
    --with-newlib             \
    --without-headers         \
    --enable-default-pie      \
    --enable-default-ssp      \
    --disable-nls             \
    --disable-shared          \
    --disable-multilib        \
    --disable-threads         \
    --disable-libatomic       \
    --disable-libgomp         \
    --disable-libquadmath     \
    --disable-libssp          \
    --disable-libvtv          \
    --disable-libstdcxx       \
    --enable-languages=c,c++

  make -j32
  make install


  popd #src

else
  mkdir -p obj/tools
fi
