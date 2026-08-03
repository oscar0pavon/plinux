#!/bin/bash
# uses pushd/popd and [ "$1" == ... ], so it needs bash and not plain sh

export MAKEFLAGS=-j32

working_directory=$(pwd)
src_directory=${working_directory}/src
build_directory=${working_directory}/obj

pushd(){
  command pushd "$@" > /dev/null
}

popd(){
  command popd "$@" > /dev/null
}

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
  
  umount /dev/loop0p1
  umount /dev/loop0p2

  pushd virtual_machine

  losetup -P /dev/loop0 disk.raw
  
  mount /dev/loop0p1 disk/boot
  mount /dev/loop0p2 disk/root

  # If a mount silently failed, the writes below would land in the plain
  # directories under the mountpoints instead of the image, and the rm would
  # delete the working tree rather than the image contents.
  if ! mountpoint -q disk/boot || ! mountpoint -q disk/root; then
    echo "mount failed, refusing to touch disk/"
    losetup -d /dev/loop0
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

  umount /dev/loop0p1
  umount /dev/loop0p2

  losetup -d /dev/loop0

  popd

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

pushd ${src_directory}/pboot
echo "Building bootloader"
make &> /dev/null

cp pboot ${build_directory}/pboot

popd

pushd ${src_directory}/linux

echo "Building kernel"

make pavon_defconfig &> /dev/null

make &> /dev/null

cp arch/x86_64/boot/bzImage ${build_directory}/vmlinuz

popd


echo "Building init PID 1"

pushd ${src_directory}/pinit

make &> /dev/null

cp pinit ${build_directory}/pinit

popd


echo "Building getty"

pushd ${src_directory}/pgetty

make &> /dev/null

cp pgetty ${build_directory}/usr/bin

popd



echo "Building login"

pushd ${src_directory}/plogin

make &> /dev/null

# must match LOGIN_PROGRAM in src/pgetty/main.c
cp plogin ${build_directory}/usr/bin/plogin

popd



echo "Building bash"

pushd ${src_directory}/bash

# Static against musl, with bash's bundled termcap. A dynamic bash would pull
# in libncursesw.so.6, which nothing in src/ builds.
./build_static.sh &> /dev/null

cp bash ${build_directory}/usr/bin/bash

popd


echo "Building glibc"

pushd ${src_directory}/glibc

mkdir -p build
pushd build

# libc_cv_slibdir is an absolute path inside the image. Without DESTDIR on
# the install, this writes libc.so.6 and the dynamic loader straight into the
# host's /usr/lib and replaces the running system's glibc.
../configure --prefix=/usr                   \
             --disable-werror                \
             --disable-nscd                  \
             libc_cv_slibdir=/usr/lib        \
             --enable-stack-protector=strong \
             --enable-kernel=5.4 &> /dev/null

make &> /dev/null

make DESTDIR=${build_directory} install &> /dev/null

popd
popd


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
